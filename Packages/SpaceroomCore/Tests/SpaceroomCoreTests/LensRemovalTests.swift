// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Space Lens removal")
struct LensRemovalTests {
    private func node(_ url: URL, size: Int64 = 4096, folder: Bool = false) -> DiskNode {
        DiskNode(name: url.lastPathComponent, path: url.path, kind: folder ? .folder : .file, size: size, itemCount: 1)
    }

    @Test("Policy allows personal items and refuses structural folders, other places and Spaceroom's data")
    func policy() throws {
        let box = try Sandbox()
        let own = box.home.appendingPathComponent("Library/Application Support/Spaceroom")
        let policy = LensRemovalPolicy(home: box.home, ownData: own)
        let h = box.home

        #expect(policy.verdict(for: h.appendingPathComponent("Documents/Project")) == .allowed)
        #expect(policy.verdict(for: h.appendingPathComponent("Downloads/movie.mov")) == .allowed)
        #expect(policy.verdict(for: h.appendingPathComponent("development")) == .allowed)
        #expect(policy.verdict(for: h.appendingPathComponent("Library/Application Support/Claude")) == .allowed)
        #expect(policy.verdict(for: h.appendingPathComponent("Library/Caches/com.example")) == .allowed)

        #expect(policy.verdict(for: h) == .outsideHome)
        #expect(policy.verdict(for: URL(fileURLWithPath: "/Applications/Safari.app")) == .outsideHome)
        #expect(policy.verdict(for: URL(fileURLWithPath: "/Users/Shared/file")) == .outsideHome)
        #expect(policy.verdict(for: h.appendingPathComponent("Documents")) == .protectedFolder)
        #expect(policy.verdict(for: h.appendingPathComponent("Library")) == .protectedFolder)
        #expect(policy.verdict(for: h.appendingPathComponent("Library/Application Support")) == .protectedFolder)
        #expect(policy.verdict(for: h.appendingPathComponent("Library/Containers")) == .protectedFolder)
        #expect(policy.verdict(for: h.appendingPathComponent("Library/Keychains/login.keychain-db")) == .protectedFolder)
        #expect(policy.verdict(for: own) == .spaceroomData)
        #expect(policy.verdict(for: own.appendingPathComponent("Quarantine")) == .spaceroomData)

        let other = DiskNode(id: h.path + "/\u{0}other", name: "", path: h.path, kind: .other(count: 3), size: 10, itemCount: 3)
        #expect(policy.verdict(for: other) == .notAnItem)
    }

    @Test("Startup-disk paths through /System/Volumes/Data map to the real path")
    func firmlink() {
        #expect(LensRemovalPolicy.canonical(URL(fileURLWithPath: "/System/Volumes/Data/Users/someone/file"))
            .hasSuffix("/Users/someone/file"))
    }

    @Test("Removes picked items into the Restore Center and refuses the rest; Undo brings them back")
    func removeAndRestore() async throws {
        let box = try Sandbox()
        let video = try box.file("Movies/clip.mov", bytes: 8000)
        let project = try box.folder("development/old-project")
        try box.file("development/old-project/main.swift", bytes: 500)
        let documents = box.home.appendingPathComponent("Documents")
        try box.folder("Documents")
        let support = try box.folder("Library/Application Support")
        let remover = LensRemover(store: try box.store(), home: box.home)

        let outcome = try await remover.remove([
            node(video), node(project, folder: true), node(documents, folder: true), node(support, folder: true),
            node(URL(fileURLWithPath: box.home.path + "/gone.txt")),
        ])
        let op = try #require(outcome.operation)
        #expect(op.module == "spaceLens")
        #expect(Set(op.items.map(\.name)) == ["clip.mov", "old-project"])
        #expect(outcome.skipped.count == 3)
        #expect(!box.exists("Movies/clip.mov"))
        #expect(!box.exists("development/old-project"))
        #expect(box.exists("Documents"))
        #expect(box.exists("Library/Application Support"))

        _ = try await remover.store.restoreAll(in: op.id)
        #expect(box.exists("Movies/clip.mov"))
        #expect(box.exists("development/old-project/main.swift"))
    }

    @Test("Ignored items are refused by the Restore Center")
    func ignored() async throws {
        let box = try Sandbox()
        let keep = try box.file("Movies/keep.mov")
        var list = IgnoreList()
        list.add(.path(keep))
        let store = try RestoreStore(directory: box.support, ignore: .list(list))
        let outcome = try await LensRemover(store: store, home: box.home).remove([node(keep)])
        #expect(outcome.operation == nil)
        #expect(outcome.skipped.map(\.reason) == [.ignored])
        #expect(box.exists("Movies/keep.mov"))
    }

    @Test("A folder and something inside it move once, as the folder")
    func outermost() throws {
        let a = DiskNode(name: "a", path: "/h/a", kind: .folder, size: 10, itemCount: 2)
        let inside = DiskNode(name: "b", path: "/h/a/b", kind: .file, size: 5, itemCount: 1)
        let sibling = DiskNode(name: "ab", path: "/h/ab", kind: .file, size: 1, itemCount: 1)
        #expect(LensRemover.outermost([inside, a, sibling, a]).map(\.path) == ["/h/a", "/h/ab"])
    }

    @Test("Removing nodes shrinks every folder above them")
    func treeUpdate() {
        let file = DiskNode(name: "f", path: "/r/a/f", kind: .file, size: 30, itemCount: 1)
        let other = DiskNode(id: "/r/a/\u{0}other", name: "", path: "/r/a", kind: .other(count: 4), size: 5, itemCount: 4)
        let a = DiskNode(name: "a", path: "/r/a", kind: .folder, size: 35, itemCount: 6, children: [file, other])
        let b = DiskNode(name: "b", path: "/r/b", kind: .file, size: 10, itemCount: 1)
        let root = DiskNode(name: "r", path: "/r", kind: .folder, size: 45, itemCount: 8, children: [a, b])

        let updated = root.removing(paths: ["/r/a/f"])
        #expect(updated.size == 15)
        #expect(updated.itemCount == 7)
        #expect(updated.children[0].size == 5)
        #expect(updated.children[0].children.map(\.id) == ["/r/a/\u{0}other"])

        let whole = root.removing(paths: ["/r/a"])
        #expect(whole.children.map(\.path) == ["/r/b"])
        #expect(whole.size == 10)
        #expect(root.removing(paths: ["/elsewhere/x"]) == root)
    }
}

