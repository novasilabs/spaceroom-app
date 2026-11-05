// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Darwin
import Foundation

// MARK: - Model

public enum ClutterKind: String, Sendable, Hashable, CaseIterable {
    case video, audio, image, archive, diskImage, installer, document, other

    static let extensions: [String: ClutterKind] = {
        var map: [String: ClutterKind] = [:]
        for ext in ["mov", "mp4", "m4v", "mkv", "avi", "webm", "hevc", "mts", "braw"] { map[ext] = .video }
        for ext in ["mp3", "m4a", "wav", "aiff", "aif", "flac", "aac", "ogg"] { map[ext] = .audio }
        for ext in ["jpg", "jpeg", "png", "heic", "tif", "tiff", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd", "gif", "webp"] { map[ext] = .image }
        for ext in ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"] { map[ext] = .archive }
        for ext in ["dmg", "iso", "img", "sparseimage", "sparsebundle"] { map[ext] = .diskImage }
        for ext in ["pkg", "mpkg", "xip"] { map[ext] = .installer }
        for ext in ["pdf", "key", "pages", "numbers", "docx", "doc", "pptx", "xlsx", "sketch", "fig", "blend"] { map[ext] = .document }
        return map
    }()

    public init(fileName: String) {
        self = Self.extensions[(fileName as NSString).pathExtension.lowercased()] ?? .other
    }
}

public struct ClutterFile: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let modified: Date
    public let kind: ClutterKind
    let fileID: UInt64

    public var name: String { url.lastPathComponent }

    /// Installer-type downloads: disk images and installer packages (Mole `installer`).
    public var isInstaller: Bool {
        kind == .installer || ["dmg", "iso"].contains(url.pathExtension.lowercased())
    }

    public init(url: URL, size: Int64, modified: Date, fileID: UInt64 = 0) {
        self.url = url
        self.size = size
        self.modified = modified
        self.kind = ClutterKind(fileName: url.lastPathComponent)
        self.fileID = fileID
    }
}

public struct ClutterReport: Sendable {
    /// Files at or above the large-file threshold, largest first.
    public let largeFiles: [ClutterFile]
    /// Installer downloads of any size, largest first.
    public let installers: [ClutterFile]
    /// Files that share their exact size with another file (input for `DuplicateFinder`).
    public let duplicateCandidates: [ClutterFile]
    /// Photos of at least the duplicate minimum (input for `SimilarPhotoFinder`).
    public let photos: [ClutterFile]
    public let scannedItems: Int

    public init(largeFiles: [ClutterFile], installers: [ClutterFile], duplicateCandidates: [ClutterFile],
                photos: [ClutterFile] = [], scannedItems: Int) {
        self.largeFiles = largeFiles
        self.installers = installers
        self.duplicateCandidates = duplicateCandidates
        self.photos = photos
        self.scannedItems = scannedItems
    }
}

public struct ClutterScanConfig: Sendable {
    public var roots: [URL]
    /// Folders skipped by name anywhere (build output, dependencies, version control).
    public var skippedFolderNames: Set<String>
    /// Folders skipped by exact path (app data, Trash).
    public var skippedPaths: Set<String>
    public var skipsHiddenItems: Bool
    public var largeFileThreshold: Int64
    public var duplicateMinimumSize: Int64
    /// Smallest photo compared for similarity.
    public var photoMinimumSize: Int64 = 200_000

    public static let defaultSkippedFolderNames: Set<String> = [
        "node_modules", ".git", "build", "DerivedData", "Pods", "target", ".build", "dist", ".next",
        "vendor", ".venv", "venv", "__pycache__", ".gradle",
    ]

    /// Bundles are opaque: their insides aren't the user's loose files.
    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "bundle", "framework",
        "xcodeproj", "xcworkspace", "playground", "lproj", "kext", "plugin", "appex", "imovielibrary",
        "fcpbundle", "logicx", "band", "rtfd", "sparsebundle",
    ]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                largeFileThreshold: Int64 = 50_000_000, duplicateMinimumSize: Int64 = 1_000_000) {
        roots = [home]
        skippedFolderNames = Self.defaultSkippedFolderNames
        skippedPaths = [home.appendingPathComponent("Library").path, home.appendingPathComponent(".Trash").path]
        skipsHiddenItems = true
        self.largeFileThreshold = largeFileThreshold
        self.duplicateMinimumSize = duplicateMinimumSize
    }
}

// MARK: - Scanner

/// Walks the user's own files (not app data) and collects large files, installers and
/// same-size files for duplicate checking. Uses `getattrlistbulk` like Space Lens.
public struct ClutterScanner: Sendable {
    public let config: ClutterScanConfig

    public init(config: ClutterScanConfig = ClutterScanConfig()) {
        self.config = config
    }

