// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3

// MARK: - Browsers

public struct Browser: Sendable, Hashable, Identifiable {
    public enum Layout: Sendable, Hashable { case chromium, safari, firefox }

    public let id: String
    public let name: String
    public let bundleID: String
    /// Data folder relative to ~/Library.
    public let folder: String
    public let layout: Layout

    public static let all: [Browser] = [
        Browser(id: "safari", name: "Safari", bundleID: "com.apple.Safari", folder: "Safari", layout: .safari),
        Browser(id: "chrome", name: "Google Chrome", bundleID: "com.google.Chrome",
                folder: "Application Support/Google/Chrome", layout: .chromium),
        Browser(id: "dia", name: "Dia", bundleID: "company.thebrowser.dia", folder: "Application Support/Dia/User Data", layout: .chromium),
        Browser(id: "arc", name: "Arc", bundleID: "company.thebrowser.Browser", folder: "Application Support/Arc/User Data", layout: .chromium),
        Browser(id: "edge", name: "Microsoft Edge", bundleID: "com.microsoft.edgemac",
                folder: "Application Support/Microsoft Edge", layout: .chromium),
        Browser(id: "brave", name: "Brave", bundleID: "com.brave.Browser",
                folder: "Application Support/BraveSoftware/Brave-Browser", layout: .chromium),
        Browser(id: "vivaldi", name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", folder: "Application Support/Vivaldi", layout: .chromium),
        Browser(id: "firefox", name: "Firefox", bundleID: "org.mozilla.firefox",
                folder: "Application Support/Firefox/Profiles", layout: .firefox),
    ]
}

public enum PrivacyKind: String, Sendable, Hashable, CaseIterable {
    /// Visited pages, typed suggestions and most-visited tiles (and, in Chromium, download history).
    case history
    case cookies
    /// Things you typed into web forms.
    case autofill
    case downloads
    /// The recent documents, apps and servers macOS lists in the Apple menu and in apps.
    case recentItems

    /// Clearing these signs you out of websites.
    public var signsYouOut: Bool { self == .cookies }
}

/// One clearable piece of privacy data: a kind, for one browser profile (or for macOS).
public struct PrivacyItem: Sendable, Hashable, Identifiable {
    public var id: String { "\(owner)/\(profile)/\(kind.rawValue)" }
    /// Browser ID, or "macos" for recent items.
    public let owner: String
    public let ownerName: String
    /// Bundle ID that must be closed before clearing (the browser).
    public let bundleID: String?
    public let profile: String
    public let kind: PrivacyKind
    public let files: [URL]
    public let size: Int64
}

public struct PrivacyScanResult: Sendable {
    public let items: [PrivacyItem]
    /// Owners whose data macOS wouldn't let us read (Full Disk Access is off).
    public let lockedOwners: [String]
}

/// Finds browser history, cookies, autofill and download records, plus macOS recent items.
/// Saved passwords (Chromium "Login Data", Safari Keychain, Firefox logins/key4) are never included.
public enum PrivacyScanner {
    /// Chromium files per kind. Each may be followed by "-journal" / "-wal" / "-shm".
    static let chromium: [PrivacyKind: [String]] = [
        .history: ["History", "Visited Links", "Top Sites", "Shortcuts", "Network Action Predictor"],
        .cookies: ["Cookies", "Network/Cookies"],
        .autofill: ["Web Data"],
    ]
    static let sqliteSidecars = ["-journal", "-wal", "-shm"]
    /// Never touched, whatever a future rule says.
    public static let neverTouch: Set<String> = ["Login Data", "Login Data For Account", "logins.json", "key4.db",
                                                 "key3.db", "Bookmarks", "places.sqlite", "Keychains"]

    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            browsers: [Browser] = Browser.all) -> PrivacyScanResult {
        let library = home.appendingPathComponent("Library")
        var items: [PrivacyItem] = []
        var locked: [String] = []
        for browser in browsers {
            let root = library.appendingPathComponent(browser.folder)
            guard FileStat.exists(root) else { continue }
            guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else {
                locked.append(browser.name)
                continue
            }
            switch browser.layout {
            case .chromium: items += chromiumItems(browser, root: root)
            case .safari: items += safariItems(browser, library: library)
            case .firefox: items += firefoxItems(browser, root: root)
            }
        }
        let recents = library.appendingPathComponent("Application Support/com.apple.sharedfilelist")
        if FileStat.exists(recents) {
            if let item = recentItems(recents) { items.append(item) } else if !readable(recents) { locked.append(String(localized: "Recent items", bundle: .module)) }
        }
        return PrivacyScanResult(items: items, lockedOwners: locked)
    }

