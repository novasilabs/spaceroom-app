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

        let freed = try await store.purge(op.id).freed
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

@Suite("Restore Center purge")
struct RestorePurgeTests {
    func move(_ url: URL) -> PlannedMove { PlannedMove(url: url, ruleID: "test.rule", size: 4096, isDirectory: true) }

    @Test("Regression: read-only folders (dotslash, Go, Cargo caches) are really deleted")
    func purgesReadOnlyFolders() async throws {
        let box = try Sandbox()
        let item = try box.folder("Library/Caches/dotslash")
        try box.file("Library/Caches/dotslash/bd/App.app/Contents/MacOS/tool")
        for sub in ["bd/App.app/Contents/MacOS", "bd/App.app/Contents", "bd/App.app", "bd"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555],
                                                  ofItemAtPath: item.appendingPathComponent(sub).path)
        }
        let store = try box.store()
        let op = try #require(try await store.quarantine([move(item)], module: "cleanup").record)
        let stored = try #require(op.items.first).storedPath

        try await store.purge(op.id)
        #expect(!FileManager.default.fileExists(atPath: stored))
        #expect(await store.operation(op.id)?.hasStoredItems == false)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: box.support.appendingPathComponent("Quarantine").path)) ?? [] == [])
    }

    @Test func undeletableItemsStayRestorable() async throws {
        let box = try Sandbox()
        let item = try box.file("Library/Caches/locked/file").deletingLastPathComponent()
        let store = try box.store()
        await store.setTrashHandler { _ in throw CocoaError(.fileWriteNoPermission) }
        let op = try #require(try await store.quarantine([move(item)], module: "cleanup").record)
        let stored = URL(fileURLWithPath: try #require(op.items.first).storedPath)
        // Make the item undeletable: an immutable (uchg) folder can't be removed even by its owner.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: stored.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: stored.path) }

        await #expect(throws: RestoreStoreError.self) { try await store.purge(op.id) }
        #expect(await store.operation(op.id)?.hasStoredItems == true)
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func removesOrphanedFolders() async throws {
        let box = try Sandbox()
        let item = try box.file("Library/Caches/keep/file").deletingLastPathComponent()
        let store = try box.store()
        let kept = try #require(try await store.quarantine([move(item)], module: "cleanup").record)
        let orphan = box.support.appendingPathComponent("Quarantine/\(UUID().uuidString)/0-left")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: orphan.path)

        #expect(await store.removeOrphanedFolders().freed >= 0)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: try #require(kept.items.first).storedPath))
    }
}

@Suite("Restore Center purge — protected items")
struct RestoreProtectedPurgeTests {
    @Test("Items macOS won't delete in place go to the Trash instead of leaking")
    func fallsBackToTrash() async throws {
        let box = try Sandbox()
        let item = try box.folder("Library/Caches/dotslash")
        // A child macOS refuses to delete (stands in for an App Management–protected bundle).
        let locked = try box.folder("Library/Caches/dotslash/Tool.app")
        try box.file("Library/Caches/dotslash/Tool.app/binary")
        let fakeTrash = try box.folder("FakeTrash")
        let store = try box.store()
        await store.setTrashHandler { url in
            try FileManager.default.moveItem(at: url, to: fakeTrash.appendingPathComponent(url.lastPathComponent))
        }
        let op = try #require(try await store.quarantine(
            [PlannedMove(url: item, ruleID: "test.rule", size: 8192, isDirectory: true)], module: "cleanup").record)
        let storedLocked = URL(fileURLWithPath: try #require(op.items.first).storedPath).appendingPathComponent("Tool.app")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: storedLocked.path)
        _ = locked

        let result = try await store.purge(op.id)
        #expect(result.movedToTrash.count == 1)
        #expect(result.movedToTrashSize == 8192)
        #expect(await store.operation(op.id)?.hasStoredItems == false)
        let quarantine = box.support.appendingPathComponent("Quarantine")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: quarantine.path)) ?? []).isEmpty)

        // Clean up the immutable flag so the sandbox can be deleted.
        let trashed = try FileManager.default.contentsOfDirectory(atPath: fakeTrash.path)
        for name in trashed {
            let tool = fakeTrash.appendingPathComponent(name).appendingPathComponent("Tool.app")
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: tool.path)
        }
    }
}
