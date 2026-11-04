// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Scanner")
struct ScannerTests {
    @Test func measuresItemsLargestFirst() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/small/a", bytes: 10_000)
        try box.file("Library/Caches/big/a", bytes: 200_000)
        try box.file("Library/Caches/big/b", bytes: 200_000)

        let report = await Scanner().scan([.test()], context: box.context())
        let items = try #require(report.result(for: "test.rule")).items
        #expect(items.map(\.url.lastPathComponent) == ["big", "small"])
        #expect(items[0].size >= 400_000)
        #expect(items[0].fileCount == 2)
        #expect(report.cleanableSize == items.reduce(0) { $0 + $1.size })
    }

    @Test func moreSpecificRuleClaimsItsFolder() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/Homebrew/bottle.tar.gz")
        try box.file("Library/Caches/com.example/data")
        let general = Rule.test("general", paths: ["~/Library/Caches/*"])
        let brew = Rule.test("brew", paths: ["~/Library/Caches/Homebrew/*"])

        // Even when only the general rule is scanned, Homebrew stays with its own rule.
        let report = await Scanner().scan([general], claimRules: [general, brew], context: box.context())
        let names = try #require(report.result(for: "general")).items.map(\.url.lastPathComponent)
        #expect(names == ["com.example"])
    }

    @Test func skipsWhileAppIsRunning() async throws {
        let box = try Sandbox()
        try box.file("Library/Developer/Xcode/DerivedData/App-abc/Build/x")
        let rule = Rule.test(paths: ["~/Library/Developer/Xcode/DerivedData/*"], skipIfRunning: ["com.apple.dt.Xcode"])

        let report = await Scanner().scan([rule], context: box.context(running: ["com.apple.dt.Xcode"]))
        let item = try #require(report.results.first?.items.first)
        #expect(item.skipReason == .inUse(bundleID: "com.apple.dt.Xcode"))
        #expect(report.cleanableSize == 0)
    }

    @Test func skipsCacheOfRunningOwnerApp() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.tinyspeck.slackmacgap/data")
        try box.file("Library/Caches/com.example.closed/data")
        let rule = Rule.test(skipIfOwnerRunning: true)

        let report = await Scanner().scan([rule], context: box.context(running: ["com.tinyspeck.slackmacgap"]))
        let items = try #require(report.results.first).items
        let slack = try #require(items.first { $0.url.lastPathComponent == "com.tinyspeck.slackmacgap" })
        let closed = try #require(items.first { $0.url.lastPathComponent == "com.example.closed" })
        #expect(slack.skipReason == .inUse(bundleID: "com.tinyspeck.slackmacgap"))
        #expect(closed.isCleanable)
    }

    @Test func respectsMinimumAgeUsingNewestFileInside() async throws {
        let box = try Sandbox()
        let old = Date.now.addingTimeInterval(-30 * 86_400)
        try box.file("Library/Logs/OldApp/log.txt", modified: old)
        try box.backdate(box.home.appendingPathComponent("Library/Logs/OldApp"), to: old)
        try box.file("Library/Logs/MixedApp/old.txt", modified: old)
        try box.file("Library/Logs/MixedApp/new.txt") // fresh file keeps the whole folder
        let rule = Rule.test(paths: ["~/Library/Logs/*"], minAgeDays: 7)

        let report = await Scanner().scan([rule], context: box.context())
        let items = try #require(report.results.first).items
        #expect(items.first { $0.url.lastPathComponent == "OldApp" }?.isCleanable == true)
        #expect(items.first { $0.url.lastPathComponent == "MixedApp" }?.skipReason == .tooRecent(minAgeDays: 7))
    }

    @Test func streamsEventsAndFinishes() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/a/x")
        try box.file("Library/Logs/b/x")
        let rules = [Rule.test("one"), Rule.test("two", paths: ["~/Library/Logs/*"])]

        var finishedRules: [String] = []
        var report: ScanReport?
        for await event in Scanner().events(for: rules, context: box.context()) {
            switch event {
            case .started: break
            case .ruleFinished(let result, _, _): finishedRules.append(result.rule.id)
            case .finished(let r): report = r
            }
        }
        #expect(Set(finishedRules) == ["one", "two"])
        #expect(try #require(report).results.map(\.rule.id) == ["one", "two"]) // catalog order preserved
    }
}

@Suite("Scanner — ownership and access")
struct ScannerOwnershipTests {
    @Test func skipsCacheNamedAfterRunningAppName() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/Dia/data")
        try box.file("Library/Caches/OtherApp/data")
        let rule = Rule.test(skipIfOwnerRunning: true)
        let context = ScanContext(home: box.home, runningBundleIDs: ["company.thebrowser.dia"], runningAppNames: ["Dia"])

        let items = await Scanner().scan([rule], context: context).results[0].items
        #expect(items.first { $0.url.lastPathComponent == "Dia" }?.skipReason == .inUse(bundleID: "Dia"))
        #expect(items.first { $0.url.lastPathComponent == "OtherApp" }?.isCleanable == true)
    }

    @Test func reportsUnreadableFolders() async throws {
        let box = try Sandbox()
        let locked = try box.folder(".Trash")
        try box.file(".Trash/old.zip")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let result = await Scanner().scan([.test(paths: ["~/.Trash/*"])], context: box.context()).results[0]
        #expect(result.accessDenied)
        #expect(result.items.isEmpty)
    }
}