    static func readable(_ url: URL) -> Bool { (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil }

    static func chromiumItems(_ browser: Browser, root: URL) -> [PrivacyItem] {
        // Profiles are "Default", "Profile 1", …; Opera-style single-profile folders hold the files directly.
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        var profiles = names.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.map { root.appendingPathComponent($0) }
        if profiles.isEmpty, FileStat.exists(root.appendingPathComponent("History")) { profiles = [root] }
        return profiles.flatMap { profile -> [PrivacyItem] in
            PrivacyKind.allCases.compactMap { kind in
                guard let bases = chromium[kind] else { return nil }
                let files = bases.flatMap { base in
                    ([base] + sqliteSidecars.map { base + $0 }).map { profile.appendingPathComponent($0) }
                }
                return item(browser, profile: profile.lastPathComponent, kind: kind, files: files)
            }
        }
    }

    static func safariItems(_ browser: Browser, library: URL) -> [PrivacyItem] {
        let safari = library.appendingPathComponent("Safari")
        let history = ["History.db", "History.db-wal", "History.db-shm", "History.db-lock"].map { safari.appendingPathComponent($0) }
        let cookies = [library.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")]
        return [item(browser, profile: "Default", kind: .history, files: history),
                item(browser, profile: "Default", kind: .downloads, files: [safari.appendingPathComponent("Downloads.plist")]),
                item(browser, profile: "Default", kind: .cookies, files: cookies)].compactMap { $0 }
    }

    static func firefoxItems(_ browser: Browser, root: URL) -> [PrivacyItem] {
        // Firefox keeps history and bookmarks in one database (places.sqlite), so history is not offered.
        let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
            .map { root.appendingPathComponent($0) }
            .filter { FileStat.lstatInfo($0).map(FileStat.isDirectory) == true }
        return profiles.flatMap { profile -> [PrivacyItem] in
            let files: [PrivacyKind: [String]] = [.cookies: ["cookies.sqlite"], .autofill: ["formhistory.sqlite"]]
            return files.sorted { $0.key.rawValue < $1.key.rawValue }.compactMap { kind, bases in
                let all = bases.flatMap { base in ([base] + sqliteSidecars.map { base + $0 }).map { profile.appendingPathComponent($0) } }
                return item(browser, profile: profile.lastPathComponent, kind: kind, files: all)
            }
        }
    }

    static func recentItems(_ folder: URL) -> PrivacyItem? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        var files = names.filter { $0.hasSuffix(".sfl2") || $0.hasSuffix(".sfl3") }.map { folder.appendingPathComponent($0) }
        let perApp = folder.appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments")
        files += ((try? FileManager.default.contentsOfDirectory(atPath: perApp.path)) ?? [])
            .filter { $0.hasSuffix(".sfl2") || $0.hasSuffix(".sfl3") }.map { perApp.appendingPathComponent($0) }
        // Favorites and sidebar lists live here too; only "Recent…" lists are recents.
        files = files.filter { $0.lastPathComponent.contains("Recent") || $0.deletingLastPathComponent() == perApp }
        guard !files.isEmpty else { return nil }
        return PrivacyItem(owner: "macos", ownerName: "macOS", bundleID: nil, profile: "Default", kind: .recentItems,
                           files: files.sorted { $0.path < $1.path }, size: files.reduce(0) { $0 + DiskUsage.size(of: $1) })
    }

    static func item(_ browser: Browser, profile: String, kind: PrivacyKind, files: [URL]) -> PrivacyItem? {
        let present = files.filter { FileStat.exists($0) && !neverTouch.contains($0.lastPathComponent) }
        guard !present.isEmpty else { return nil }
        return PrivacyItem(owner: browser.id, ownerName: browser.name, bundleID: browser.bundleID, profile: profile,
                           kind: kind, files: present, size: present.reduce(0) { $0 + DiskUsage.size(of: $1) })
    }
}

public enum PrivacyError: Error, Equatable, LocalizedError {
    case browserRunning(String)

