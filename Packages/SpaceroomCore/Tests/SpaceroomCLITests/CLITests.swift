// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCLI
@testable import SpaceroomCore

@Suite("spaceroom command")
struct CLITests {
    /// A fake home with one cache folder and a captured terminal.
    final class Harness: @unchecked Sendable {
        let base: URL
        let home: URL
        let store: URL
        var output = ""
        var errors = ""
        var answers: [String] = []
        var appRunning = false
        var interactive = true

        init() throws {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("spaceroom-cli-\(UUID().uuidString)")
            home = base.appendingPathComponent("home")
            store = base.appendingPathComponent("store")
            let cache = home.appendingPathComponent("Library/Caches/com.example.app/blob")
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: 50_000).write(to: cache)
        }

        deinit { try? FileManager.default.removeItem(at: base) }

        var cacheExists: Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.example.app").path) }

        func run(_ arguments: String) async -> CLI.ExitCode {
            let rule = Rule(id: "system.user-caches", module: .cleanup, group: "caches", title: "User app caches",
                            whySafe: "Rebuilt.", paths: ["~/Library/Caches/*"], defaultSelected: true)
            let env = CLI.Environment(
                home: home, storeDirectory: store, catalog: { try RuleCatalog(rules: [rule]) },
                runningBundleIDs: { [] }, runningAppNames: { [] }, isAppRunning: { self.appRunning },
                isInteractive: interactive, readLine: { self.answers.isEmpty ? nil : self.answers.removeFirst() },
                write: { self.output += $0 }, writeError: { self.errors += $0 }, retentionDays: { 7 })
            return await CLI(environment: env).run(arguments.split(separator: " ").map(String.init))
        }
    }

    @Test("scan reports and changes nothing")
    func scan() async throws {
        let h = try Harness()
        #expect(await h.run("scan cleanup") == .ok)
        #expect(h.output.contains("User app caches"))
        #expect(h.cacheExists)
        h.output = ""
        #expect(await h.run("scan --json") == .ok)
        let json = try JSONSerialization.jsonObject(with: Data(h.output.utf8)) as? [String: Any]
        #expect((json?["selectedBytes"] as? Int ?? 0) > 0)
    }

    @Test("clean asks first, and 'no' or no answer changes nothing")
    func confirm() async throws {
        let h = try Harness()
        h.answers = ["n"]
        #expect(await h.run("clean") == .refused)
        #expect(h.cacheExists)
        h.interactive = false
        #expect(await h.run("clean") == .refused)
        #expect(h.errors.contains("--yes"))
        #expect(h.cacheExists)
    }

    @Test("--dry-run never moves anything, even with --yes")
    func dryRun() async throws {
        let h = try Harness()
        #expect(await h.run("clean --dry-run --yes") == .ok)
        #expect(h.output.contains("Dry run"))
        #expect(h.cacheExists)
    }

    @Test("clean moves into the Restore Center; restore puts it back; history lists it")
    func cleanAndRestore() async throws {
        let h = try Harness()
        h.answers = ["y"]
        #expect(await h.run("clean cleanup") == .ok)
        #expect(!h.cacheExists)
        let id = try #require(h.output.components(separatedBy: "spaceroom restore ").last?.prefix(8))

        h.output = ""
        #expect(await h.run("history") == .ok)
        #expect(h.output.contains(String(id)) && h.output.contains("restorable"))

        h.output = ""
        #expect(await h.run("restore \(id)") == .ok)
        #expect(h.cacheExists)
    }

    @Test("Refuses to write while the app is open")
    func appOpen() async throws {
        let h = try Harness()
        h.appRunning = true
        #expect(await h.run("clean --yes") == .refused)
        #expect(h.cacheExists)
        #expect(await h.run("restore abcdef12") == .refused)
        // Reading is fine.
        #expect(await h.run("scan") == .ok)
        #expect(await h.run("clean --dry-run") == .ok)
    }

    @Test("Usage errors")
    func usage() async throws {
        let h = try Harness()
        #expect(await h.run("frobnicate") == .usage)
        #expect(await h.run("scan everything") == .usage)
        #expect(await h.run("clean --force") == .usage)
        #expect(await h.run("restore abc") == .usage)
        #expect(await h.run("help") == .ok)
    }
}
