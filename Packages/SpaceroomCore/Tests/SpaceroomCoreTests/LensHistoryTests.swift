// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Space Lens history")
struct LensHistoryTests {
    private let mb: Int64 = 1_000_000

    private func tree(dev: Int64, photos: Int64, extra: DiskNode? = nil) -> DiskNode {
        let app = DiskNode(name: "app", path: "/h/dev/app", kind: .folder, size: dev - 5 * mb, itemCount: 10)
        let tiny = DiskNode(name: "tiny", path: "/h/dev/tiny", kind: .folder, size: 5 * mb, itemCount: 2)
        let devNode = DiskNode(name: "dev", path: "/h/dev", kind: .folder, size: dev, itemCount: 13, children: [app, tiny])
        let photosNode = DiskNode(name: "Pictures", path: "/h/Pictures", kind: .folder, size: photos, itemCount: 5)
        var children = [devNode, photosNode]
        if let extra { children.append(extra) }
        return DiskNode(name: "h", path: "/h", kind: .folder, size: children.reduce(0) { $0 + $1.size },
                        itemCount: 30, children: children)
    }

    @Test("Snapshots keep folders above the minimum, a few levels deep")
    func snapshot() {
        let snap = LensSnapshot.make(from: tree(dev: 500 * mb, photos: 200 * mb))
        #expect(snap.sizes[""] == 700 * mb)
        #expect(snap.sizes["dev"] == 500 * mb)
        #expect(snap.sizes["dev/app"] == 495 * mb)
        #expect(snap.sizes["dev/tiny"] == nil)
        #expect(snap.total == 700 * mb)
    }

    @Test("Changes and new folders compared with an older scan")
    func changes() {
        let before = LensSnapshot.make(from: tree(dev: 500 * mb, photos: 200 * mb))
        let downloads = DiskNode(name: "Downloads", path: "/h/Downloads", kind: .folder, size: 300 * mb, itemCount: 1)
        let now = tree(dev: 900 * mb, photos: 150 * mb, extra: downloads)
        #expect(before.change(of: now, root: "/h") == 650 * mb)
        #expect(before.change(of: now.children[0], root: "/h") == 400 * mb)
        #expect(before.change(of: now.children[1], root: "/h") == -50 * mb)
        #expect(before.change(of: downloads, root: "/h") == nil)
        #expect(before.isNew(downloads, root: "/h"))
        #expect(!before.isNew(now.children[0], root: "/h"))
        let deep = DiskNode(name: "x", path: "/h/a/b/c/d", kind: .folder, size: 50 * mb, itemCount: 1)
        #expect(!before.isNew(deep, root: "/h"))
    }

    @Test("History keeps the newest scans, merges scans within an hour, and survives a bad file")
    func store() throws {
        let box = try Sandbox()
        let history = LensHistory(directory: box.support.appendingPathComponent("SpaceLens"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<35 {
            let snap = LensSnapshot(date: start.addingTimeInterval(Double(day) * 86_400), total: Int64(day), sizes: [:], depth: 3)
            try history.record(snap, root: "/h")
        }
        #expect(history.load(root: "/h").count == LensHistory.kept)
        #expect(history.load(root: "/h").last?.total == 34)

        let soon = LensSnapshot(date: start.addingTimeInterval(34 * 86_400 + 600), total: 99, sizes: [:], depth: 3)
        try history.record(soon, root: "/h")
        #expect(history.load(root: "/h").last?.total == 99)
        #expect(history.load(root: "/h").count == LensHistory.kept)
        #expect(history.baseline(root: "/h", before: soon.date)?.total == 33)
        #expect(history.load(root: "/other").isEmpty)

        try Data("not json".utf8).write(to: history.directory.appendingPathComponent(LensHistory.fileName(for: "/h")))
        #expect(history.load(root: "/h").isEmpty)
    }
}
