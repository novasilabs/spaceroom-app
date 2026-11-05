// SPDX-License-Identifier: GPL-3.0-or-later

import CoreServices
import Foundation

// MARK: - Installed apps

public struct InstalledApp: Sendable, Identifiable, Hashable {
    public enum Source: String, Sendable, Hashable {
        case appStore, apple, developer
    }

    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String?
    public let source: Source
    public let lastUsed: Date?

    public var isProtected: Bool { source == .apple || bundleID.hasPrefix("com.apple.") }

    public init(url: URL, name: String, bundleID: String, version: String?, source: Source, lastUsed: Date?) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.source = source
        self.lastUsed = lastUsed
    }
}

public enum AppInventory {
    /// Where users install apps. System apps live in /System/Applications and are never listed.
    public static func appFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    /// App bundles in the folders and one level of plain subfolders (e.g. "/Applications/Adobe X/").
    public static func discover(in folders: [URL]) -> [URL] {
        var found: [URL] = []
        for folder in folders {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in entries.sorted() where !name.hasPrefix(".") {
                let url = folder.appendingPathComponent(name)
                if name.hasSuffix(".app") {
                    found.append(url)
                } else if FileStat.lstatInfo(url).map(FileStat.isDirectory) == true,
                          let nested = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                    found += nested.filter { $0.hasSuffix(".app") }.sorted().map { url.appendingPathComponent($0) }
                }
            }
        }
        return found
    }

    /// Reads an app's identity from its Info.plist. Returns `nil` for bundles without a bundle ID.
    public static func info(for url: URL) -> InstalledApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String, !bundleID.isEmpty
        else { return nil }
        let name = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let source: InstalledApp.Source
        if bundleID.hasPrefix("com.apple.") {
            source = .apple
        } else if FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path) {
            source = .appStore
        } else {
            source = .developer
        }
        return InstalledApp(url: url, name: name, bundleID: bundleID,
                            version: dict["CFBundleShortVersionString"] as? String,
                            source: source, lastUsed: lastUsedDate(of: url))
    }

    /// Spotlight's "last opened" date, when Spotlight has one.
    static func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

// MARK: - Leftovers

public enum LeftoverCategory: String, Sendable, Hashable, CaseIterable {
    case caches, logs, savedState, webData, launchAgents, preferences, cookies, applicationSupport, containers, groupContainers

    /// Personal data (settings, documents an app keeps, logins) stays unless the user ticks it.
    public var isPersonal: Bool {
        switch self {
        case .preferences, .cookies, .applicationSupport, .containers, .groupContainers: true
        case .caches, .logs, .savedState, .webData, .launchAgents: false
        }
    }
}

public struct Leftover: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let category: LeftoverCategory
    public let size: Int64
    public let lastModified: Date
    public var isPersonal: Bool { category.isPersonal }
}

