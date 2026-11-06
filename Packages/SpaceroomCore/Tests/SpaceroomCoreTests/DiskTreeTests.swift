// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Space Lens disk tree")
struct DiskTreeTests {
    // Small thresholds so tiny test trees behave like real ones.
    func scanner(maxChildren: Int = 60, minFileSize: Int64 = 50_000) -> DiskScanner {
        DiskScanner(maxChildren: maxChildren, minFileSize: minFileSize, pruneBelow: 150_000)
    }

    @Test func sizesAddUpAndSortLargestFirst() async throws {
        let box = try Sandbox()
        try box.file("root/big/a.bin", bytes: 400_000)
        try box.file("root/big/b.bin", bytes: 200_000)
        try box.file("root/small/c.bin", bytes: 100_000)
        try box.file("root/top.bin", bytes: 300_000)

        let root = await scanner().scan(box.home.appendingPathComponent("root"))
        #expect(root.children.map(\.name) == ["big", "top.bin", "small"])
        #expect(root.size == root.children.reduce(0) { $0 + $1.size })
        let big = try #require(root.children.first)
        #expect(big.kind == .folder)
        #expect(big.size >= 600_000)
        #expect(big.children.map(\.name) == ["a.bin", "b.bin"])
        // Tiny folders keep no children (memory); `small` is only 100 kB.
        #expect(root.children.first { $0.name == "small" }?.children.isEmpty == true)
        #expect(root.itemCount >= 6) // 4 files + 2 folders
    }

    @Test func smallFilesFoldIntoOther() async throws {
        let box = try Sandbox()
        for i in 0..<5 { try box.file("root/dir/tiny\(i).txt", bytes: 1_000) }
        try box.file("root/dir/large.bin", bytes: 200_000)

        let dir = try #require(await scanner().scan(box.home.appendingPathComponent("root")).children.first)
        #expect(dir.children.count == 2)
        let other = try #require(dir.children.first { if case .other = $0.kind { true } else { false } })
        #expect(other.kind == .other(count: 5))
    }

    @Test func longTailFoldsIntoOther() async throws {
        let box = try Sandbox()
        for i in 0..<6 { try box.file("root/dir/f\(i).bin", bytes: 60_000 + i * 10_000) }

        let dir = try #require(await scanner(maxChildren: 3).scan(box.home.appendingPathComponent("root")).children.first)
        #expect(dir.children.count == 4) // 3 largest + other
        #expect(dir.children.contains { $0.kind == .other(count: 3) })
        #expect(dir.size == dir.children.reduce(0) { $0 + $1.size })
    }

    @Test func appBundlesAreSingleObjects() async throws {
        let box = try Sandbox()
        try box.file("root/Tool.app/Contents/MacOS/tool", bytes: 300_000)
        let root = await scanner().scan(box.home.appendingPathComponent("root"))
        #expect(root.children.first?.kind == .package)
    }

    @Test func unreadableFoldersAreMarkedPartial() async throws {
        let box = try Sandbox()
        try box.file("root/open/a.bin", bytes: 200_000)
        let locked = try box.folder("root/open/locked")
        try box.file("root/open/locked/secret.bin", bytes: 100_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let root = await scanner().scan(box.home.appendingPathComponent("root"))
        let open = try #require(root.children.first)
        #expect(open.isPartial)
        #expect(root.isPartial)
        #expect(open.children.contains { $0.name == "locked" && $0.isPartial })
    }

    @Test func hardLinksCountOnce() async throws {
        let box = try Sandbox()
        let original = try box.file("root/dir/original.bin", bytes: 300_000)
        try FileManager.default.linkItem(at: original, to: box.home.appendingPathComponent("root/dir/link.bin"))
        let dir = try #require(await scanner().scan(box.home.appendingPathComponent("root")).children.first)
        #expect(dir.children.filter { $0.kind == .file }.count == 1)
    }

    @Test func doesNotFollowSymlinks() async throws {
        let box = try Sandbox()
        let target = try box.file("elsewhere/huge.bin", bytes: 900_000).deletingLastPathComponent()
        try box.folder("root/dir")
        try FileManager.default.createSymbolicLink(at: box.home.appendingPathComponent("root/dir/link"),
                                                   withDestinationURL: target)
        let root = await scanner().scan(box.home.appendingPathComponent("root"))
        #expect(root.size < 100_000)
    }

    @Test func streamsProgressThenFinishes() async throws {
        let box = try Sandbox()
        for i in 0..<20 { try box.file("root/d\(i % 4)/f\(i).bin", bytes: 10_000) }
        var items = 0
        var topLevel: [String] = []
        var finished: DiskNode?
        for await event in scanner().events(for: box.home.appendingPathComponent("root")) {
            switch event {
            case .progress(let count, _): items += count
            case .topLevelFinished(let node): topLevel.append(node.name)
            case .finished(let node): finished = node
            }
        }
        #expect(items == 20)
        #expect(Set(topLevel) == ["d0", "d1", "d2", "d3"])
        #expect(try #require(finished).children.count == 4)
    }
}

/// Opt-in benchmark on the real home folder (read-only): `SPACEROOM_PERF=1 swift test --filter benchmark`.
@Suite("Space Lens benchmark")
struct DiskTreeBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPACEROOM_PERF"] != nil))
    func benchmarkHome() async {
        let clock = ContinuousClock()
        let start = clock.now
        let root = await DiskScanner().scan(FileManager.default.homeDirectoryForCurrentUser)
        let elapsed = clock.now - start
        print("BENCH home: \(root.itemCount) items, \(root.size / 1_000_000) MB, partial=\(root.isPartial), \(elapsed)")
        for child in root.children.prefix(8) { print("BENCH   \(child.name): \(child.size / 1_000_000) MB") }
    }
}

@Suite("Disk map: hard links")
struct DiskTreeHardLinkTests {
    @Test("A file hard-linked into two parallel-scanned folders counts once")
    func linkedOnce() async throws {
        let box = try Sandbox()
        let original = try box.file("store/pkg/blob.bin", bytes: 2_000_000)
        try box.folder("app/node_modules/pkg")
        try FileManager.default.linkItem(at: original, to: box.home.appendingPathComponent("app/node_modules/pkg/blob.bin"))
        let tree = await DiskScanner().scan(box.home)
        #expect(tree.size < 3_000_000)
    }
}