@Suite("Space Lens removal on external drives")
struct LensExternalRemovalTests {
    @Test("Items on an external drive are allowed, except its system and hidden folders")
    func policy() throws {
        let box = try Sandbox()
        let drive = try box.folder("../Volumes/Backup Drive")
        let policy = LensRemovalPolicy(home: box.home, ownData: box.support, volumes: [drive])
        #expect(policy.verdict(for: drive.appendingPathComponent("Videos/2024")) == .allowed)
        #expect(policy.verdict(for: drive.appendingPathComponent("old.dmg")) == .allowed)
        #expect(policy.verdict(for: drive) == .outsideHome)
        #expect(policy.verdict(for: drive.appendingPathComponent(".Spotlight-V100")) == .protectedFolder)
        #expect(policy.verdict(for: drive.appendingPathComponent(".Trashes/501")) == .protectedFolder)
        #expect(policy.verdict(for: drive.appendingPathComponent("System/Library")) == .protectedFolder)
        #expect(policy.verdict(for: drive.appendingPathComponent("Users/someone/file")) == .protectedFolder)
        #expect(policy.verdict(for: drive.appendingPathComponent("Backups.backupdb")) == .protectedFolder)
        // A drive that isn't in the list stays off limits.
        let other = LensRemovalPolicy(home: box.home, ownData: box.support)
        #expect(other.verdict(for: drive.appendingPathComponent("Videos")) == .outsideHome)
    }

    @Test("Removing from an external drive checks containment against the drive and can be undone")
    func remove() async throws {
        let box = try Sandbox()
        let drive = try box.folder("../Volumes/Drive")
        let clip = drive.appendingPathComponent("Videos/clip.mov")
        try FileManager.default.createDirectory(at: clip.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 5000).write(to: clip)
        let remover = LensRemover(store: try box.store(), home: box.home, volumes: [drive])
        let node = DiskNode(name: "clip.mov", path: clip.path, kind: .file, size: 5000, itemCount: 1)
        let outcome = try await remover.remove([node])
        let op = try #require(outcome.operation)
        #expect(!FileManager.default.fileExists(atPath: clip.path))
        _ = try await remover.store.restoreAll(in: op.id)
        #expect(FileManager.default.fileExists(atPath: clip.path))
    }
}

