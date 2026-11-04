// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import SpaceroomCore

/// A throwaway fake home folder. Deleted when the value is released.
final class Sandbox {
    let home: URL
    let support: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("spaceroom-tests-\(UUID().uuidString)", isDirectory: true)
        home = base.appendingPathComponent("home", isDirectory: true)
        support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    /// Creates a file with `bytes` of content, and optionally backdates it.
    @discardableResult
    func file(_ relative: String, bytes: Int = 4096, modified: Date? = nil) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        if let modified { try backdate(url, to: modified) }
        return url
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func backdate(_ url: URL, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(relative).path)
    }

    func context(running: Set<String> = [], now: Date = .now) -> ScanContext {
        ScanContext(home: home, runningBundleIDs: running, now: now)
    }

    func store() throws -> RestoreStore { try RestoreStore(directory: support) }
}

extension Rule {
    static func test(
        _ id: String = "test.rule",
        paths: [String] = ["~/Library/Caches/*"],
        exclude: [String] = [],
        minAgeDays: Int = 0,
        skipIfRunning: [String] = [],
        skipIfOwnerRunning: Bool = false,
        module: CleanModule = .cleanup
    ) -> Rule {
        Rule(id: id, module: module, group: "test", title: "Test rule", whySafe: "Test data.",
             paths: paths, exclude: exclude, minAgeDays: minAgeDays, skipIfRunning: skipIfRunning,
             skipIfOwnerRunning: skipIfOwnerRunning)
    }
}
