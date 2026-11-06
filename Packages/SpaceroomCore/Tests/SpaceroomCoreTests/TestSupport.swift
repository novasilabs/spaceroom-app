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

/// A long-running test program at a chosen path. Copies of Apple's own tools (/bin/sleep) are
/// killed by macOS's launch constraints within a second when run from elsewhere, so one is
/// compiled once per test run instead.
enum TestProgram {
    private static let compiled: URL? = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spaceroom-sleeper-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("sleeper.c"), binary = dir.appendingPathComponent("sleeper")
        if FileManager.default.isExecutableFile(atPath: binary.path) { return binary }
        try? Data("#include <unistd.h>\nint main(void){sleep(30);return 0;}\n".utf8).write(to: source)
        let cc = Process()
        cc.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        cc.arguments = ["-o", binary.path, source.path]
        guard (try? cc.run()) != nil else { return nil }
        cc.waitUntilExit()
        return cc.terminationStatus == 0 ? binary : nil
    }()

    static var isAvailable: Bool { compiled != nil }

    /// Starts the program at `url` and waits until it's really running there.
    static func run(at url: URL) throws -> Process {
        guard let compiled else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: compiled, to: url)
        let process = Process()
        process.executableURL = url
        try process.run()
        let deadline = Date.now.addingTimeInterval(5)
        while RunningProcesses.current().program(inside: url) == nil, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return process
    }
}
