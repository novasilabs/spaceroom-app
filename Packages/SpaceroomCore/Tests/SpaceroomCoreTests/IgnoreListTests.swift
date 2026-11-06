// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Ignore list")
struct IgnoreListTests {
    @Test func pathsProtectThemselvesTheirContentsAndTheirParents() throws {
        let box = try Sandbox()
        let project = try box.folder("Library/Caches/Keep/project")
        let list = IgnoreList(entries: [.path(project)])
        #expect(list.ignores(project))
        #expect(list.ignores(project.appendingPathComponent("sub/file.bin")))
        // Cleaning the parent would take the ignored folder along.
        #expect(list.ignores(project.deletingLastPathComponent()))
        #expect(!list.ignores(box.home.appendingPathComponent("Library/Caches/Other")))
        #expect(!list.ignores(box.home.appendingPathComponent("Library/Caches/Keep/projectile")))
    }

    @Test func appEntriesCoverDataNamedAfterTheApp() {
        let list = IgnoreList(entries: [.app("com.example.Notes")])
        for name in ["com.example.Notes", "com.example.notes.helper", "com.example.Notes.savedState", "group.com.example.Notes"] {
            #expect(list.ignoresItem(named: name), "\(name)")
        }
        #expect(!list.ignoresItem(named: "com.example.NotesPro"))
        #expect(list.ignoresApp("COM.EXAMPLE.NOTES"))
    }

    @Test func noDuplicatesAndRemoval() {
        var list = IgnoreList()
        list.add(.rule("system.user-logs"))
        list.add(.rule("system.user-logs"))
        #expect(list.entries.count == 1)
        list.remove(id: IgnoreEntry.rule("system.user-logs").id)
        #expect(list.isEmpty)
    }

    @Test func scansMarkIgnoredItemsAndSkipIgnoredCategories() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.keep.me/data.bin")
        try box.file("Library/Caches/com.example.app/data.bin")
        try box.file("Library/Caches/Projects/important/x.bin")
        let rule = Rule.test()
        let ignore = IgnoreList(entries: [.app("com.keep.me"),
                                          .path(box.home.appendingPathComponent("Library/Caches/Projects/important"))])
        let report = await Scanner().scan([rule], context: ScanContext(home: box.home, ignore: ignore))
        let reasons = Dictionary(uniqueKeysWithValues: report.results[0].items.map { ($0.url.lastPathComponent, $0.skipReason) })
        #expect(reasons["com.keep.me"] == .ignored)
        #expect(reasons["Projects"] == .ignored) // contains an ignored folder
        #expect(reasons["com.example.app"] == SkipReason?.none)

        let skipped = await Scanner().scan([rule], context: ScanContext(home: box.home, ignore: IgnoreList(entries: [.rule(rule.id)])))
        #expect(skipped.results[0].items.isEmpty)
    }

    @Test func cleaningRechecksTheListAddedAfterTheScan() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example.app/data.bin")
        let rule = Rule.test()
        let report = await Scanner().scan([rule], context: box.context())
        let item = try #require(report.results[0].items.first)
        let later = ScanContext(home: box.home, ignore: IgnoreList(entries: [.path(item.url)]))
        let outcome = try await CleanupEngine(store: try box.store()).clean([item], rules: [rule], operationName: "cleanup", context: later)
        #expect(outcome.operation == nil)
        #expect(outcome.skipped.map(\.reason) == [.ignored])
        #expect(box.exists("Library/Caches/com.example.app/data.bin"))
    }

    @Test func theRestoreCenterRefusesIgnoredMovesFromAnyModule() async throws {
        let box = try Sandbox()
        let keep = try box.file("Downloads/keep.dmg")
        let other = try box.file("Downloads/other.dmg")
        let store = try RestoreStore(directory: box.support, ignore: .list(IgnoreList(entries: [.path(keep)])))
        let moves = [keep, other].map { PlannedMove(url: $0, ruleID: "clutter.installer", size: 4096, isDirectory: false) }
        let (record, failures) = try await store.quarantine(moves, module: "clutter")
        #expect(record?.items.count == 1)
        #expect(failures == [MoveFailure(path: keep.path, reason: .ignored)])
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(!FileManager.default.fileExists(atPath: other.path))
    }

    @Test func anUnreadableListBlocksEveryMove() async throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.support, withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: IgnoreListFile.url(in: box.support))
        #expect(throws: (any Error).self) { try IgnoreListFile.load(directory: box.support) }

        let file = try box.file("Downloads/a.dmg")
        let store = try RestoreStore(directory: box.support, ignore: .unavailable("corrupt"))
        await #expect(throws: RestoreStoreError.self) {
            _ = try await store.quarantine([PlannedMove(url: file, ruleID: "x", size: 1, isDirectory: false)], module: "clutter")
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func savesAndLoads() throws {
        let box = try Sandbox()
        let list = IgnoreList(entries: [.app("com.example.app"), .rule("trash.user"), .path(box.home.appendingPathComponent("Projects"))])
        try IgnoreListFile.save(list, directory: box.support)
        #expect(try IgnoreListFile.load(directory: box.support) == list)
        #expect(try IgnoreListFile.load(directory: box.home.appendingPathComponent("nowhere")).isEmpty)
    }
}

@Suite("Ignore list: one file, one path")
struct IgnoreCanonicalTests {
    @Test("Ignoring from a startup-disk scan protects the file however it's reached")
    func firmlink() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var list = IgnoreList()
        list.add(.path(URL(fileURLWithPath: "/System/Volumes/Data" + home + "/Projects/keep")))
        #expect(list.ignores(URL(fileURLWithPath: home + "/Projects/keep/file.txt")))
        #expect(list.ignores(URL(fileURLWithPath: "/System/Volumes/Data" + home + "/Projects/keep")))
        let old = IgnoreList(entries: [IgnoreEntry(kind: .rule, value: "x")])
        #expect(!old.ignores(URL(fileURLWithPath: home + "/Projects/keep")))
    }
}
