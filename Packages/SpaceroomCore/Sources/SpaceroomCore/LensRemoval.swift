// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// MARK: - What Space Lens may remove

/// Whether a file or folder on the Space Lens map may be removed.
///
/// Space Lens shows everything, so it's the one module where the user can pick *any* item. The
/// policy is deliberately narrower than "anything Finder would delete":
/// - only items inside the home folder (other users, `/Applications` and the system are refused;
///   apps go through Applications so their leftovers go too);
/// - never the home folder's own top-level folders (Documents, Library, …), never the folders
///   directly inside `~/Library` (Application Support, Caches, Containers, …), never Keychains;
/// - never Spaceroom's own data, including the Restore Center.
public enum LensVerdict: Sendable, Hashable {
    case allowed
    /// Not inside the home folder.
    case outsideHome
    /// A folder macOS or apps rely on, or something that contains one.
    case protectedFolder
    /// Spaceroom's own data (the Restore Center lives here).
    case spaceroomData
    /// The "smaller items" summary, which isn't a real file.
    case notAnItem
}

public struct LensRemovalPolicy: Sendable {
    public let home: URL
    /// Spaceroom's data folder (the Restore Center's directory).
    public let ownData: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, ownData: URL) {
        self.home = home
        self.ownData = ownData
    }

    /// Folders inside `~/Library` whose *contents* may never be removed from Space Lens.
    static let sealedLibraryFolders: Set<String> = ["Keychains"]

    public func verdict(for node: DiskNode) -> LensVerdict {
        if case .other = node.kind { return .notAnItem }
        return verdict(for: URL(fileURLWithPath: node.path))
    }

    public func verdict(for url: URL) -> LensVerdict {
        let real = Self.canonical(url)
        let realHome = SafetyGuard.realPath(home)
        guard real.hasPrefix(realHome + "/") else { return .outsideHome }

        let components = real.dropFirst(realHome.count + 1).split(separator: "/").map(String.init)
        // ~/Documents, ~/Library, …: the folders themselves (deeper items are fine).
        if components.count == 1, PathPattern.protectedHomeRoots.contains(components[0]) { return .protectedFolder }
        if components.first == "Library" {
            // ~/Library/Application Support, ~/Library/Caches, … hold every app's data.
            if components.count == 2 { return .protectedFolder }
            if components.count > 2, Self.sealedLibraryFolders.contains(components[1]) { return .protectedFolder }
        }
        let own = SafetyGuard.realPath(ownData)
        if real == own || real.hasPrefix(own + "/") || own.hasPrefix(real + "/") { return .spaceroomData }
        if SafetyGuard(home: home).check(URL(fileURLWithPath: real), root: URL(fileURLWithPath: realHome)) != nil {
            return .protectedFolder
        }
        return .allowed
    }

    /// Resolves symlinks and the APFS firmlink: a scan of the startup disk reports
    /// `/System/Volumes/Data/Users/…`, which is the same file as `/Users/…`.
    public static func canonical(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        let data = "/System/Volumes/Data"
        if path.hasPrefix(data + "/") { path = String(path.dropFirst(data.count)) }
        return SafetyGuard.realPath(URL(fileURLWithPath: path))
    }
}

// MARK: - Removal

/// Moves items picked on the Space Lens map into the Restore Center (module "spaceLens"),
/// re-checking each one against `LensRemovalPolicy` and `SafetyGuard` right before it moves.
public struct LensRemover: Sendable {
    public let store: RestoreStore
    public let policy: LensRemovalPolicy

    public init(store: RestoreStore, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.store = store
        self.policy = LensRemovalPolicy(home: home, ownData: store.directory)
    }

    public func remove(_ nodes: [DiskNode], now: Date = .now) async throws -> CleanOutcome {
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        for node in Self.outermost(nodes) {
            let url = URL(fileURLWithPath: LensRemovalPolicy.canonical(URL(fileURLWithPath: node.path)))
            guard let mode = FileStat.lstatInfo(url).map({ $0.st_mode & S_IFMT }) else {
                skipped.append(SkippedItem(path: node.path, size: node.size, reason: .missing))
                continue
            }
            if policy.verdict(for: node) != .allowed || ![S_IFREG, S_IFDIR, S_IFLNK].contains(mode) {
                skipped.append(SkippedItem(path: node.path, size: node.size, reason: .protectedPath))
            } else if let reason = SafetyGuard(home: policy.home).check(url, root: policy.home) {
                skipped.append(SkippedItem(path: node.path, size: node.size, reason: reason))
            } else {
                moves.append(PlannedMove(url: url, ruleID: "spaceLens", size: node.size, isDirectory: mode == S_IFDIR))
            }
        }
        guard !moves.isEmpty else { return CleanOutcome(operation: nil, skipped: skipped) }
        let (record, failures) = try await store.quarantine(moves, module: "spaceLens", now: now)
        let sizes = Dictionary(moves.map { ($0.url.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        return CleanOutcome(operation: record,
                            skipped: skipped + failures.map { SkippedItem(path: $0.path, size: sizes[$0.path] ?? 0, reason: $0.reason) })
    }

    /// Drops duplicates and items inside another selected folder (moving the folder moves them).
    static func outermost(_ nodes: [DiskNode]) -> [DiskNode] {
        let sorted = nodes.sorted { $0.path.count < $1.path.count }
        var kept: [DiskNode] = []
        for node in sorted where !kept.contains(where: { $0.path == node.path || node.path.hasPrefix($0.path + "/") }) {
            kept.append(node)
        }
        return kept
    }
}

// MARK: - Updating the map

extension DiskNode {
    /// The "smaller items" summary node, which stands for many files rather than one.
    public var isAggregate: Bool {
        if case .other = kind { return true }
        return false
    }

    /// A copy of the tree without the nodes at `paths`, with sizes and counts of every folder
    /// above them reduced to match. Used after a removal so the map updates without a rescan.
    public func removing(paths: Set<String>) -> DiskNode {
        guard !paths.isEmpty, kind == .folder,
              paths.contains(where: { $0.hasPrefix(path.hasSuffix("/") ? path : path + "/") }) else { return self }
        var size = size
        var itemCount = itemCount
        var kept: [DiskNode] = []
        for child in children {
            if paths.contains(child.path), !child.isAggregate {
                size -= child.size
                itemCount -= child.itemCount
                continue
            }
            let updated = child.removing(paths: paths)
            size -= child.size - updated.size
            itemCount -= child.itemCount - updated.itemCount
            kept.append(updated)
        }
        return DiskNode(id: id, name: name, path: path, kind: kind, size: max(0, size), itemCount: max(1, itemCount),
                        children: kept, isPartial: isPartial)
    }
}
