// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Project build folders")
struct ProjectArtifactsTests {
    private static let old = Date.now.addingTimeInterval(-90 * 86_400)

    private func nodeRule(minAgeDays: Int = 30) -> Rule {
        Rule(id: "dev.projects.node-modules", module: .devCleanup, group: "projects", title: "node_modules",
             whySafe: "Reinstallable.", paths: ["~/development", "~/Documents"], minAgeDays: minAgeDays,
             projectArtifact: ProjectArtifactSpec(folders: ["node_modules"], markers: ["package.json"]))
    }

    /// Creates a project and backdates every file and folder in it.
    @discardableResult
    private func project(_ box: Sandbox, _ path: String, marker: String = "package.json",
                         artifact: String = "node_modules", modified: Date? = old) throws -> URL {
        try box.file("\(path)/\(marker)", bytes: 100)
        try box.file("\(path)/src/index.js", bytes: 100)
        try box.file("\(path)/\(artifact)/lib/a.js", bytes: 20_000)
        let url = box.home.appendingPathComponent(path)
        if let modified { try backdateTree(url, to: modified) }
        return url
    }

    private func backdateTree(_ url: URL, to date: Date) throws {
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let child as URL in enumerator { try fm.setAttributes([.modificationDate: date], ofItemAtPath: child.path) }
        }
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test("Finds build folders next to a marker, labels them with the project, and skips the rest")
    func finds() async throws {
        let box = try Sandbox()
        try project(box, "development/shop")
        try project(box, "development/monorepo/packages/web")
        try project(box, "Documents/GitHub/notes")
        try box.file("development/not-a-project/node_modules/x.js")          // no package.json
        try box.file("development/shop/node_modules/dep/node_modules/y.js")  // nested: part of the outer one
        let report = await Scanner().scan([nodeRule()], context: box.context())
        let items = report.results[0].items

        #expect(Set(items.map { String($0.url.path.split(separator: "/home/", maxSplits: 1).last ?? "") }) == [
            "development/shop/node_modules", "development/monorepo/packages/web/node_modules",
            "Documents/GitHub/notes/node_modules",
        ])
        #expect(items.allSatisfy { $0.isCleanable })
        #expect(items.contains { $0.displayName == "shop › node_modules" })
        #expect(items.allSatisfy { $0.root == $0.url.deletingLastPathComponent() })
    }

    @Test("Projects changed recently are left alone")
    func recent() async throws {
        let box = try Sandbox()
        try project(box, "development/active", modified: nil)
        try project(box, "development/idle")
        let items = await Scanner().scan([nodeRule()], context: box.context()).results[0].items
        let active = try #require(items.first { $0.url.path.contains("/active/") })
        let idle = try #require(items.first { $0.url.path.contains("/idle/") })
        #expect(active.skipReason == .tooRecent(minAgeDays: 30))
        #expect(idle.isCleanable)
    }

    @Test("Installing packages doesn't make a project look active")
    func artifactChangesDontCount() async throws {
        let box = try Sandbox()
        let url = try project(box, "development/idle")
        try Data("new".utf8).write(to: url.appendingPathComponent("node_modules/lib/b.js"))
        let items = await Scanner().scan([nodeRule()], context: box.context()).results[0].items
        #expect(items.first?.isCleanable == true)
    }

    @Test("Symlinked folders and app bundles aren't searched")
    func noSymlinks() async throws {
        let box = try Sandbox()
        let outside = try project(box, "elsewhere/app")
        try box.folder("development")
        try FileManager.default.createSymbolicLink(at: box.home.appendingPathComponent("development/link"),
                                                   withDestinationURL: outside)
        try project(box, "development/Tool.app/Contents/app")
        let items = await Scanner().scan([nodeRule()], context: box.context()).results[0].items
        #expect(items.isEmpty)
    }

    @Test("Folders committed to Git are never offered", .enabled(if: GitProbe.shared.executable != nil))
    func committed() async throws {
        let box = try Sandbox()
        let committed = try project(box, "development/vendored")
        let ignored = try project(box, "development/clean")
        let git = try #require(GitProbe.shared.executable)
        for (repo, add) in [(committed, ["add", "."]), (ignored, ["add", "package.json", "src"])] {
            _ = GitProbe.run(git, ["-C", repo.path, "init", "-q"])
            _ = GitProbe.run(git, ["-C", repo.path] + add)
            _ = GitProbe.run(git, ["-C", repo.path, "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                                   "commit", "-q", "-m", "init"])
            try backdateTree(repo, to: Self.old)
        }
        let items = await Scanner().scan([nodeRule()], context: box.context()).results[0].items
        #expect(items.first { $0.url.path.contains("/vendored/") }?.skipReason == .trackedByGit(verified: true))
        #expect(items.first { $0.url.path.contains("/clean/") }?.isCleanable == true)
    }

    @Test("Without Git, folders inside a repository are skipped rather than guessed")
    func noGit() throws {
        let probe = GitProbe(executable: nil)
        #expect(probe.isTracked(URL(fileURLWithPath: "/tmp/x/node_modules"), in: URL(fileURLWithPath: "/tmp/x")) == nil)
    }

    @Test("Clean then restore, end to end through the Restore Center")
    func cleanAndRestore() async throws {
        let box = try Sandbox()
        try project(box, "development/shop")
        let rule = nodeRule()
        let context = box.context()
        let store = try box.store()
        let items = await Scanner().scan([rule], context: context).results[0].cleanableItems
        let outcome = try await CleanupEngine(store: store).clean(items, rules: [rule], module: .devCleanup, context: context)
        let op = try #require(outcome.operation)
        #expect(outcome.skipped.isEmpty)
        #expect(!box.exists("development/shop/node_modules"))
        #expect(box.exists("development/shop/package.json"))
        _ = try await store.restoreAll(in: op.id)
        #expect(box.exists("development/shop/node_modules/lib/a.js"))
    }

    @Test("Project rules: search folders must be plain home folders outside Library")
    func validation() {
        func rule(_ paths: [String], folders: [String] = ["node_modules"]) -> Rule {
            Rule(id: "p", module: .devCleanup, group: "projects", title: "t", whySafe: "w", paths: paths,
                 projectArtifact: ProjectArtifactSpec(folders: folders, markers: ["package.json"]))
        }
        func valid(_ rule: Rule) -> Bool { (try? RuleCatalog.validate([rule])) != nil }
        #expect(valid(rule(["~/Documents", "~/development/work"])))
        #expect(!valid(rule(["~/Library/Caches"])))
        #expect(!valid(rule(["~/dev/*"])))
        #expect(!valid(rule(["/opt/code"])))
        #expect(!valid(rule(["~/a/b/c"])))
        #expect(!valid(rule(["~/dev"], folders: ["../x"])))
        #expect(!valid(rule(["~/dev"], folders: ["*"])))
    }

    @Test("The bundled project rules load and never run unattended")
    func bundled() throws {
        let rules = try RuleCatalog.bundled().rules.filter { $0.projectArtifact != nil }
        #expect(rules.count == 7)
        #expect(rules.allSatisfy { !$0.smartCare && $0.module == .devCleanup && $0.minAgeDays >= 30 })
    }
}

@Suite("Project build folders: running programs")
struct ProjectRunningTests {
    @Test("A tool running from target/release keeps its folder, at scan and at clean time")
    func runningTool() async throws {
        let box = try Sandbox()
        try box.file("development/tool/Cargo.toml", bytes: 10)
        let exe = box.home.appendingPathComponent("development/tool/target/release/tool")
        let old = Date.now.addingTimeInterval(-90 * 86_400)
        let process = try TestProgram.run(at: exe)
        defer { process.terminate() }
        for path in ["development/tool/Cargo.toml", "development/tool"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: box.home.appendingPathComponent(path).path)
        }

        let rule = Rule(id: "dev.projects.rust-target", module: .devCleanup, group: "projects", title: "target", whySafe: "w",
                        paths: ["~/development"], minAgeDays: 30,
                        projectArtifact: ProjectArtifactSpec(folders: ["target"], markers: ["Cargo.toml"]))
        let item = try #require(await Scanner().scan([rule], context: box.context()).results[0].items.first)
        #expect(item.skipReason == .running(name: "tool"))
        // Even if the scan had missed it, the clean-time check stops it.
        let forced = item.withoutSkipReason()
        let plan = CleanupEngine(store: try box.store()).plan([forced], rules: [rule], context: box.context())
        #expect(plan.moves.isEmpty)
    }
}

extension ScanItem {
    func withoutSkipReason() -> ScanItem {
        ScanItem(url: url, ruleID: ruleID, root: root, size: size, fileCount: fileCount, lastModified: lastModified,
                 isDirectory: isDirectory, identity: identity, skipReason: nil, label: label)
    }
}
