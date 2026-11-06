// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// One node of a Space Lens size map.
///
/// Folders keep their largest children; small files and the long tail are folded into
/// "other" nodes so a whole-disk map stays small enough to hold in memory and draw.
public struct DiskNode: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable {
        case folder
        case package   // .app and other bundles: drawn like a file, can still be opened
        case file
        /// Aggregate of items too small to list ("1,204 smaller items").
        case other(count: Int)
    }

    public let id: String
    public let name: String
    public let path: String
    public let kind: Kind
    /// Bytes allocated on disk, including everything below.
    public let size: Int64
    /// Files and folders below (including this one).
    public let itemCount: Int
    /// Largest first.
    public let children: [DiskNode]
    /// Part of the tree could not be read (permissions), so `size` is a lower bound.
    public let isPartial: Bool

    public var url: URL { URL(fileURLWithPath: path) }
    public var isContainer: Bool { kind == .folder && !children.isEmpty }

    // Trees are immutable snapshots, so identity + size + count identify a node. Comparing
    // shallowly keeps SwiftUI's view diffing O(1) instead of walking millions of nodes.
    public static func == (lhs: DiskNode, rhs: DiskNode) -> Bool {
        lhs.id == rhs.id && lhs.size == rhs.size && lhs.itemCount == rhs.itemCount
            && lhs.children.count == rhs.children.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(size)
    }

    public init(id: String? = nil, name: String, path: String, kind: Kind, size: Int64, itemCount: Int,
                children: [DiskNode] = [], isPartial: Bool = false) {
        self.id = id ?? path
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.itemCount = itemCount
        self.children = children
        self.isPartial = isPartial
    }
}

public enum DiskScanEvent: Sendable {
    /// Incremental counts since the previous progress event of the same worker.
    case progress(items: Int, bytes: Int64)
    /// A top-level folder finished, so the map can grow while the rest is scanned.
    case topLevelFinished(DiskNode)
    case finished(DiskNode)
}

/// Builds a `DiskNode` tree with `getattrlistbulk(2)`: one system call returns a whole folder's
/// names, types and sizes, with one open file at a time per worker. Never follows symlinks,
/// stays on one volume, counts hard-linked files once, and scans the top two folder levels in
/// parallel so one huge folder (say `~/development`) doesn't serialise the whole scan.
public struct DiskScanner: Sendable {
    /// Children kept per folder; the rest fold into an "other" node.
    public let maxChildren: Int
    /// Files smaller than this are folded into their folder's "small files" node.
    public let minFileSize: Int64
    /// Folders smaller than this keep no children (shown as one block) to keep big maps lean.
    public let pruneBelow: Int64
    /// Folder levels below the root that are scanned in parallel.
    public let parallelDepth: Int

    public init(maxChildren: Int = 60, minFileSize: Int64 = 2_000_000, pruneBelow: Int64 = 2_000_000,
                parallelDepth: Int = 2) {
        self.maxChildren = maxChildren
        self.minFileSize = minFileSize
        self.pruneBelow = pruneBelow
        self.parallelDepth = parallelDepth
    }

