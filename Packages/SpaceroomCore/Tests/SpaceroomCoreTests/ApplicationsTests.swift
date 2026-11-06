// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

extension Sandbox {
    /// A minimal app bundle with an Info.plist (and optionally an App Store receipt).
    @discardableResult
    func app(_ relative: String, bundleID: String, name: String? = nil, appStore: Bool = false) throws -> URL {
        let url = home.appendingPathComponent(relative)
        var plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": "1.2.3"]
        if let name { plist["CFBundleName"] = name }
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data(repeating: 0x41, count: 50_000).write(to: url.appendingPathComponent("Contents/MacOS/binary"))
        if appStore {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/_MASReceipt"), withIntermediateDirectories: true)
            try Data("receipt".utf8).write(to: url.appendingPathComponent("Contents/_MASReceipt/receipt"))
        }
        return url
    }
}

@Suite("Applications: inventory")
struct AppInventoryTests {
    @Test func discoversAppsIncludingOneNestedLevel() throws {
        let box = try Sandbox()
        try box.app("Applications/Alpha.app", bundleID: "com.example.alpha")
        try box.app("Applications/Vendor Suite/Beta.app", bundleID: "com.example.beta")
        try box.file("Applications/readme.txt")
        let found = AppInventory.discover(in: [box.home.appendingPathComponent("Applications")]).map(\.lastPathComponent)
        #expect(found == ["Alpha.app", "Beta.app"])
    }

    @Test func readsIdentityAndSource() throws {
        let box = try Sandbox()
        let mas = try box.app("Applications/Store.app", bundleID: "com.example.store", name: "Store", appStore: true)
        let apple = try box.app("Applications/Notes.app", bundleID: "com.apple.Notes")
        let dev = try box.app("Applications/Dev.app", bundleID: "com.example.dev")

        let store = try #require(AppInventory.info(for: mas))
        #expect(store.bundleID == "com.example.store")
        #expect(store.version == "1.2.3")
        #expect(store.source == .appStore)
        #expect(AppInventory.info(for: apple)?.isProtected == true)
        #expect(AppInventory.info(for: dev)?.source == .developer)
        #expect(AppInventory.info(for: dev)?.name == "Dev")
    }
}

@Suite("Applications: leftovers")
struct LeftoverFinderTests {
    @Test func findsAppDataByBundleIDAndName() throws {
        let box = try Sandbox()
        let id = "com.example.paint"
        try box.file("Library/Caches/\(id)/cache.db")
        try box.file("Library/Caches/\(id).ShipIt/update")
        try box.file("Library/Logs/Paint/log.txt")
        try box.file("Library/Saved Application State/\(id).savedState/window")
        try box.file("Library/Preferences/\(id).plist")
        try box.file("Library/Application Support/Paint/doc")
        try box.file("Library/Containers/\(id)/Data/x")
        try box.file("Library/Group Containers/ABCDE12345.\(id)/shared")
        try box.file("Library/LaunchAgents/\(id).updater.plist")
        // Not ours:
        try box.file("Library/Caches/com.example.paintbrush/cache")
        try box.file("Library/Application Support/Paintings/doc")
        try box.file("Library/Preferences/com.example.other.plist")

        let found = LeftoverFinder(home: box.home).leftovers(bundleID: id, appName: "Paint")
        let names = Set(found.map(\.url.lastPathComponent))
        #expect(names == [id, "\(id).ShipIt", "Paint", "\(id).savedState", "\(id).plist",
                          "ABCDE12345.\(id)", "\(id).updater.plist"])
        // Personal data is flagged so the UI leaves it unticked.
        #expect(found.filter(\.isPersonal).map(\.category).allSatisfy {
            [.preferences, .applicationSupport, .containers, .groupContainers].contains($0) })
        #expect(found.contains { $0.category == .caches && !$0.isPersonal })
    }

    @Test func ignoresAppleAndAmbiguousNames() throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.apple.Safari/x")
        try box.file("Library/Application Support/Google/x")
        #expect(LeftoverFinder(home: box.home).leftovers(bundleID: "com.apple.Safari", appName: "Safari").isEmpty)
        #expect(LeftoverFinder(home: box.home).leftovers(bundleID: "com.google.Chrome", appName: "Google").isEmpty)
    }

    @Test("Bundle ID shape", arguments: [
        ("com.example.app", true), ("com.example.app-2", true), ("com.example", false),
        ("com..app", false), ("../etc/passwd", false), ("com.ex ample.app", false),
    ])
    func bundleIDValidation(id: String, valid: Bool) {
        #expect(LeftoverFinder.isValidBundleID(id) == valid)
    }
}

@Suite("Applications: orphaned leftovers")
struct OrphanFinderTests {
    @Test func findsOldDataOfAppsThatAreGone() throws {
        let box = try Sandbox()
        let old = Date.now.addingTimeInterval(-60 * 86_400)
        try box.file("Library/Caches/com.gone.app/cache", modified: old)
        try box.backdate(box.home.appendingPathComponent("Library/Caches/com.gone.app"), to: old)
        try box.file("Library/Preferences/com.gone.app.plist", modified: old)
        try box.file("Library/Caches/com.installed.app/cache", modified: old)          // installed
        try box.file("Library/Caches/com.installed.app.helper/cache", modified: old)   // helper of installed
        try box.file("Library/Caches/com.apple.something/cache", modified: old)        // Apple
        try box.file("Library/Caches/com.recent.app/cache")                            // touched recently
        try box.file("Library/Caches/com.lsknown.app/cache", modified: old)            // LaunchServices knows it

        let groups = OrphanFinder(home: box.home).find(installedBundleIDs: ["com.installed.app"]) { $0 == "com.lsknown.app" }
        #expect(groups.map(\.bundleID) == ["com.gone.app"])
        #expect(Set(groups[0].items.map(\.category)) == [.caches, .preferences])
    }
}