    public var errorDescription: String? {
        switch self {
        case .browserRunning(let name): String(localized: "Quit \(name) first: clearing a browser's data while it's open can damage it.", bundle: .module)
        }
    }
}

/// Moves chosen privacy data into the Restore Center (so even cleared history can come back).
public struct PrivacyCleaner: Sendable {
    public let store: RestoreStore
    public let home: URL

    public init(store: RestoreStore, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.store = store
        self.home = home
    }

    public func clear(_ items: [PrivacyItem], runningBundleIDs: Set<String>, now: Date = .now) async throws -> CleanOutcome {
        if let running = items.first(where: { $0.bundleID.map(runningBundleIDs.contains) == true }) {
            throw PrivacyError.browserRunning(running.ownerName)
        }
        let library = SafetyGuard.realPath(home.appendingPathComponent("Library")) + "/"
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        for item in items {
            for file in item.files {
                let real = SafetyGuard.realPath(file)
                let isFile = FileStat.lstatInfo(file).map { ($0.st_mode & S_IFMT) == S_IFREG } ?? false
                if !real.hasPrefix(library) || !isFile || PrivacyScanner.neverTouch.contains(file.lastPathComponent) {
                    skipped.append(SkippedItem(path: file.path, size: 0, reason: .protectedPath))
                } else {
                    moves.append(PlannedMove(url: file, ruleID: "privacy.\(item.owner).\(item.kind.rawValue)",
                                             size: DiskUsage.size(of: file), isDirectory: false))
                }
            }
        }
        guard !moves.isEmpty else { return CleanOutcome(operation: nil, skipped: skipped) }
        let (record, failures) = try await store.quarantine(moves, module: "privacy", now: now)
        return CleanOutcome(operation: record,
                            skipped: skipped + failures.map { SkippedItem(path: $0.path, size: 0, reason: $0.reason) })
    }
}

// MARK: - App permissions (read-only)

public struct PermissionGrant: Sendable, Hashable, Identifiable {
    public var id: String { service + "/" + client }
    public let service: String
    /// Bundle ID or executable path.
    public let client: String
    public let allowed: Bool
}

public enum PermissionService: String, CaseIterable, Sendable {
    case camera = "kTCCServiceCamera"
    case microphone = "kTCCServiceMicrophone"
    case screenRecording = "kTCCServiceScreenCapture"
    case fullDiskAccess = "kTCCServiceSystemPolicyAllFiles"
    case accessibility = "kTCCServiceAccessibility"
    case inputMonitoring = "kTCCServiceListenEvent"
    case contacts = "kTCCServiceAddressBook"
    case calendars = "kTCCServiceCalendar"
    case photos = "kTCCServicePhotos"
}

/// Reads macOS's permission databases. Read-only: changing permissions is only possible in System Settings.
public enum PermissionsReader {
    public static func databases(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
         URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")]
    }

    /// `nil` when the database can't be read (Full Disk Access is off).
    public static func read(_ database: URL) -> [PermissionGrant]? {
        var handle: OpaquePointer?
        let uri = "file:" + database.path + "?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT service, client, auth_value FROM access", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        var grants: [PermissionGrant] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let service = sqlite3_column_text(statement, 0), let client = sqlite3_column_text(statement, 1) else { continue }
            grants.append(PermissionGrant(service: String(cString: service), client: String(cString: client),
                                          allowed: sqlite3_column_int(statement, 2) == 2))
        }
        return grants
    }
}
