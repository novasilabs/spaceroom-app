// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Cleanup engine")
struct CleanupEngineTests {
    @Test("M0 exit criterion: scan → quarantine → restore, end to end")
    func endToEnd() async throws {
        let box = try Sandbox()
        try box.file("Library/Developer/Xcode/DerivedData/App-abc/Build/obj.o", bytes: 50_000)
        try box.file("Library/Developer/Xcode/DerivedData/Other-def/Index/db", bytes: 20_000)
        let rule = Rule.test("dev.xcode.derived-data", paths: ["~/Library/Developer/Xcode/DerivedData/*"],
                             skipIfRunning: ["com.apple.dt.Xcode"], module: .devCleanup)
        let context = box.context()
        let store = try box.store()

        let report = await Scanner().scan([rule], context: context)
        let items = report.results.flatMap(\.cleanableItems)
        #expect(items.count == 2)

        let outcome = try await CleanupEngine(store: store).clean(items, rules: [rule], module: .devCleanup, context: context)
        let op = try #require(outcome.operation)
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.freedSize == report.cleanableSize)
        #expect(!box.exists("Library/Developer/Xcode/DerivedData/App-abc"))
        #expect(op.module == "devCleanup")

        _ = try await store.restoreAll(in: op.id)
        #expect(box.exists("Library/Developer/Xcode/DerivedData/App-abc/Build/obj.o"))
        #expect(box.exists("Library/Developer/Xcode/DerivedData/Other-def/Index/db"))
    }

    @Test func dryRunTouchesNothing() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example/data")
        let rule = Rule.test()
        let report = await Scanner().scan([rule], context: box.context())

        let plan = CleanupEngine(store: try box.store()).plan(report.results[0].items, rules: [rule], context: box.context())
        #expect(plan.moves.count == 1)
        #expect(box.exists("Library/Caches/com.example/data"))
    }

    @Test func skipsItemReplacedAfterScan() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example/data")
        let rule = Rule.test()
        let report = await Scanner().scan([rule], context: box.context())

        // Swap the folder for a different object at the same path.
        try FileManager.default.removeItem(at: box.home.appendingPathComponent("Library/Caches/com.example"))
        try box.file("Library/Caches/com.example/other")

        let outcome = try await CleanupEngine(store: try box.store())
            .clean(report.results[0].items, rules: [rule], module: .cleanup, context: box.context())
        #expect(outcome.operation == nil)
        #expect(outcome.skipped.map(\.reason) == [.changedSinceScan])
        #expect(box.exists("Library/Caches/com.example/other"))
    }

    @Test func skipsWhenAppStartedAfterScan() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example/data")
        let rule = Rule.test(skipIfRunning: ["com.example"])
        let report = await Scanner().scan([rule], context: box.context())

        let outcome = try await CleanupEngine(store: try box.store())
            .clean(report.results[0].items, rules: [rule], module: .cleanup, context: box.context(running: ["com.example"]))
        #expect(outcome.skipped.map(\.reason) == [.inUse(bundleID: "com.example")])
        #expect(box.exists("Library/Caches/com.example/data"))
    }

    @Test func refusesItemsWithoutALoadedRule() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example/data")
        let report = await Scanner().scan([.test()], context: box.context())

        let outcome = try await CleanupEngine(store: try box.store())
            .clean(report.results[0].items, rules: [], module: .cleanup, context: box.context())
        #expect(outcome.operation == nil)
        #expect(box.exists("Library/Caches/com.example/data"))
    }

    @Test func neverCleansSkippedItems() async throws {
        let box = try Sandbox()
        try box.file("Library/Logs/Fresh/log.txt")
        let rule = Rule.test(paths: ["~/Library/Logs/*"], minAgeDays: 7)
        let report = await Scanner().scan([rule], context: box.context())

        let outcome = try await CleanupEngine(store: try box.store())
            .clean(report.results[0].items, rules: [rule], module: .cleanup, context: box.context())
        #expect(outcome.operation == nil)
        #expect(outcome.skipped.map(\.reason) == [.tooRecent(minAgeDays: 7)])
    }
}