@Suite("Applications: uninstall")
struct UninstallerTests {
    func setup(_ box: Sandbox) throws -> (InstalledApp, [Leftover], Uninstaller) {
        let url = try box.app("Applications/Paint.app", bundleID: "com.example.paint", name: "Paint")
        try box.file("Library/Caches/com.example.paint/cache.db")
        try box.file("Library/Preferences/com.example.paint.plist")
        let app = try #require(AppInventory.info(for: url))
        let leftovers = LeftoverFinder(home: box.home).leftovers(bundleID: app.bundleID, appName: app.name)
        let uninstaller = Uninstaller(store: try box.store(), home: box.home,
                                      appFolders: [box.home.appendingPathComponent("Applications")])
        return (app, leftovers, uninstaller)
    }

    @Test func movesAppAndChosenLeftoversThenRestores() async throws {
        let box = try Sandbox()
        let (app, leftovers, uninstaller) = try setup(box)
        let chosen = leftovers.filter { !$0.isPersonal } // the default selection

        let outcome = try await uninstaller.remove(app: app, leftovers: chosen, runningBundleIDs: [])
        let op = try #require(outcome.operation)
        #expect(op.module == "applications")
        #expect(!box.exists("Applications/Paint.app"))
        #expect(!box.exists("Library/Caches/com.example.paint"))
        #expect(box.exists("Library/Preferences/com.example.paint.plist")) // personal data kept

        _ = try await uninstaller.store.restoreAll(in: op.id)
        #expect(box.exists("Applications/Paint.app/Contents/Info.plist"))
        #expect(box.exists("Library/Caches/com.example.paint/cache.db"))
    }

    @Test func refusesRunningApps() async throws {
        let box = try Sandbox()
        let (app, leftovers, uninstaller) = try setup(box)
        await #expect(throws: UninstallError.appIsRunning("Paint")) {
            try await uninstaller.remove(app: app, leftovers: leftovers, runningBundleIDs: ["com.example.paint"])
        }
        #expect(box.exists("Applications/Paint.app"))
    }

    @Test func refusesAppleApps() async throws {
        let box = try Sandbox()
        let url = try box.app("Applications/Notes.app", bundleID: "com.apple.Notes")
        let app = try #require(AppInventory.info(for: url))
        let uninstaller = Uninstaller(store: try box.store(), home: box.home,
                                      appFolders: [box.home.appendingPathComponent("Applications")])
        await #expect(throws: UninstallError.self) {
            try await uninstaller.remove(app: app, leftovers: [], runningBundleIDs: [])
        }
        #expect(box.exists("Applications/Notes.app"))
    }

    @Test func refusesAppsOutsideAppFoldersAndItemsOutsideLibrary() async throws {
        let box = try Sandbox()
        let stray = try box.app("Documents/Stray.app", bundleID: "com.example.stray")
        let app = try #require(AppInventory.info(for: stray))
        let document = try box.file("Documents/important.txt")
        let fake = Leftover(url: document, category: .caches, size: 10, lastModified: .now)
        let uninstaller = Uninstaller(store: try box.store(), home: box.home,
                                      appFolders: [box.home.appendingPathComponent("Applications")])

        let outcome = try await uninstaller.remove(app: app, leftovers: [fake], runningBundleIDs: [])
        #expect(outcome.operation == nil)
        #expect(outcome.skipped.count == 2)
        #expect(box.exists("Documents/Stray.app"))
        #expect(box.exists("Documents/important.txt"))
    }
}

@Suite("Leftovers in vendor folders")
struct VendorLeftoverTests {
    @Test("Versioned folders inside Google/JetBrains are found; similar names aren't")
    func vendor() throws {
        let box = try Sandbox()
        for path in ["Application Support/Google/AndroidStudio2025.2.3/options.xml", "Caches/Google/AndroidStudio2025.2.3/x",
                     "Application Support/Google/Chrome/Default/History", "Application Support/Google/Chrome for Testing/x",
                     "Application Support/Google/ChromeForTesting/x", "Logs/JetBrains/IntelliJIdea2025.1/idea.log"] {
            try box.file("Library/" + path, bytes: 10)
        }
        let finder = LeftoverFinder(home: box.home)
        let studio = finder.leftovers(bundleID: "com.google.android.studio", appName: "Android Studio").map(\.url.lastPathComponent)
        #expect(studio.sorted() == ["AndroidStudio2025.2.3", "AndroidStudio2025.2.3"])
        let chrome = finder.leftovers(bundleID: "com.google.Chrome", appName: "Google Chrome").map { $0.url.path }
        #expect(chrome.count == 1 && chrome[0].hasSuffix("Google/Chrome"))
        let idea = finder.leftovers(bundleID: "com.jetbrains.intellij", appName: "IntelliJ IDEA").map(\.url.lastPathComponent)
        #expect(idea == ["IntelliJIdea2025.1"])
        // A different product that merely starts with the name is left alone.
        try box.file("Library/Application Support/Google/AndroidStudioPreview/x", bytes: 10)
        #expect(!finder.leftovers(bundleID: "com.google.android.studio", appName: "Android Studio")
            .contains { $0.url.lastPathComponent == "AndroidStudioPreview" })
    }
}
