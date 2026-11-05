// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3
import Testing
@testable import SpaceroomCore

@Suite("Privacy")
struct PrivacyTests {
    let chrome = Browser.all.first { $0.id == "chrome" }!
    let firefox = Browser.all.first { $0.id == "firefox" }!

    func makeChromeProfile(_ box: Sandbox, profile: String = "Default") throws {
        let base = "Library/Application Support/Google/Chrome/\(profile)"
        for name in ["History", "History-journal", "Top Sites", "Cookies", "Web Data", "Login Data", "Bookmarks", "Preferences"] {
            try box.file("\(base)/\(name)", bytes: 2_000)
        }
    }

    @Test func findsChromiumDataButNeverPasswordsOrBookmarks() throws {
        let box = try Sandbox()
        try makeChromeProfile(box)
        try makeChromeProfile(box, profile: "Profile 1")
        let result = PrivacyScanner.scan(home: box.home, browsers: [chrome])
        #expect(result.lockedOwners.isEmpty)
        #expect(result.items.count == 6) // 2 profiles × history, cookies, autofill
        let history = try #require(result.items.first { $0.profile == "Default" && $0.kind == .history })
        #expect(Set(history.files.map(\.lastPathComponent)) == ["History", "History-journal", "Top Sites"])
        let allFiles = Set(result.items.flatMap(\.files).map(\.lastPathComponent))
        #expect(!allFiles.contains("Login Data"))
        #expect(!allFiles.contains("Bookmarks"))
        #expect(!allFiles.contains("Preferences"))
    }

    @Test func findsNewerChromiumCookieLocation() throws {
        let box = try Sandbox()
        try box.file("Library/Application Support/Google/Chrome/Default/History")
        try box.file("Library/Application Support/Google/Chrome/Default/Network/Cookies")
        let cookies = PrivacyScanner.scan(home: box.home, browsers: [chrome]).items.first { $0.kind == .cookies }
        #expect(cookies?.files.map(\.lastPathComponent) == ["Cookies"])
        #expect(cookies?.files.first?.deletingLastPathComponent().lastPathComponent == "Network")
    }

    @Test func firefoxNeverOffersHistoryBecauseBookmarksShareTheDatabase() throws {
        let box = try Sandbox()
        let base = "Library/Application Support/Firefox/Profiles/abc.default-release"
        for name in ["places.sqlite", "cookies.sqlite", "cookies.sqlite-wal", "formhistory.sqlite", "logins.json", "key4.db"] {
            try box.file("\(base)/\(name)")
        }
        let items = PrivacyScanner.scan(home: box.home, browsers: [firefox]).items
        #expect(Set(items.map(\.kind)) == [.cookies, .autofill])
        #expect(Set(items.flatMap(\.files).map(\.lastPathComponent)) == ["cookies.sqlite", "cookies.sqlite-wal", "formhistory.sqlite"])
    }

    @Test func reportsLockedBrowsers() throws {
        let box = try Sandbox()
        try makeChromeProfile(box)
        let root = box.home.appendingPathComponent("Library/Application Support/Google/Chrome")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let result = PrivacyScanner.scan(home: box.home, browsers: [chrome])
        #expect(result.items.isEmpty)
        #expect(result.lockedOwners == ["Google Chrome"])
    }

    @Test func recentItemsAreTheRecentListsOnly() throws {
        let box = try Sandbox()
        let base = "Library/Application Support/com.apple.sharedfilelist"
        try box.file("\(base)/com.apple.LSSharedFileList.RecentDocuments.sfl3")
        try box.file("\(base)/com.apple.LSSharedFileList.RecentApplications.sfl3")
        try box.file("\(base)/com.apple.LSSharedFileList.FavoriteItems.sfl3") // Finder sidebar: not a recent list
        try box.file("\(base)/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.apple.textedit.sfl3")
        let item = try #require(PrivacyScanner.scan(home: box.home, browsers: []).items.first)
        #expect(item.kind == .recentItems)
        #expect(Set(item.files.map(\.lastPathComponent)) == [
            "com.apple.LSSharedFileList.RecentDocuments.sfl3", "com.apple.LSSharedFileList.RecentApplications.sfl3",
            "com.apple.textedit.sfl3"])
    }

    @Test func refusesWhileTheBrowserIsOpen() async throws {
        let box = try Sandbox()
        try makeChromeProfile(box)
        let items = PrivacyScanner.scan(home: box.home, browsers: [chrome]).items
        let cleaner = PrivacyCleaner(store: try box.store(), home: box.home)
        await #expect(throws: PrivacyError.browserRunning("Google Chrome")) {
            try await cleaner.clear(items, runningBundleIDs: ["com.google.Chrome"])
        }
        #expect(box.exists("Library/Application Support/Google/Chrome/Default/History"))
    }

    @Test func clearsIntoTheRestoreCenterAndNeverTouchesPasswords() async throws {
        let box = try Sandbox()
        try makeChromeProfile(box)
        var items = PrivacyScanner.scan(home: box.home, browsers: [chrome]).items.filter { $0.kind == .history }
        // Even if a bad caller slips saved passwords into an item, they are refused.
        let passwords = box.home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Login Data")
        items.append(PrivacyItem(owner: "chrome", ownerName: "Google Chrome", bundleID: "com.google.Chrome", profile: "Default",
                                 kind: .history, files: [passwords], size: 0))
        let cleaner = PrivacyCleaner(store: try box.store(), home: box.home)

        let outcome = try await cleaner.clear(items, runningBundleIDs: [])
        let op = try #require(outcome.operation)
        #expect(op.module == "privacy")
        #expect(!box.exists("Library/Application Support/Google/Chrome/Default/History"))
        #expect(box.exists("Library/Application Support/Google/Chrome/Default/Login Data"))
        #expect(outcome.skipped.map(\.path) == [passwords.path])

        _ = try await cleaner.store.restoreAll(in: op.id)
        #expect(box.exists("Library/Application Support/Google/Chrome/Default/History"))
    }

    @Test func readsPermissionDatabasesReadOnly() throws {
        let box = try Sandbox()
        let db = box.home.appendingPathComponent("TCC.db")
        var handle: OpaquePointer?
        #expect(sqlite3_open(db.path, &handle) == SQLITE_OK)
        sqlite3_exec(handle, """
            CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER);
            INSERT INTO access VALUES ('kTCCServiceCamera', 'us.zoom.xos', 2), ('kTCCServiceMicrophone', 'com.example', 0);
            """, nil, nil, nil)
        sqlite3_close(handle)

        let grants = try #require(PermissionsReader.read(db))
        #expect(grants.count == 2)
        #expect(grants.first { $0.service == PermissionService.camera.rawValue }?.allowed == true)
        #expect(grants.first { $0.client == "com.example" }?.allowed == false)
        #expect(PermissionsReader.read(box.home.appendingPathComponent("missing.db")) == nil)
    }
}