    public func scan(progress: @escaping @Sendable (Int) -> Void = { _ in }) async -> ClutterReport {
        let config = config
        var all: [ClutterFile] = []
        var items = 0
        for root in config.roots {
            let device = FileStat.lstatInfo(root).map { Int32($0.st_dev) } ?? 0
            // Top-level folders in parallel, everything below sequentially per worker.
            var walker = CatalogWalker(config: config, device: device)
            let top = walker.read(root.standardizedFileURL.path)
            all += walker.files
            items += walker.items
            let results = await withTaskGroup(of: (files: [ClutterFile], items: Int).self) { group in
                for folder in top {
                    group.addTask {
                        var worker = CatalogWalker(config: config, device: device)
                        worker.walk(folder, progress: progress)
                        return (worker.files, worker.items)
                    }
                }
                var collected: [(files: [ClutterFile], items: Int)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for result in results {
                all += result.files
                items += result.items
            }
        }

        let large = all.filter { $0.size >= config.largeFileThreshold }.sorted { $0.size > $1.size }
        let installers = all.filter(\.isInstaller).sorted { $0.size > $1.size }
        var bySize: [Int64: [ClutterFile]] = [:]
        for file in all where file.size >= config.duplicateMinimumSize { bySize[file.size, default: []].append(file) }
        let candidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        return ClutterReport(largeFiles: large, installers: installers, duplicateCandidates: candidates,
                             photos: all.filter(SimilarPhotoFinder.isPhoto), scannedItems: items)
    }
}

/// One worker's walk. Keeps only files worth reporting (≥ the duplicate minimum, or installers).
struct CatalogWalker {
    let config: ClutterScanConfig
    let device: Int32
    private(set) var files: [ClutterFile] = []
    private(set) var items = 0
    private var pending = 0
    private var seenInodes: Set<UInt64> = []
    private let storage = ScanBuffer()
    private var buffer: UnsafeMutableRawPointer { storage.pointer }
    private static var bufferSize: Int { ScanBuffer.size }

    init(config: ClutterScanConfig, device: Int32) {
        self.config = config
        self.device = device
    }

    // Layout with FSOPT_PACK_INVAL_ATTRS: length, returned set, error, name ref, devid, objtype,
    // modtime (timespec), fileid, linkcount, allocsize. ATTR_CMN_ERROR follows the returned set.
    private static var attributes: attrlist {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_FILEID)
        list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
        return list
    }

    mutating func walk(_ path: String, progress: @Sendable (Int) -> Void) {
        var stack = [path]
        while let folder = stack.popLast() {
            if Task.isCancelled { break }
            stack += read(folder)
            if pending >= 5_000 {
                progress(pending)
                pending = 0
            }
        }
        progress(pending)
        pending = 0
    }

    /// Reads one folder: records interesting files, returns subfolders to visit.
    mutating func read(_ path: String) -> [String] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var list = Self.attributes
        var subfolders: [String] = []
        let base = path == "/" ? "" : path
        while true {
            let count = getattrlistbulk(fd, &list, buffer, Self.bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if count <= 0 { break }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                var cursor = entry + 4 + MemoryLayout<attribute_set_t>.size
                let error = cursor.loadUnaligned(as: UInt32.self); cursor += 4
                let nameRef = cursor.loadUnaligned(as: attrreference_t.self)
                let namePointer = (cursor + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                cursor += MemoryLayout<attrreference_t>.size
                let entryDevice = cursor.loadUnaligned(as: Int32.self); cursor += 4
                let objectType = cursor.loadUnaligned(as: UInt32.self); cursor += 4
                let seconds = cursor.loadUnaligned(as: Int.self)
                let nanoseconds = (cursor + MemoryLayout<Int>.size).loadUnaligned(as: Int.self)
                cursor += MemoryLayout<timespec>.size
                let fileID = cursor.loadUnaligned(as: UInt64.self); cursor += 8
                let linkCount = cursor.loadUnaligned(as: UInt32.self); cursor += 4
                let allocated = cursor.loadUnaligned(as: Int64.self)
                entry += length
                if error != 0 { continue }

                let name = String(cString: namePointer)
                if config.skipsHiddenItems, name.hasPrefix(".") { continue }
                items += 1
                pending += 1
                switch objectType {
                case 2: // VDIR
                    guard entryDevice == device else { continue }
                    let child = base + "/" + name
                    let ext = (name as NSString).pathExtension.lowercased()
                    if config.skippedFolderNames.contains(name) || config.skippedPaths.contains(child)
                        || ClutterScanConfig.packageExtensions.contains(ext) { continue }
                    subfolders.append(child)
                case 1: // VREG (symlinks are skipped: they aren't the user's data)
                    if linkCount > 1, !seenInodes.insert(fileID).inserted { continue }
                    let url = URL(fileURLWithPath: base + "/" + name)
                    let ext = (name as NSString).pathExtension.lowercased()
                    let isInstaller = ["dmg", "pkg", "mpkg", "iso", "xip"].contains(ext)
                    // Photos are kept from 200 KB, for the similar-photo check.
                    let isPhoto = SimilarPhotoFinder.extensions.contains(ext) && allocated >= config.photoMinimumSize
                    guard allocated >= config.duplicateMinimumSize || isInstaller || isPhoto else { continue }
                    let modified = Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1e9)
                    files.append(ClutterFile(url: url, size: allocated, modified: modified, fileID: fileID))
                default:
                    continue
                }
            }
        }
        return subfolders
    }
}