    public func events(for root: URL) -> AsyncStream<DiskScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                let node = await scan(root,
                                      progress: { items, bytes in continuation.yield(.progress(items: items, bytes: bytes)) },
                                      onTopLevel: { continuation.yield(.topLevelFinished($0)) })
                if !Task.isCancelled { continuation.yield(.finished(node)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func scan(_ root: URL,
                     progress: @escaping @Sendable (Int, Int64) -> Void = { _, _ in },
                     onTopLevel: @escaping @Sendable (DiskNode) -> Void = { _ in }) async -> DiskNode {
        let path = root.standardizedFileURL.path
        let device = FileStat.lstatInfo(root).map { Int32($0.st_dev) } ?? 0
        let name = path == "/" ? "/" : (path as NSString).lastPathComponent
        return await scanFolder(path: path, name: name, device: device, depth: 0, links: HardLinks(),
                                progress: progress, onChild: onTopLevel)
    }

    /// Reads one folder, then scans its subfolders — in parallel near the top, sequentially below.
    private func scanFolder(path: String, name: String, device: Int32, depth: Int, links: HardLinks,
                            progress: @escaping @Sendable (Int, Int64) -> Void,
                            onChild: @Sendable (DiskNode) -> Void = { _ in }) async -> DiskNode {
        var reader = BulkReader(links: links)
        var builder = FolderBuilder(name: name, path: path)
        let subfolders = reader.read(path: path, device: device, minFileSize: minFileSize, into: &builder)
        reader.flush(progress)

        if depth < parallelDepth {
            let children = await withTaskGroup(of: DiskNode.self) { group in
                for sub in subfolders {
                    group.addTask {
                        await scanFolder(path: sub.path, name: sub.name, device: device, depth: depth + 1, links: links,
                                         progress: progress)
                    }
                }
                var nodes: [DiskNode] = []
                for await node in group {
                    nodes.append(node)
                    onChild(node)
                }
                return nodes
            }
            for child in children { builder.add(child) }
        } else {
            for sub in subfolders {
                if Task.isCancelled { break }
                builder.add(scanSequential(path: sub.path, name: sub.name, device: device, reader: &reader, progress: progress))
            }
            reader.flush(progress)
        }
        builder.items += 1
        // The scan root is never pruned.
        return builder.finish(maxChildren: maxChildren, pruneBelow: depth == 0 ? 0 : pruneBelow)
    }

    private func scanSequential(path: String, name: String, device: Int32, reader: inout BulkReader,
                                progress: @Sendable (Int, Int64) -> Void) -> DiskNode {
        var builder = FolderBuilder(name: name, path: path)
        let subfolders = reader.read(path: path, device: device, minFileSize: minFileSize, into: &builder)
        if reader.pendingItems >= 5_000 { reader.flush(progress) }
        for sub in subfolders {
            if Task.isCancelled { break }
            builder.add(scanSequential(path: sub.path, name: sub.name, device: device, reader: &reader, progress: progress))
        }
        builder.items += 1
        return builder.finish(maxChildren: maxChildren, pruneBelow: pruneBelow)
    }
}

/// A `getattrlistbulk` buffer that frees itself (a raw allocation in a struct would leak).
final class ScanBuffer {
    static let size = 256 * 1024
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: ScanBuffer.size, alignment: 16)
    deinit { pointer.deallocate() }
}

/// Files with several hard links, seen by any worker: each is counted once in the whole scan,
/// not once per folder that happens to be scanned in parallel.
final class HardLinks: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<UInt64> = []
    /// True the first time an inode is seen.
    func insert(_ inode: UInt64) -> Bool { lock.withLock { seen.insert(inode).inserted } }
}

/// Per-worker `getattrlistbulk` state: a reusable buffer and progress counters.
struct BulkReader {
    struct Subfolder { let name: String; let path: String }

    private let storage = ScanBuffer()
    private var buffer: UnsafeMutableRawPointer { storage.pointer }
    private static var bufferSize: Int { ScanBuffer.size }
    private let links: HardLinks

    init(links: HardLinks = HardLinks()) {
        self.links = links
    }
    private(set) var pendingItems = 0
    private var pendingBytes: Int64 = 0

