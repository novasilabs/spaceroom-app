// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Folder sizes from one finished Space Lens scan, so the next scan can show what grew.
/// Only sizes are kept (no file names below the recorded depth), and it never leaves the Mac.
public struct LensSnapshot: Codable, Sendable, Equatable {
    public let date: Date
    public let total: Int64
    /// Folder sizes up to a few levels below the scanned folder, keyed by path relative to it
    /// ("" is the scanned folder itself).
    public let sizes: [String: Int64]
    /// How many levels below the scanned folder were recorded.
    public let depth: Int

    public init(date: Date, total: Int64, sizes: [String: Int64], depth: Int) {
        self.date = date
        self.total = total
        self.sizes = sizes
        self.depth = depth
    }

    /// Records folders and files of at least `minimumSize` down to `depth` levels.
    public static func make(from root: DiskNode, depth: Int = 3, minimumSize: Int64 = 10_000_000,
                            date: Date = .now) -> LensSnapshot {
        var sizes: [String: Int64] = ["": root.size]
        func walk(_ node: DiskNode, level: Int) {
            guard level < depth else { return }
            for child in node.children where !child.isAggregate && child.size >= minimumSize {
                if let key = relativePath(of: child.path, root: root.path) { sizes[key] = child.size }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 0)
        return LensSnapshot(date: date, total: root.size, sizes: sizes, depth: depth)
    }

    static func relativePath(of path: String, root: String) -> String? {
        if path == root { return "" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    /// How much `node` changed since this snapshot. `nil` when it wasn't recorded (too small
    /// then, too deep, or not inside `root`).
    public func change(of node: DiskNode, root: String) -> Int64? {
        guard !node.isAggregate, let key = Self.relativePath(of: node.path, root: root),
              let before = sizes[key] else { return nil }
        return node.size - before
    }

    /// True when `node` appeared since this snapshot: its parent was recorded and deep enough
    /// that `node` would have been too, had it existed at its current size.
    public func isNew(_ node: DiskNode, root: String, minimumSize: Int64 = 10_000_000) -> Bool {
        guard !node.isAggregate, node.size >= minimumSize, let key = Self.relativePath(of: node.path, root: root),
              !key.isEmpty, sizes[key] == nil else { return false }
        let parts = key.split(separator: "/")
        guard parts.count <= depth else { return false }
        let parent = parts.dropLast().joined(separator: "/")
        return sizes[parent] != nil
    }
}

/// The last snapshots of each scanned folder, in `<directory>/<hash of the folder path>.json`.
public struct LensHistory: Sendable {
    public let directory: URL
    public static let kept = 30

    public init(directory: URL) {
        self.directory = directory
    }

    struct File: Codable {
        var root: String
        var snapshots: [LensSnapshot]
    }

    static func fileName(for root: String) -> String {
        SHA256.hash(data: Data(root.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    private func url(for root: String) -> URL { directory.appendingPathComponent(Self.fileName(for: root)) }

    /// Oldest first. Empty when there's no history or the file can't be read.
    public func load(root: String) -> [LensSnapshot] {
        guard let data = try? Data(contentsOf: url(for: root)),
              let file = try? JSONDecoder().decode(File.self, from: data), file.root == root else { return [] }
        return file.snapshots.sorted { $0.date < $1.date }
    }

    /// Adds a snapshot, keeping the newest `kept`. A second scan within an hour replaces the
    /// first, so "since last scan" means since a different moment, not a minute ago.
    public func record(_ snapshot: LensSnapshot, root: String) throws {
        var snapshots = load(root: root)
        if let last = snapshots.last, snapshot.date.timeIntervalSince(last.date) < 3600 { snapshots.removeLast() }
        snapshots.append(snapshot)
        snapshots = Array(snapshots.suffix(Self.kept))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(File(root: root, snapshots: snapshots))
        try data.write(to: url(for: root), options: .atomic)
    }

    /// The snapshot to compare a new scan with: the newest one at least an hour older.
    public func baseline(root: String, before date: Date = .now) -> LensSnapshot? {
        load(root: root).last { date.timeIntervalSince($0.date) >= 3600 }
    }
}