// MARK: - Duplicates

public struct DuplicateGroup: Sendable, Identifiable, Hashable {
    public let id: String
    public let files: [ClutterFile]
    /// The copy to keep: outside Downloads, then the original name over "name (1)", then the oldest.
    public let keeper: ClutterFile
    public var size: Int64 { files.first?.size ?? 0 }
    /// Space the extra copies take.
    public var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
    public var extras: [ClutterFile] { files.filter { $0.id != keeper.id } }
}

/// Confirms duplicates by content: same size → same first/last 64 KB → same SHA-256.
public enum DuplicateFinder {
    public static func groups(from candidates: [ClutterFile], isCancelled: @Sendable () -> Bool = { false }) -> [DuplicateGroup] {
        var bySize: [Int64: [ClutterFile]] = [:]
        for file in candidates { bySize[file.size, default: []].append(file) }
        var groups: [DuplicateGroup] = []
        for (_, sameSize) in bySize where sameSize.count > 1 {
            if isCancelled() { break }
            // Different inodes only: hard links are one file, not duplicates.
            var seen = Set<UInt64>()
            let distinct = sameSize.filter { $0.fileID == 0 || seen.insert($0.fileID).inserted }
            guard distinct.count > 1 else { continue }
            let byQuick = Dictionary(grouping: distinct) { quickHash($0.url) ?? UUID().uuidString }
            for (_, quickMatch) in byQuick where quickMatch.count > 1 {
                let byFull = Dictionary(grouping: quickMatch) { fullHash($0.url) ?? UUID().uuidString }
                for (hash, files) in byFull where files.count > 1 {
                    groups.append(DuplicateGroup(id: hash, files: files.sorted { $0.url.path < $1.url.path },
                                                 keeper: keeper(of: files)))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    static func keeper(of files: [ClutterFile]) -> ClutterFile {
        files.min { a, b in
            let aDownload = a.url.path.contains("/Downloads/"), bDownload = b.url.path.contains("/Downloads/")
            if aDownload != bDownload { return !aDownload }
            let aCopy = looksLikeCopy(a.name), bCopy = looksLikeCopy(b.name)
            if aCopy != bCopy { return !aCopy }
            if a.modified != b.modified { return a.modified < b.modified }
            return a.url.path.count < b.url.path.count
        }!
    }

    /// "report (1).pdf", "report copy.pdf", "report copy 2.pdf" — names browsers and Finder give copies.
    static func looksLikeCopy(_ name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension
        return stem.range(of: #" \(\d+\)$"#, options: .regularExpression) != nil
            || stem.range(of: #" copy( \d+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func quickHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        if let head = try? handle.read(upToCount: 64 * 1024) { hasher.update(data: head) }
        if let end = try? handle.seekToEnd(), end > 128 * 1024 {
            try? handle.seek(toOffset: end - 64 * 1024)
            if let tail = try? handle.read(upToCount: 64 * 1024) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Removal

/// Moves the user's chosen files into the Restore Center. Only loose files inside the home
/// folder qualify — never app data in ~/Library, never folders, never protected locations.
public struct ClutterRemover: Sendable {
    public let store: RestoreStore
    public let home: URL

    public init(store: RestoreStore, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.store = store
        self.home = home
    }

    public func remove(_ files: [ClutterFile], now: Date = .now) async throws -> CleanOutcome {
        let guardrail = SafetyGuard(home: home)
        let realHome = SafetyGuard.realPath(home)
        let library = realHome + "/Library/"
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        for file in files {
            let real = SafetyGuard.realPath(file.url)
            let isRegularFile = FileStat.lstatInfo(file.url).map { ($0.st_mode & S_IFMT) == S_IFREG } ?? false
            if !FileStat.exists(file.url) {
                skipped.append(SkippedItem(path: file.url.path, size: file.size, reason: .missing))
            } else if !real.hasPrefix(realHome + "/") || real.hasPrefix(library) || !isRegularFile {
                skipped.append(SkippedItem(path: file.url.path, size: file.size, reason: .protectedPath))
            } else if let reason = guardrail.check(file.url, root: file.url.deletingLastPathComponent()) {
                skipped.append(SkippedItem(path: file.url.path, size: file.size, reason: reason))
            } else {
                moves.append(PlannedMove(url: file.url, ruleID: "clutter." + file.kind.rawValue, size: file.size, isDirectory: false))
            }
        }
        guard !moves.isEmpty else { return CleanOutcome(operation: nil, skipped: skipped) }
        let (record, failures) = try await store.quarantine(moves, module: "clutter", now: now)
        let sizes = Dictionary(moves.map { ($0.url.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        return CleanOutcome(operation: record,
                            skipped: skipped + failures.map { SkippedItem(path: $0.path, size: sizes[$0.path] ?? 0, reason: $0.reason) })
    }
}
