// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os
import Testing
@testable import SpaceroomCore

extension Sandbox {
    @discardableResult
    func plist(_ relative: String, _ dict: [String: Any]) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
        return url
    }
}

@Suite("Startup & Background: parsing")
struct LaunchItemParsingTests {
    @Test func readsTheKeysThatMatter() throws {
        let box = try Sandbox()
        try box.plist("Library/LaunchAgents/com.example.agent.plist", [
            "Label": "com.example.agent",
            "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/helper", "--quiet"],
            "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false],
            "AssociatedBundleIdentifiers": "com.example.app",
        ])
        try box.plist("Library/LaunchAgents/com.vendor.off.plist", [:])
        let items = LaunchItemScanner.scan([(box.home.appendingPathComponent("Library/LaunchAgents"), .user)])
        #expect(items.count == 2)
        let agent = try #require(items.first { $0.label == "com.example.agent" })
        #expect(agent.program == "/Applications/Example.app/Contents/MacOS/helper")
        #expect(agent.runsAtLoad && agent.keepsAlive)
        #expect(agent.associatedBundleIDs == ["com.example.app"])
        #expect(agent.containingApp == "/Applications/Example.app")
        #expect(agent.isRemovableByUser)
        let empty = try #require(items.first { $0.label == "com.vendor.off" })
        #expect(empty.isEmpty)
    }

    @Test func parsesLaunchctlList() {
        let output = "PID\tStatus\tLabel\n-\t0\tcom.apple.SafariHistoryServiceAgent\n453\t0\tcom.example.agent\n"
        #expect(Launchctl.parseList(output) == ["com.apple.SafariHistoryServiceAgent", "com.example.agent"])
    }

    @Test func parsesSecurityToolOutput() {
        #expect(SecurityPosture.parseSIP("System Integrity Protection status: enabled.") == true)
        #expect(SecurityPosture.parseGatekeeper("assessments enabled") == true)
        #expect(SecurityPosture.parseFileVault("FileVault is Off.") == false)
        #expect(SecurityPosture.parseFirewall("Firewall is disabled. (State = 0)") == false)
        #expect(SecurityPosture.parseFirewall("Firewall is enabled. (State = 1)") == true)
    }
}

@Suite("Startup & Background: audit")
struct LaunchAuditTests {
    let home = URL(fileURLWithPath: "/Users/test")

    func item(program: String?, arguments: [String] = [], associated: [String] = [], empty: Bool = false) -> LaunchItem {
        LaunchItem(url: URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/x.plist"), scope: .user, label: "x",
                   program: program, arguments: arguments.isEmpty ? program.map { [$0] } ?? [] : arguments,
                   runsAtLoad: true, keepsAlive: false, associatedBundleIDs: associated, isEmpty: empty)
    }

    @Test func orphanOfADeletedApp() {
        // Like OpenUsage.plist pointing at /Applications/OpenUsage.app after the app was removed.
        let findings = LaunchAuditor.findings(for: item(program: "/Applications/OpenUsage.app/Contents/MacOS/openusage"),
                                              home: home, exists: { _ in false })
        #expect(findings == [.programMissing])
    }

    @Test func helperWhoseAppIsGone() {
        // Like us.zoom.ZoomDaemon: helper still installed, its app (us.zoom.xos) removed.
        let findings = LaunchAuditor.findings(for: item(program: "/Library/PrivilegedHelperTools/us.zoom.ZoomDaemon",
                                                        associated: ["us.zoom.xos"]),
                                              home: home, exists: { _ in true }, isInstalled: { _ in false },
                                              signature: .developer(team: "BJ4HAAB9B3"))
        #expect(findings == [.appRemoved("us.zoom.xos")])
    }

    @Test("Regression: a bare program name is resolved by launchd, not missing")
    func bareProgramNameIsNotMissing() {
        // Xcode's xcbackgrounddownloader agent runs "xcodebuild" by name.
        #expect(LaunchAuditor.findings(for: item(program: "xcodebuild"), home: home, exists: { _ in false }).isEmpty)
    }

    @Test func emptyPlistDoesNothing() {
        #expect(LaunchAuditor.findings(for: item(program: nil, empty: true), home: home) == [.emptyJob])
    }

    @Test func unsignedProgramIsAWarning() {
        let findings = LaunchAuditor.findings(for: item(program: "/usr/local/bin/tool"), home: home,
                                              exists: { _ in true }, signature: .unsigned)
        #expect(findings == [.unsigned])
        let allWarnings = findings.allSatisfy(\.isWarning)
        #expect(allWarnings)
    }

    @Test("Unusual locations", arguments: [
        ("/tmp/x", "temporary folder"), ("/private/var/folders/ab/x", "temporary folder"),
        ("/Users/test/Downloads/run", "Downloads folder"), ("/Users/test/.config/x/run", "hidden folder (.config)"),
    ])
    func unusualLocations(path: String, reason: String) {
        #expect(LaunchAuditor.unusualLocation(path, home: home) == reason)
    }

    @Test func wellKnownToolFoldersAreFine() {
        #expect(LaunchAuditor.unusualLocation("/Users/test/.local/bin/tool", home: home) == nil)
        #expect(LaunchAuditor.unusualLocation("/Applications/App.app/Contents/MacOS/x", home: home) == nil)
    }

    @Test func scriptRunFromAHiddenFolderIsFlagged() {
        let findings = LaunchAuditor.findings(for: item(program: "/bin/bash",
                                                        arguments: ["/bin/bash", "/Users/test/.cache/run.sh"]),
                                              home: home, exists: { _ in true }, signature: .apple)
        #expect(findings == [.unusualLocation("hidden folder (.cache)")])
    }
}

@Suite("Startup & Background: signatures and removal")
struct LaunchSignatureAndRemovalTests {
    @Test func appleAndUnsignedPrograms() throws {
        #expect(CodeSignature.status(of: "/bin/ls") == .apple)
        let box = try Sandbox()
        let script = try box.file("tool.sh", bytes: 10)
        #expect(CodeSignature.status(of: script.path) == .unsigned)
    }

    @Test func removesOnlyTheUsersOwnAgentsAndStopsThem() async throws {
        let box = try Sandbox()
        let agent = try box.plist("Library/LaunchAgents/com.example.agent.plist", ["Label": "com.example.agent", "Program": "/x"])
        let user = try #require(LaunchItemScanner.parse(agent, scope: .user))
        let system = LaunchItem(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.daemon.plist"), scope: .system,
                                label: "com.example.daemon", program: "/x", arguments: [], runsAtLoad: true,
                                keepsAlive: true, associatedBundleIDs: [], isEmpty: false)
        let stopped = OSAllocatedUnfairLock<[String]>(initialState: [])
        let remover = LaunchItemRemover(store: try box.store(), home: box.home) { label in
            stopped.withLock { $0.append(label) }
        }

        let outcome = try await remover.remove([user, system])
        let op = try #require(outcome.operation)
        #expect(op.module == "startup")
        #expect(op.items.map(\.name) == ["com.example.agent.plist"])
        #expect(outcome.skipped.map(\.path) == ["/Library/LaunchDaemons/com.example.daemon.plist"])
        #expect(stopped.withLock { $0 } == ["com.example.agent"])
        #expect(!box.exists("Library/LaunchAgents/com.example.agent.plist"))

        _ = try await remover.store.restoreAll(in: op.id)
        #expect(box.exists("Library/LaunchAgents/com.example.agent.plist"))
    }
}
