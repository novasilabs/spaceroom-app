// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Device + inode pair. Used to prove an item is still the same object between scan and clean.
public struct FileIdentity: Codable, Sendable, Hashable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// Measured facts about an item (file or folder tree).
public struct FileMeasurement: Sendable, Hashable {
    /// Bytes allocated on disk (what the user actually gets back).
    public var allocatedSize: Int64
    /// Newest modification date anywhere inside the item.
    public var newestModification: Date
    public var fileCount: Int
    public var isDirectory: Bool
    public var identity: FileIdentity
}

/// Thin wrappers over `lstat` and directory enumeration. Never follows symlinks.
enum FileStat {
    static func lstatInfo(_ url: URL) -> stat? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? info : nil
    }

    static func exists(_ url: URL) -> Bool { lstatInfo(url) != nil }

    static func identity(of url: URL) -> FileIdentity? {
        lstatInfo(url).map(identity(from:))
    }

    static func identity(from info: stat) -> FileIdentity {
        FileIdentity(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino))
    }

    static func device(of url: URL) -> UInt64? { identity(of: url)?.device }

    static func modificationDate(from info: stat) -> Date {
        let ts = info.st_mtimespec
        return Date(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000)
    }

    static func isDirectory(_ info: stat) -> Bool { (info.st_mode & S_IFMT) == S_IFDIR }

    /// Measures an item. Folder trees are walked without following symlinks.
    /// Returns `nil` if the item does not exist. Stops early (partial result) when cancelled.
    static func measure(_ url: URL, isCancelled: () -> Bool = { false }) -> FileMeasurement? {
        guard let info = lstatInfo(url) else { return nil }
        let identity = identity(from: info)
        var newest = modificationDate(from: info)
        guard isDirectory(info) else {
            return FileMeasurement(
                allocatedSize: Int64(info.st_blocks) * 512,
                newestModification: newest,
                fileCount: 1,
                isDirectory: false,
                identity: identity
            )
        }

        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentModificationDateKey, .isDirectoryKey]
        var total: Int64 = 0
        var count = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) {
            for case let child as URL in enumerator {
                count += 1
                if count % 2_000 == 0, isCancelled() { break }
                guard let values = try? child.resourceValues(forKeys: Set(keys)) else { continue }
                if let date = values.contentModificationDate, date > newest { newest = date }
                if values.isDirectory != true {
                    total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
            }
        }
        return FileMeasurement(
            allocatedSize: total,
            newestModification: newest,
            fileCount: count,
            isDirectory: true,
            identity: identity
        )
    }
}
