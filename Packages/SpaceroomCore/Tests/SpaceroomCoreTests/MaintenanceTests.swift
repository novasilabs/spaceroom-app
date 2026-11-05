// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os
import Testing
@testable import SpaceroomCore

@Suite("Performance: maintenance")
struct MaintenanceTests {
    /// Records commands instead of running them.
    func fake(_ respond: @escaping @Sendable (Command) -> CommandResult?) -> (CommandRunner, OSAllocatedUnfairLock<[Command]>) {
        let log = OSAllocatedUnfairLock<[Command]>(initialState: [])
        return (CommandRunner { command in
            log.withLock { $0.append(command) }
            return respond(command)
        }, log)
    }

    func task(_ id: String) throws -> MaintenanceTask {
        try #require(MaintenanceCatalog.all.first { $0.id == id })
    }

    @Test func catalogIsWellFormedAndToolsExist() {
        let ids = MaintenanceCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for task in MaintenanceCatalog.all {
            #expect(!task.commands.isEmpty, "\(task.id) has no commands")
            for command in task.commands {
                #expect(FileManager.default.isExecutableFile(atPath: command.tool), "\(command.tool) missing")
                #expect(command.tool.hasPrefix("/"), "\(command.tool) must be an absolute path (no shell, no PATH lookup)")
            }
        }
    }

    @Test func runsEveryCommandInOrder() throws {
        let (runner, log) = fake { _ in CommandResult(status: 0, output: "", timedOut: false) }
        let outcome = MaintenanceRunner(runner: runner).run(try task("quicklook"))
        #expect(outcome == .done(note: nil))
        #expect(log.withLock { $0 }.map(\.arguments) == [["-r"], ["-r", "cache"]])
    }

    @Test func neverRunsAdminTasks() throws {
        let (runner, log) = fake { _ in CommandResult(status: 0, output: "", timedOut: false) }
        #expect(MaintenanceRunner(runner: runner).run(try task("purge")) == .skipped(.needsAdmin))
        #expect(log.withLock { $0 }.isEmpty)
    }

    @Test func stopsAtTheFirstFailureWithItsMessage() throws {
        let (runner, log) = fake { _ in CommandResult(status: 1, output: "Working…\nVolume could not be checked\n", timedOut: false) }
        let outcome = MaintenanceRunner(runner: runner).run(try task("quicklook"))
        #expect(outcome == .failed("Volume could not be checked"))
        #expect(log.withLock { $0 }.count == 1)
    }

    @Test func reportsTimeoutsAndMissingTools() throws {
        let (slow, _) = fake { _ in CommandResult(status: -1, output: "", timedOut: true) }
        #expect(MaintenanceRunner(runner: slow).run(try task("verifydisk")) == .failed("Stopped after 900 seconds"))
        let (missing, _) = fake { _ in nil }
        #expect(MaintenanceRunner(runner: missing).run(try task("fonts")) == .skipped(.unavailable))
    }

    @Test func passesTheAfterNoteOnSuccess() throws {
        let (runner, _) = fake { _ in CommandResult(status: 0, output: "", timedOut: false) }
        #expect(MaintenanceRunner(runner: runner).run(try task("fonts")) == .done(note: "Restart your apps (or log out) to finish."))
    }

    @Test func systemRunnerCapturesOutputAndExitCode() throws {
        let result = try #require(CommandRunner.system.run(Command("/bin/echo", ["hello"])))
        #expect(result.status == 0)
        #expect(result.output == "hello\n")
        let failing = try #require(CommandRunner.system.run(Command("/usr/bin/false")))
        #expect(failing.status != 0)
        let slow = try #require(CommandRunner.system.run(Command("/bin/sleep", ["5"], timeout: 0.3)))
        #expect(slow.timedOut)
    }
}