    // Requested attributes. With FSOPT_PACK_INVAL_ATTRS every entry has the same layout:
    // length, returned-attrs set, error, name ref, devid, objtype, fileid, linkcount, allocsize.
    private static var attributes: attrlist {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID) | attrgroup_t(ATTR_CMN_ERROR)
        list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
        return list
    }

    mutating func flush(_ progress: (Int, Int64) -> Void) {
        guard pendingItems > 0 else { return }
        progress(pendingItems, pendingBytes)
        pendingItems = 0
        pendingBytes = 0
    }

    /// Adds the folder's files to `builder` and returns its subfolders (same volume only).
    mutating func read(path: String, device: Int32, minFileSize: Int64, into builder: inout FolderBuilder) -> [Subfolder] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            builder.isPartial = true
            return []
        }
        defer { close(fd) }

        var list = Self.attributes
        var subfolders: [Subfolder] = []
        let base = path == "/" ? "" : path
        while true {
            let count = getattrlistbulk(fd, &list, buffer, Self.bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if count < 0 { builder.isPartial = true; break }
            if count == 0 { break }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                var cursor = entry + 4 + MemoryLayout<attribute_set_t>.size
                // ATTR_CMN_ERROR comes right after the returned-attributes set (getattrlist(2)),
                // the rest follow in bit order.
                let error = cursor.loadUnaligned(as: UInt32.self); cursor += 4
                let nameRef = cursor.loadUnaligned(as: attrreference_t.self)
                let namePointer = (cursor + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                cursor += MemoryLayout<attrreference_t>.size
                let entryDevice = cursor.loadUnaligned(as: Int32.self); cursor += 4
                let objectType = cursor.loadUnaligned(as: UInt32.self); cursor += 4
                let fileID = cursor.loadUnaligned(as: UInt64.self); cursor += 8
                let linkCount = cursor.loadUnaligned(as: UInt32.self); cursor += 4
                let allocated = cursor.loadUnaligned(as: Int64.self)
                entry += length

                if error != 0 { builder.isPartial = true; continue }
                switch objectType {
                case 2: // VDIR
                    guard entryDevice == device else { continue } // a mount point: another volume
                    let name = String(cString: namePointer)
                    subfolders.append(Subfolder(name: name, path: base + "/" + name))
                case 1, 5: // VREG, VLNK (a link's own size; never followed)
                    if objectType == 1, linkCount > 1, !links.insert(fileID) { continue }
                    pendingItems += 1
                    pendingBytes += allocated
                    if allocated >= minFileSize {
                        let name = String(cString: namePointer)
                        builder.addFile(name: name, path: base + "/" + name, size: allocated, keepAsChild: true)
                    } else {
                        builder.addSmallFile(size: allocated)
                    }
                default:
                    continue
                }
            }
        }
        return subfolders
    }
}

/// Accumulates one folder during the walk.
struct FolderBuilder {
    let name: String
    let path: String
    var size: Int64 = 0
    var items = 0
    var children: [DiskNode] = []
    var smallFilesSize: Int64 = 0
    var smallFilesCount = 0
    var isPartial = false

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    mutating func addFile(name: String, path: String, size: Int64, keepAsChild: Bool) {
        self.size += size
        items += 1
        if keepAsChild {
            let isPackage = (path as NSString).pathExtension == "app"
            children.append(DiskNode(name: name, path: path, kind: isPackage ? .package : .file,
                                     size: size, itemCount: 1))
        } else {
            smallFilesSize += size
            smallFilesCount += 1
        }
    }

    mutating func addSmallFile(size: Int64) {
        self.size += size
        items += 1
        smallFilesSize += size
        smallFilesCount += 1
    }

    mutating func add(_ child: DiskNode) {
        size += child.size
        items += child.itemCount
        // Bundles read as one object in the map.
        if child.kind == .folder, (child.path as NSString).pathExtension == "app" {
            children.append(DiskNode(name: child.name, path: child.path, kind: .package, size: child.size,
                                     itemCount: child.itemCount, isPartial: child.isPartial))
        } else {
            children.append(child)
        }
        if child.isPartial { isPartial = true }
    }

    /// Sorts children, keeps the largest `maxChildren`, folds the rest and small files into "other".
    /// Folders under `pruneBelow` keep no children: they show as one block, which keeps a
    /// whole-disk map (hundreds of thousands of folders) small in memory.
    func finish(maxChildren: Int, pruneBelow: Int64) -> DiskNode {
        if size < pruneBelow {
            return DiskNode(name: name, path: path, kind: .folder, size: size, itemCount: max(items, 1),
                            isPartial: isPartial)
        }
        var sorted = children.sorted { $0.size > $1.size }
        var otherSize = smallFilesSize
        var otherCount = smallFilesCount
        if sorted.count > maxChildren {
            for extra in sorted[maxChildren...] {
                otherSize += extra.size
                otherCount += max(1, extra.itemCount)
            }
            sorted.removeSubrange(maxChildren...)
        }
        if otherSize > 0 {
            sorted.append(DiskNode(id: path + "/\u{0}other", name: "", path: path, kind: .other(count: otherCount),
                                   size: otherSize, itemCount: otherCount))
            sorted.sort { $0.size > $1.size }
        }
        return DiskNode(name: name, path: path, kind: .folder, size: size, itemCount: max(items, 1),
                        children: sorted, isPartial: isPartial)
    }
}