/// Finds the files an app leaves in ~/Library, by bundle ID (and, where apps use it, by name).
public struct LeftoverFinder: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var library: URL { home.appendingPathComponent("Library") }

    /// Folder-name matches only for distinctive names; generic or vendor names are shared.
    static let ambiguousNames: Set<String> = ["google", "microsoft", "adobe", "apple", "mozilla", "jetbrains",
                                              "library", "data", "app", "helper", "support", "cache", "caches"]

    public func leftovers(bundleID: String, appName: String) -> [Leftover] {
        guard Self.isValidBundleID(bundleID), !bundleID.hasPrefix("com.apple.") else { return [] }
        let name = appName.hasSuffix(".app") ? String(appName.dropLast(4)) : appName
        let nameUsable = name.count >= 3 && !Self.ambiguousNames.contains(name.lowercased())

        var matches: [(URL, LeftoverCategory)] = []
        func add(_ folder: String, _ category: LeftoverCategory, where predicate: (String) -> Bool) {
            let dir = library.appendingPathComponent(folder)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
            for entry in entries where predicate(entry) {
                matches.append((dir.appendingPathComponent(entry), category))
            }
        }
        func idOrHelper(_ entry: String, suffix: String = "") -> Bool {
            entry == bundleID + suffix || (entry.hasPrefix(bundleID + ".") && entry.hasSuffix(suffix))
        }

        add("Caches", .caches) { idOrHelper($0) || (nameUsable && $0 == name) }
        add("Logs", .logs) { idOrHelper($0) || (nameUsable && $0 == name) }
        add("Saved Application State", .savedState) { $0 == bundleID + ".savedState" }
        add("HTTPStorages", .webData) { $0 == bundleID || $0 == bundleID + ".binarycookies" }
        add("WebKit", .webData) { $0 == bundleID }
        add("LaunchAgents", .launchAgents) { $0.hasPrefix(bundleID) && $0.hasSuffix(".plist") }
        add("Preferences", .preferences) { idOrHelper($0, suffix: ".plist") }
        add("Preferences/ByHost", .preferences) { $0.hasPrefix(bundleID + ".") && $0.hasSuffix(".plist") }
        add("Cookies", .cookies) { $0 == bundleID + ".binarycookies" }
        add("Application Support", .applicationSupport) { $0 == bundleID || (nameUsable && $0 == name) }
        add("Containers", .containers) { idOrHelper($0) }
        add("Group Containers", .groupContainers) { $0 == "group." + bundleID || $0.hasSuffix("." + bundleID) }

        return matches.compactMap { url, category in
            guard let m = FileStat.measure(url) else { return nil }
            return Leftover(url: url, category: category, size: m.allocatedSize, lastModified: m.newestModification)
        }
        .sorted { $0.size > $1.size }
    }

    /// Reverse-DNS with at least three parts, e.g. `com.example.app`.
    static func isValidBundleID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}

// MARK: - Leftovers of apps that are gone

public struct OrphanGroup: Sendable, Identifiable, Hashable {
    public var id: String { bundleID }
    public let bundleID: String
    public let items: [Leftover]
    public var size: Int64 { items.reduce(0) { $0 + $1.size } }
    public var lastModified: Date { items.map(\.lastModified).max() ?? .distantPast }
}

/// Finds bundle-ID-named data in ~/Library whose app is no longer installed (Mole `clean` leftovers).
public struct OrphanFinder: Sendable {
    public let home: URL
    /// Anything touched more recently is assumed to still be in use by something.
    public let minAgeDays: Int

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, minAgeDays: Int = 30) {
        self.home = home
        self.minAgeDays = minAgeDays
    }

    static let folders: [(String, LeftoverCategory, String)] = [
        ("Caches", .caches, ""),
        ("Saved Application State", .savedState, ".savedState"),
        ("HTTPStorages", .webData, ""),
        ("WebKit", .webData, ""),
        ("Preferences", .preferences, ".plist"),
        ("Application Support", .applicationSupport, ""),
        ("Containers", .containers, ""),
    ]

    /// Our own data and identifiers that look like apps but aren't.
    static let ignoredPrefixes = ["com.apple.", "group.", "io.github.spaceroom-app", "com.spaceroom"]

    /// - Parameter isInstalled: asks LaunchServices whether *any* copy of an app exists.
    public func find(installedBundleIDs: Set<String>, now: Date = .now,
                     isInstalled: (String) -> Bool = { _ in false }) -> [OrphanGroup] {
        let library = home.appendingPathComponent("Library")
        var groups: [String: [Leftover]] = [:]
        for (folder, category, suffix) in Self.folders {
            let dir = library.appendingPathComponent(folder)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for entry in entries {
                guard suffix.isEmpty || entry.hasSuffix(suffix) else { continue }
                let id = suffix.isEmpty ? entry : String(entry.dropLast(suffix.count))
                guard LeftoverFinder.isValidBundleID(id),
                      !Self.ignoredPrefixes.contains(where: { id.hasPrefix($0) }) else { continue }
                // Installed exactly, or a helper of an installed app (com.foo.app.helper).
                if installedBundleIDs.contains(id) || installedBundleIDs.contains(where: { id.hasPrefix($0 + ".") }) {
                    continue
                }
                if isInstalled(id) { continue }
                let url = dir.appendingPathComponent(entry)
                guard let m = FileStat.measure(url),
                      now.timeIntervalSince(m.newestModification) >= TimeInterval(minAgeDays) * 86_400 else { continue }
                groups[id, default: []].append(
                    Leftover(url: url, category: category, size: m.allocatedSize, lastModified: m.newestModification))
            }
        }
        return groups.map { OrphanGroup(bundleID: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.size > $1.size }
    }
}

