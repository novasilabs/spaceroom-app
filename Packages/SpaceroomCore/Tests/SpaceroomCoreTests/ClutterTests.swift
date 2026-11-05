// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("My Clutter")
struct ClutterTests {
    func config(_ box: Sandbox, large: Int64 = 300_000) -> ClutterScanConfig {
        ClutterScanConfig(home: box.home, largeFileThreshold: large, duplicateMinimumSize: 50_000)
    }

    @Test func findsLargeFilesAndInstallersButSkipsAppDataAndBuildFolders() async throws {
        let box = try Sandbox()
        try box.file("Movies/holiday.mov", bytes: 600_000)
        try box.file("Downloads/Setup.dmg", bytes: 10_000)            // installer, small
        try box.file("Downloads/tool.pkg", bytes: 400_000)            // installer, large
        try box.file("Documents/notes.txt", bytes: 2_000)             // small, ignored
        try box.file("Library/Caches/big.bin", bytes: 900_000)        // app data
        try box.file("dev/app/node_modules/huge.bin", bytes: 900_000) // dependency
        try box.file(".hidden/secret.bin", bytes: 900_000)            // hidden
        try box.file("Pictures/Photos Library.photoslibrary/db.bin", bytes: 900_000) // package

        let report = await ClutterScanner(config: config(box)).scan()
        #expect(report.largeFiles.map(\.name) == ["holiday.mov", "tool.pkg"])
        #expect(Set(report.installers.map(\.name)) == ["Setup.dmg", "tool.pkg"])
        #expect(report.largeFiles.first?.kind == .video)
    }

    @Test func confirmsDuplicatesByContent() async throws {
        let box = try Sandbox()
        let content = Data((0..<200_000).map { UInt8($0 % 251) })
        try FileManager.default.createDirectory(at: box.home.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: box.home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try content.write(to: box.home.appendingPathComponent("Documents/report.pdf"))
        try content.write(to: box.home.appendingPathComponent("Downloads/report (1).pdf"))
        var different = content
        different[150_000] ^= 0xFF // same size, same head and tail, different middle
        try different.write(to: box.home.appendingPathComponent("Documents/other.pdf"))

        let report = await ClutterScanner(config: config(box)).scan()
        #expect(report.duplicateCandidates.count == 3)
        let groups = DuplicateFinder.groups(from: report.duplicateCandidates)
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(Set(group.files.map(\.name)) == ["report.pdf", "report (1).pdf"])
        #expect(group.keeper.name == "report.pdf") // keeps the copy outside Downloads
        #expect(group.extras.map(\.name) == ["report (1).pdf"])
        #expect(group.wasted == group.size)
    }

    @Test func keepsTheOriginalNameOverABrowserCopy() {
        let base = URL(fileURLWithPath: "/Users/x/Downloads")
        let original = ClutterFile(url: base.appendingPathComponent("tool.dmg"), size: 10, modified: .now)
        let copy = ClutterFile(url: base.appendingPathComponent("tool (1).dmg"), size: 10, modified: .now.addingTimeInterval(-60))
        #expect(DuplicateFinder.keeper(of: [copy, original]).name == "tool.dmg")
        #expect(DuplicateFinder.looksLikeCopy("Report copy 2.pdf"))
        #expect(!DuplicateFinder.looksLikeCopy("Mix (Live).mp3"))
    }

    @Test func hardLinksAreNotDuplicates() async throws {
        let box = try Sandbox()
        let original = try box.file("Documents/video.mov", bytes: 200_000)
        try FileManager.default.linkItem(at: original, to: box.home.appendingPathComponent("Documents/link.mov"))
        let report = await ClutterScanner(config: config(box)).scan()
        #expect(DuplicateFinder.groups(from: report.duplicateCandidates).isEmpty)
    }

    @Test func removesOnlyLooseFilesInHomeAndRestores() async throws {
        let box = try Sandbox()
        let video = try box.file("Movies/old.mov", bytes: 600_000)
        let appData = try box.file("Library/Application Support/App/data.bin", bytes: 600_000)
        let folder = try box.folder("Documents/Project")
        let remover = ClutterRemover(store: try box.store(), home: box.home)

        let outcome = try await remover.remove([
            ClutterFile(url: video, size: 600_000, modified: .now),
            ClutterFile(url: appData, size: 600_000, modified: .now),
            ClutterFile(url: folder, size: 0, modified: .now),
        ])
        let op = try #require(outcome.operation)
        #expect(op.module == "clutter")
        #expect(op.items.map(\.name) == ["old.mov"])
        #expect(outcome.skipped.count == 2)
        #expect(box.exists("Library/Application Support/App/data.bin"))
        #expect(box.exists("Documents/Project"))

        _ = try await remover.store.restoreAll(in: op.id)
        #expect(box.exists("Movies/old.mov"))
    }

    @Test("Kinds by extension", arguments: [
        ("clip.MOV", ClutterKind.video), ("song.flac", .audio), ("shot.HEIC", .image), ("backup.tar.gz", .archive),
        ("Xcode.xip", .installer), ("disk.dmg", .diskImage), ("deck.key", .document), ("blob", .other),
    ])
    func kinds(name: String, kind: ClutterKind) {
        #expect(ClutterKind(fileName: name) == kind)
    }
}
