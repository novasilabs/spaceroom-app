// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Cleanup extras")
struct CleanupExtrasTests {
    private static let old = Date.now.addingTimeInterval(-10 * 86_400)

    private func bundledRule(_ id: String) throws -> Rule {
        try #require(try RuleCatalog.bundled().rules.first { $0.id == id })
    }

    @Test("Broken preferences: only empty or unparseable files, never unreadable or Apple's")
    func brokenPreferences() async throws {
        let box = try Sandbox()
        let rule = try bundledRule("system.broken-preferences")
        let prefs = "Library/Preferences/"
        let valid = try PropertyListSerialization.data(fromPropertyList: ["a": 1], format: .binary, options: 0)
        try box.file(prefs + "com.example.good.plist", bytes: 0)
        try valid.write(to: box.home.appendingPathComponent(prefs + "com.example.good.plist"))
        try Data("<?xml garbage".utf8).write(to: box.home.appendingPathComponent(prefs + "com.example.broken.plist"))
        try box.file(prefs + "com.example.empty.plist", bytes: 0)
        try Data("garbage".utf8).write(to: box.home.appendingPathComponent(prefs + "com.apple.finder.plist"))
        let locked = box.home.appendingPathComponent(prefs + "com.example.locked.plist")
        try Data("garbage".utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        for name in ["good", "broken", "empty"] {
            try box.backdate(box.home.appendingPathComponent(prefs + "com.example.\(name).plist"), to: Self.old)
        }

        let items = await Scanner().scan([rule], context: box.context()).results[0].items
        #expect(Set(items.map(\.url.lastPathComponent)) == ["com.example.broken.plist", "com.example.empty.plist"])
        #expect(items.allSatisfy { $0.isCleanable })
        #expect(rule.defaultSelected == false && rule.smartCare == false)
    }

    @Test("Broken preferences of a running app are skipped")
    func runningOwner() async throws {
        let box = try Sandbox()
        let rule = try bundledRule("system.broken-preferences")
        let url = try box.file("Library/Preferences/com.example.app.plist", bytes: 0, modified: Self.old)
        let items = await Scanner().scan([rule], context: box.context(running: ["com.example.app"])).results[0].items
        #expect(items.first?.url == url)
        #expect(items.first?.skipReason == .inUse(bundleID: "com.example.app"))
    }

    @Test("Mail attachment copies and Photos analysis caches are found, and wait while their app runs")
    func mailAndPhotos() async throws {
        let box = try Sandbox()
        let mail = try bundledRule("mail.downloads")
        let photos = try bundledRule("photos.analysis-caches")
        try box.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC/invoice.pdf", modified: Self.old)
        try box.backdate(box.home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC"), to: Self.old)
        try box.file("Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/com.apple.mediaanalysisd/x.db", modified: Self.old)
        try box.backdate(box.home.appendingPathComponent("Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/com.apple.mediaanalysisd"), to: Self.old)

        let report = await Scanner().scan([mail, photos], context: box.context())
        #expect(report.result(for: mail.id)?.cleanableItems.map(\.url.lastPathComponent) == ["ABC"])
        #expect(report.result(for: photos.id)?.cleanableItems.count == 1)

        let busy = await Scanner().scan([mail], context: box.context(running: ["com.apple.mail"]))
        #expect(busy.results[0].items.first?.skipReason == .inUse(bundleID: "com.apple.mail"))
    }

    @Test("Content checks", arguments: [(Data(), true), (Data("{".utf8), true), (Data("<plist><dict/></plist>".utf8), false)])
    func contentCheck(data: Data, fails: Bool) throws {
        let box = try Sandbox()
        let url = box.home.appendingPathComponent("p.plist")
        try data.write(to: url)
        #expect(ContentCheck.brokenPropertyList.fails(url) == fails)
        #expect(ContentCheck.brokenPropertyList.fails(box.home.appendingPathComponent("missing.plist")) == false)
    }
}

@Suite("Access detection")
struct AccessDetectionTests {
    @Test("A folder inside a container macOS won't let us look into counts as denied")
    func deniedParent() throws {
        let box = try Sandbox()
        let container = try box.folder("Library/Containers/com.example.locked/Data")
        try box.folder("Library/Containers/com.example.locked/Data/Downloads")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: container.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: container.path) }
        let pattern = try PathPattern("~/Library/Containers/com.example.locked/Data/Downloads/*")
        #expect(pattern.isAccessDenied(home: box.home))
        #expect(try PathPattern("~/Library/Nowhere/*").isAccessDenied(home: box.home) == false)
    }
}