// MARK: - Uninstall

public enum UninstallError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case protectedApp(String)
    case appIsRunning(String)

    public var description: String {
        switch self {
        case .protectedApp(let name): String(localized: "\(name) is part of macOS and can't be removed.", bundle: .module)
        case .appIsRunning(let name): String(localized: "Quit \(name) before uninstalling it.", bundle: .module)
        }
    }

    public var errorDescription: String? { description }
}

/// Moves an app and the leftovers the user chose into the Restore Center, so uninstalling is undoable.
public struct Uninstaller: Sendable {
    public let store: RestoreStore
    public let home: URL
    public let appFolders: [URL]

    public init(store: RestoreStore, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                appFolders: [URL]? = nil) {
        self.store = store
        self.home = home
        self.appFolders = appFolders ?? AppInventory.appFolders(home: home)
    }

    /// - Parameter app: `nil` removes only leftovers (apps that are already gone).
    public func remove(app: InstalledApp?, leftovers: [Leftover], runningBundleIDs: Set<String>,
                       now: Date = .now) async throws -> CleanOutcome {
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        let guardrail = SafetyGuard(home: home)

        if let app {
            if app.isProtected { throw UninstallError.protectedApp(app.name) }
            if runningBundleIDs.contains(app.bundleID) { throw UninstallError.appIsRunning(app.name) }
            let parent = SafetyGuard.realPath(app.url.deletingLastPathComponent())
            let allowed = appFolders.map(SafetyGuard.realPath)
            // The bundle must sit in an app folder or one plain subfolder of it.
            let inAppFolder = allowed.contains(parent)
                || allowed.contains(SafetyGuard.realPath(app.url.deletingLastPathComponent().deletingLastPathComponent()))
            if inAppFolder, app.url.pathExtension == "app" {
                moves.append(PlannedMove(url: app.url, ruleID: "app." + app.bundleID,
                                         size: FileStat.measure(app.url)?.allocatedSize ?? 0, isDirectory: true))
            } else {
                skipped.append(SkippedItem(path: app.url.path, size: 0, reason: .outsideRoot))
            }
        }

        let library = home.appendingPathComponent("Library")
        for item in leftovers {
            // Leftovers live directly in a ~/Library subfolder (one deeper for Preferences/ByHost).
            let parent = item.url.deletingLastPathComponent()
            let insideLibrary = SafetyGuard.realPath(parent).hasPrefix(SafetyGuard.realPath(library) + "/")
            if !insideLibrary {
                skipped.append(SkippedItem(path: item.url.path, size: item.size, reason: .outsideRoot))
            } else if let reason = guardrail.check(item.url, root: parent) {
                skipped.append(SkippedItem(path: item.url.path, size: item.size, reason: reason))
            } else {
                moves.append(PlannedMove(url: item.url, ruleID: "leftover." + item.category.rawValue,
                                         size: item.size, isDirectory: FileStat.measure(item.url)?.isDirectory ?? false))
            }
        }

        guard !moves.isEmpty else { return CleanOutcome(operation: nil, skipped: skipped) }
        let (record, failures) = try await store.quarantine(moves, module: "applications", now: now)
        let sizes = Dictionary(moves.map { ($0.url.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        return CleanOutcome(operation: record,
                            skipped: skipped + failures.map { SkippedItem(path: $0.path, size: sizes[$0.path] ?? 0, reason: $0.reason) })
    }
}

// MARK: - Sizes

public enum DiskUsage {
    /// Bytes allocated by a file or folder tree (never follows symlinks).
    public static func size(of url: URL) -> Int64 {
        FileStat.measure(url)?.allocatedSize ?? 0
    }
}
