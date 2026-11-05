// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// MARK: - Commands

/// One tool invocation. Tasks never go through a shell: a fixed executable plus fixed arguments.
public struct Command: Sendable, Hashable {
    public let tool: String
    public let arguments: [String]
    public let timeout: TimeInterval

    public init(_ tool: String, _ arguments: [String] = [], timeout: TimeInterval = 60) {
        self.tool = tool
        self.arguments = arguments
        self.timeout = timeout
    }
}

public struct CommandResult: Sendable, Hashable {
    public let status: Int32
    public let output: String
    public let timedOut: Bool
}

/// Runs commands. Injected so the task logic is testable without touching the system.
public struct CommandRunner: Sendable {
    public let run: @Sendable (Command) -> CommandResult?

    public init(run: @escaping @Sendable (Command) -> CommandResult?) {
        self.run = run
    }

    /// Real processes: output is read while the tool runs (so large output can't block it),
    /// and the tool is stopped when its timeout passes.
    public static let system = CommandRunner { command in
        guard FileManager.default.isExecutableFile(atPath: command.tool) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.tool)
        process.arguments = command.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collected = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData) }
        do { try process.run() } catch { return nil }
        let deadline = Date.now.addingTimeInterval(command.timeout)
        while process.isRunning, Date.now < deadline { usleep(20_000) }
        let timedOut = process.isRunning
        if timedOut { process.terminate(); process.waitUntilExit() }
        pipe.fileHandleForReading.readabilityHandler = nil
        collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return CommandResult(status: timedOut ? -1 : process.terminationStatus, output: collected.text, timedOut: timedOut)
    }
}

/// Thread-safe byte accumulator for a pipe's readability handler.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); data.append(chunk); lock.unlock()
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Tasks

public struct MaintenanceTask: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    /// What it does, in plain words.
    public let summary: String
    /// When it's worth running.
    public let helpsWhen: String
    public let symbol: String
    public let commands: [Command]
    /// Needs root; runs once Spaceroom's privileged helper exists (PRD §8.4).
    public let requiresAdmin: Bool
    /// Apps that must be closed first (bundle IDs).
    public let requiresQuit: [String]
    /// Shown after a successful run, e.g. "Restart apps to see the change".
    public let afterNote: String?
    public let estimate: LocalizedDuration

    public enum LocalizedDuration: Sendable, Hashable {
        case seconds, minute, minutes
    }
}

public enum MaintenanceCatalog {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public static let all: [MaintenanceTask] = [
        MaintenanceTask(
            id: "quicklook", title: "Refresh Quick Look previews",
            summary: "Resets Quick Look's preview plug-ins and thumbnail cache.",
            helpsWhen: "Previews or Finder thumbnails are blank, wrong or slow.",
            symbol: "eye", commands: [Command("/usr/bin/qlmanage", ["-r"]), Command("/usr/bin/qlmanage", ["-r", "cache"])],
            requiresAdmin: false, requiresQuit: [], afterNote: nil, estimate: .seconds),
        MaintenanceTask(
            id: "launchservices", title: "Rebuild the “Open With” list",
            summary: "Re-registers your apps with Launch Services.",
            helpsWhen: "“Open With” shows duplicates or old apps, or files open in the wrong app.",
            symbol: "arrow.up.forward.app",
            commands: [Command(lsregister, ["-r", "-domain", "local", "-domain", "system", "-domain", "user"], timeout: 300)],
            requiresAdmin: false, requiresQuit: [], afterNote: nil, estimate: .minute),
        MaintenanceTask(
            id: "fonts", title: "Clear your font caches",
            summary: "Removes your user font caches; macOS rebuilds them.",
            helpsWhen: "Text renders oddly or fonts show as missing.",
            symbol: "textformat", commands: [Command("/usr/bin/atsutil", ["databases", "-removeUser"])],
            requiresAdmin: false, requiresQuit: [], afterNote: "Restart your apps (or log out) to finish.", estimate: .seconds),
        MaintenanceTask(
            id: "verifydisk", title: "Check the startup disk",
            summary: "Verifies the startup disk's file system without changing anything.",
            helpsWhen: "Your Mac crashes, files misbehave, or before a big update.",
            symbol: "internaldrive", commands: [Command("/usr/sbin/diskutil", ["verifyVolume", "/"], timeout: 900)],
            requiresAdmin: false, requiresQuit: [], afterNote: nil, estimate: .minute),
        MaintenanceTask(
            id: "dns", title: "Flush the DNS cache",
            summary: "Forgets cached website addresses.",
            helpsWhen: "A website won't load after it moved, or after changing networks.",
            symbol: "network", commands: [Command("/usr/bin/dscacheutil", ["-flushcache"]), Command("/usr/bin/killall", ["-HUP", "mDNSResponder"])],
            requiresAdmin: true, requiresQuit: [], afterNote: nil, estimate: .seconds),
        MaintenanceTask(
            id: "spotlight", title: "Rebuild the Spotlight index",
            summary: "Erases and rebuilds the search index of the startup disk.",
            helpsWhen: "Spotlight can't find files you know are there.",
            symbol: "magnifyingglass", commands: [Command("/usr/bin/mdutil", ["-E", "/"])],
            requiresAdmin: true, requiresQuit: [], afterNote: "Indexing continues in the background for a while.", estimate: .minutes),
        MaintenanceTask(
            id: "purge", title: "Free up memory",
            summary: "Clears inactive memory macOS is holding on to.",
            helpsWhen: "Rarely needed: macOS manages memory well. Try it only if apps stall under memory pressure.",
            symbol: "memorychip", commands: [Command("/usr/sbin/purge")],
            requiresAdmin: true, requiresQuit: [], afterNote: "The effect is temporary.", estimate: .seconds),
    ]
}

// MARK: - Running

public enum MaintenanceOutcome: Sendable, Hashable {
    case done(note: String?)
    case skipped(MaintenanceSkip)
    case failed(String)
}

public enum MaintenanceSkip: Sendable, Hashable {
    /// Root rights needed (the privileged helper isn't installed).
    case needsAdmin
    /// An app has to be closed first.
    case appRunning(String)
    /// The tool doesn't exist on this macOS version.
    case unavailable
}

public struct MaintenanceRunner: Sendable {
    public let runner: CommandRunner

    public init(runner: CommandRunner = .system) {
        self.runner = runner
    }

    /// Runs a task's commands in order; stops at the first failure. Never runs admin tasks.
    public func run(_ task: MaintenanceTask, runningBundleIDs: Set<String> = []) -> MaintenanceOutcome {
        if task.requiresAdmin { return .skipped(.needsAdmin) }
        if let app = task.requiresQuit.first(where: runningBundleIDs.contains) { return .skipped(.appRunning(app)) }
        for command in task.commands {
            guard let result = runner.run(command) else { return .skipped(.unavailable) }
            if result.timedOut { return .failed("Stopped after \(Int(command.timeout)) seconds") }
            if result.status != 0 { return .failed(Self.lastLine(of: result.output) ?? "Exit code \(result.status)") }
        }
        return .done(note: task.afterNote)
    }

    static func lastLine(of output: String) -> String? {
        output.split(whereSeparator: \.isNewline).last.map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