@Suite("Removal safety: apps and running programs")
struct RemovalSafetyTests {
    /// Copies /bin/sleep into the sandbox and runs it, so a "program inside the folder" is running.
    private func runSleep(at url: URL) throws -> Process {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: url)
        let process = Process()
        process.executableURL = url
        process.arguments = ["30"]
        try process.run()
        // Wait until the process has actually started running this executable (under load,
        // exec can take a while), so the tests check removal, not timing.
        let deadline = Date.now.addingTimeInterval(5)
        while RunningProcesses.current().program(inside: url) == nil, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return process
    }

    @Test("Running programs are found by path")
    func detects() throws {
        let box = try Sandbox()
        let tool = box.home.appendingPathComponent("Downloads/Tool.app/Contents/MacOS/tool")
        let process = try runSleep(at: tool)
        defer { process.terminate() }
        let running = RunningProcesses.current()
        #expect(running.program(inside: box.home.appendingPathComponent("Downloads/Tool.app")) == "Tool")
        #expect(running.program(inside: box.home.appendingPathComponent("Downloads")) == "Tool")
        #expect(running.program(inside: box.home.appendingPathComponent("Documents")) == nil)
    }

    @Test("Protection never moves a running program")
    func protection() async throws {
        let box = try Sandbox()
        let tool = box.home.appendingPathComponent("Downloads/payload")
        let process = try runSleep(at: tool)
        defer { process.terminate() }
        let finding = ThreatFinding(url: tool, kind: .disguisedProgram, severity: .high, evidence: "", size: 100)
        let outcome = try await ThreatRemover(store: try box.store(), home: box.home).remove([finding])
        #expect(outcome.operation == nil)
        #expect(outcome.skipped.first?.reason == .running(name: "payload"))
        #expect(FileManager.default.fileExists(atPath: tool.path))
    }

    @Test("Space Lens leaves apps to Applications and skips running programs")
    func lens() async throws {
        let box = try Sandbox()
        try box.folder("Applications/Tool.app/Contents/MacOS")
        let folderWithApp = try box.folder("Downloads/Bundle")
        try box.folder("Downloads/Bundle/Inner.app/Contents")
        let policy = LensRemovalPolicy(home: box.home, ownData: box.support)
        let app = DiskNode(name: "Tool.app", path: box.home.appendingPathComponent("Applications/Tool.app").path,
                           kind: .package, size: 10, itemCount: 1)
        #expect(policy.verdict(for: app) == .application)
        let folder = DiskNode(name: "Bundle", path: folderWithApp.path, kind: .folder, size: 10, itemCount: 2)
        #expect(policy.verdict(for: folder) == .allowed)   // the map didn't show the app inside…
        let remover = LensRemover(store: try box.store(), home: box.home)
        let outcome = try await remover.remove([folder])    // …but removal checks the disk
        #expect(outcome.operation == nil)
        #expect(FileManager.default.fileExists(atPath: folderWithApp.path))

        let running = box.home.appendingPathComponent("Downloads/Tools/server")
        let process = try runSleep(at: running)
        defer { process.terminate() }
        let tools = DiskNode(name: "Tools", path: running.deletingLastPathComponent().path, kind: .folder, size: 10, itemCount: 1)
        let busy = try await remover.remove([tools])
        #expect(busy.skipped.first?.reason == .running(name: "server"))
    }

    @Test("Uninstalling refuses while a copy of the app is running, found by path")
    func uninstall() async throws {
        let box = try Sandbox()
        let exe = box.home.appendingPathComponent("Applications/Tool.app/Contents/MacOS/tool")
        let process = try runSleep(at: exe)
        defer { process.terminate() }
        let app = InstalledApp(url: box.home.appendingPathComponent("Applications/Tool.app"), name: "Tool",
                               bundleID: "com.example.tool", version: "1", source: .developer, lastUsed: nil)
        let uninstaller = Uninstaller(store: try box.store(), home: box.home, appFolders: [box.home.appendingPathComponent("Applications")])
        await #expect(throws: UninstallError.appIsRunning("Tool")) {
            _ = try await uninstaller.remove(app: app, leftovers: [], runningBundleIDs: [])
        }
    }

    @Test("Apps in the Restore Center can't be launched, and come back with their name")
    func heldApps() async throws {
        let box = try Sandbox()
        let app = try box.folder("Applications/Tool.app/Contents")
        try Data("x".utf8).write(to: app.appendingPathComponent("Info.plist"))
        let store = try box.store()
        let (record, _) = try await store.quarantine(
            [PlannedMove(url: app.deletingLastPathComponent(), ruleID: "app.x", size: 1, isDirectory: true)], module: "applications")
        let item = try #require(record?.items.first)
        #expect(item.storedPath.hasSuffix("Tool.app.held"))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("Applications/Tool.app").path))
        _ = try await store.restoreAll(in: try #require(record).id)
        #expect(box.exists("Applications/Tool.app/Contents/Info.plist"))
    }
}
