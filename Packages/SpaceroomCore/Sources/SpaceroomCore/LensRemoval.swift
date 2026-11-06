// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// MARK: - What Space Lens may remove

/// Whether a file or folder on the Space Lens map may be removed.
///
/// Space Lens shows everything, so it's the one module where the user can pick *any* item. The
/// policy is deliberately narrower than "anything Finder would delete":
/// - only items inside the home folder or on a writable external drive (other users,
///   `/Applications` and the system are refused; apps go through Applications so their
///   leftovers go too). On external drives the drive's own system folders, hidden folders at
///   its top level and Time Machine drives are refused;
/// - never the home folder's own top-level folders (Documents, Library, …), never the folders
///   directly inside `~/Library` (Application Support, Caches, Containers, …), never Keychains;
/// - never Spaceroom's own data, including the Restore Center.
public enum LensVerdict: Sendable, Hashable {
    case allowed
    /// Not inside the home folder or on a removable external drive.
    case outsideHome
    /// A folder macOS or apps rely on, or something that contains one.
    case protectedFolder
    /// Spaceroom's own data (the Restore Center lives here).
    case spaceroomData
    /// The "smaller items" summary, which isn't a real file.
    case notAnItem
    /// An app, or a folder with apps in it. Apps are removed in Applications, which also finds
    /// their leftovers and checks they aren't running.
    case application
}

public struct LensRemovalPolicy: Sendable {
    public let home: URL
    /// Spaceroom's data folder (the Restore Center's directory).
    public let ownData: URL

    /// Roots of external drives items may be removed from (see `removableVolumes()`).
    public let volumes: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, ownData: URL, volumes: [URL] = []) {
        self.home = home
        self.ownData = ownData
        self.volumes = volumes
    }

    /// Top-level folders of a drive that belong to an installed macOS or to backups.
    static let volumeSystemFolders: Set<String> = [
        "System", "Library", "Applications", "Users", "private", "usr", "bin", "sbin", "etc", "var", "opt",
        "cores", "Volumes", "Backups.backupdb",
    ]

    /// External drives Space Lens may remove from: local, writable, mounted under `/Volumes`,
    /// and not used for Time Machine.
    public static func removableVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true, values.volumeIsReadOnly != true, values.volumeIsRootFileSystem != true,
                  url.path.hasPrefix("/Volumes/") else { return false }
            let fm = FileManager.default
            return !fm.fileExists(atPath: url.appendingPathComponent("Backups.backupdb").path)
                && !fm.fileExists(atPath: url.appendingPathComponent(".com.apple.timemachine.supported").path)
                && !fm.fileExists(atPath: url.appendingPathComponent(".com.apple.TimeMachine").path)
        }
    }

    /// The external drive `real` is on, if it's one of `volumes`.
    func volume(containing real: String) -> String? {
        volumes.map { SafetyGuard.realPath($0) }.first { real.hasPrefix($0 + "/") }
    }

    /// The folder `url` must stay inside: the home folder, or its external drive.
    public func root(for url: URL) -> URL {
        volume(containing: Self.canonical(url)).map { URL(fileURLWithPath: $0) } ?? home
    }

    /// Folders inside `~/Library` whose *contents* may never be removed from Space Lens.
    static let sealedLibraryFolders: Set<String> = ["Keychains"]

    public func verdict(for node: DiskNode) -> LensVerdict {
        if case .other = node.kind { return .notAnItem }
        let verdict = verdict(for: URL(fileURLWithPath: node.path))
        if verdict == .allowed, Self.containsApplication(node) { return .application }
        return verdict
    }

    /// The node is an app bundle, or one appears in the part of the tree that was measured.
    static func containsApplication(_ node: DiskNode, depth: Int = 0) -> Bool {
        if node.path.lowercased().hasSuffix(".app") { return true }
        guard depth < 6 else { return false }
        return node.children.contains { !$0.isAggregate && containsApplication($0, depth: depth + 1) }
    }

    /// The same check on disk, right before removal (the map may have folded small apps away).
    static func containsApplication(at url: URL) -> Bool {
        if url.pathExtension.lowercased() == "app" { return true }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]) else { return false }
        var checked = 0
        for case let child as URL in enumerator {
            checked += 1
            if child.pathExtension.lowercased() == "app" { return true }
            if checked > 200_000 { break }   // a huge tree (say a project with dependencies): stop looking
        }
        return false
    }

    public func verdict(for url: URL) -> LensVerdict {
        let real = Self.canonical(url)
        let realHome = SafetyGuard.realPath(home)
        if !real.hasPrefix(realHome + "/"), let volume = volume(containing: real) {
            let first = real.dropFirst(volume.count + 1).split(separator: "/").first.map(String.init) ?? ""
            if first.hasPrefix(".") || Self.volumeSystemFolders.contains(first) { return .protectedFolder }
            return .allowed
        }
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

    public init(store: RestoreStore, home: URL = FileManager.default.homeDirectoryForCurrentUser, volumes: [URL] = []) {
        self.store = store
        self.policy = LensRemovalPolicy(home: home, ownData: store.directory, volumes: volumes)
    }

    public func remove(_ nodes: [DiskNode], running: RunningProcesses = .current(), now: Date = .now) async throws -> CleanOutcome {
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        for node in Self.outermost(nodes) {
            let url = URL(fileURLWithPath: LensRemovalPolicy.canonical(URL(fileURLWithPath: node.path)))
            guard let mode = FileStat.lstatInfo(url).map({ $0.st_mode & S_IFMT }) else {
                skipped.append(SkippedItem(path: node.path, size: node.size, reason: .missing))
                continue
            }
            if policy.verdict(for: node) != .allowed || ![S_IFREG, S_IFDIR, S_IFLNK].contains(mode)
                || (mode == S_IFDIR && LensRemovalPolicy.containsApplication(at: url)) {
                skipped.append(SkippedItem(path: node.path, size: node.size, reason: .protectedPath))
            } else if let reason = SafetyGuard(home: policy.home).check(url, root: policy.root(for: url)) {
                skipped.append(SkippedItem(path: node.path, size: node.size, reason: reason))
            } else if let name = running.program(inside: url) {
                skipped.append(SkippedItem(path: node.path, size: node.size, reason: .running(name: name)))
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
