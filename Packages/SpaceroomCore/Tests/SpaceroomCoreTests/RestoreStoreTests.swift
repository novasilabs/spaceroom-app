// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Restore Center store")
struct RestoreStoreTests {
    func move(_ url: URL, size: Int64 = 4096) -> PlannedMove {
        PlannedMove(url: url, ruleID: "test.rule", size: size, isDirectory: true)
    }

    @Test func quarantineThenRestore() async throws {
        let box = try Sandbox()
        let item = try box.file("Library/Caches/com.example/data").deletingLastPathComponent()
        let store = try box.store()

        let (record, failures) = try await store.quarantine([move(item)], module: "cleanup")
        let op = try #require(record)
        #expect(failures.isEmpty)
        #expect(!box.exists("Library/Caches/com.example"))
        #expect(op.items.first?.storage == .quarantine)
        #expect(await store.storedSize == 4096)

        let outcomes = try await store.restoreAll(in: op.id)
        #expect(outcomes.count == 1)
        #expect(box.exists("Library/Caches/com.example/data"))
        #expect(await store.storedSize == 0)
        let restored = try #require(await store.operation(op.id)?.items.first)
        #expect(!restored.isStored)
    }

    @Test func restoreNextToNewItemWhenOriginalPathIsTaken() async throws {
        let box = try Sandbox()
        let item = try box.file("Library/Caches/com.example/data").deletingLastPathComponent()
        let store = try box.store()
        let op = try #require(try await store.quarantine([move(item)], module: "cleanup").record)

        try box.file("Library/Caches/com.example/new-data") // the app recreated its cache
        let outcomes = try await store.restoreAll(in: op.id)

        guard case .restoredRenamed(_, let path) = try #require(outcomes.first) else {
            Issue.record("expected renamed restore, got \(outcomes)")
            return
        }
        #expect(path.hasSuffix("com.example (restored)"))
        #expect(box.exists("Library/Caches/com.example/new-data"))
        #expect(box.exists("Library/Caches/com.example (restored)/data"))
    }

    @Test func restoreRecreatesMissingParentFolders() async throws {
        let box = try Sandbox()
        let item = try box.file("Library/Developer/Xcode/DerivedData/App-1/x").deletingLastPathComponent()
        let store = try box.store()
        let op = try #require(try await store.quarantine([move(item)], module: "devCleanup").record)

        try FileManager.default.removeItem(at: box.home.appendingPathComponent("Library/Developer"))
        _ = try await store.restoreAll(in: op.id)
        #expect(box.exists("Library/Developer/Xcode/DerivedData/App-1/x"))
    }

    @Test func partialFailureStillMovesTheRest() async throws {
        let box = try Sandbox()
        let good = try box.file("Library/Caches/good/x").deletingLastPathComponent()
        let gone = box.home.appendingPathComponent("Library/Caches/gone")
        let store = try box.store()

        let (record, failures) = try await store.quarantine([move(gone), move(good)], module: "cleanup")
        #expect(record?.items.map(\.name) == ["good"])
        #expect(failures.map(\.path) == [gone.path])
    }

    @Test func nothingMovedMeansNoRecord() async throws {
        let box = try Sandbox()
        let store = try box.store()
        let (record, failures) = try await store.quarantine(
            [move(box.home.appendingPathComponent("nope"))], module: "cleanup")
        #expect(record == nil)
        #expect(failures.count == 1)
        #expect(await store.operations.isEmpty)
    }

    @Test func purgeDeletesPermanently() async throws {
        let box = try Sandbox()
        let item = try box.file("Library/Caches/com.example/data").deletingLastPathComponent()
        let store = try box.store()
        let op = try #require(try await store.quarantine([move(item)], module: "cleanup").record)
        let storedPath = try #require(op.items.first).storedPath

        let freed = try await store.purge(op.id)
        #expect(freed == 4096)
        #expect(!FileManager.default.fileExists(atPath: storedPath))
        #expect(try await store.restoreAll(in: op.id).isEmpty)
    }

    @Test func expiredOperationsArePurged() async throws {
        let box = try Sandbox()
        let oldItem = try box.file("Library/Caches/old/x").deletingLastPathComponent()
        let newItem = try box.file("Library/Caches/new/x").deletingLastPathComponent()
        let store = try box.store()
        let now = Date.now
        let old = try #require(try await store.quarantine([move(oldItem)], module: "cleanup",
                                                         now: now.addingTimeInterval(-8 * 86_400)).record)
        let new = try #require(try await store.quarantine([move(newItem)], module: "cleanup", now: now).record)

        try await store.purgeExpired(retentionDays: 7, now: now)
        #expect(await store.operation(old.id)?.hasStoredItems == false)
        #expect(await store.operation(new.id)?.hasStoredItems == true)
    }

    @Test func indexSurvivesRelaunch() async throws {
        let box = try Sandbox()
        let item = try box.file("Library/Caches/com.example/data").deletingLastPathComponent()
        let op = try #require(try await box.store().quarantine([move(item)], module: "cleanup").record)

        let reopened = try box.store()
        #expect(await reopened.operations.map(\.id) == [op.id])
        _ = try await reopened.restoreAll(in: op.id)
        #expect(box.exists("Library/Caches/com.example/data"))
    }

    @Test func corruptIndexFailsClosed() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.support, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: box.support.appendingPathComponent("operations.json"))
        #expect(throws: RestoreStoreError.self) { try RestoreStore(directory: box.support) }
        // The unreadable index is left untouched for recovery.
        #expect(try String(contentsOf: box.support.appendingPathComponent("operations.json"), encoding: .utf8) == "not json")
    }
}

@Suite("Restore destination naming")
struct RestoreDestinationTests {
    @Test func filesKeepExtensionFoldersKeepFullName() throws {
        let box = try Sandbox()
        let file = try box.file("Library/Logs/report.log")
        let folder = try box.folder("Library/Caches/com.example")
        #expect(RestoreStore.freeDestination(for: file, isDirectory: false).lastPathComponent == "report (restored).log")
        #expect(RestoreStore.freeDestination(for: folder, isDirectory: true).lastPathComponent == "com.example (restored)")
        try box.folder("Library/Caches/com.example (restored)")
        #expect(RestoreStore.freeDestination(for: folder, isDirectory: true).lastPathComponent == "com.example (restored 2)")
    }
}
