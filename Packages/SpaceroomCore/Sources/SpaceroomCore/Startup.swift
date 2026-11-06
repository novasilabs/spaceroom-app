// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

// MARK: - Launch items

/// A launchd job (LaunchAgent or LaunchDaemon) or a background item bundled inside an app.
public struct LaunchItem: Sendable, Identifiable, Hashable {
    public enum Scope: String, Sendable, Hashable, CaseIterable {
        /// ~/Library/LaunchAgents: runs as you, and you may remove it.
        case user
        /// /Library/LaunchAgents: runs in every user's session; changing it needs admin rights.
        case allUsers
        /// /Library/LaunchDaemons: runs as root at boot; changing it needs admin rights.
        case system
        /// Contents/Library/LoginItems or LaunchAgents inside an app; managed in System Settings.
        case insideApp
    }

    public var id: String { url.path }
    public let url: URL
    public let scope: Scope
    public let label: String
    /// The executable it starts, if it declares one.
    public let program: String?
    public let arguments: [String]
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    /// Apps the job says it belongs to (`AssociatedBundleIdentifiers`).
    public let associatedBundleIDs: [String]
    /// The plist has no keys at all (vendors write these to switch a job off).
    public let isEmpty: Bool

    public var isRemovableByUser: Bool { scope == .user }

    /// The app bundle containing the program, e.g. "/Applications/Zoom.app".
    public var containingApp: String? {
        guard let program, let range = program.range(of: ".app/") else { return nil }
        return String(program[..<range.lowerBound]) + ".app"
    }
}

public enum LaunchItemScanner {
    public static func folders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [(URL, LaunchItem.Scope)] {
        [(home.appendingPathComponent("Library/LaunchAgents"), .user),
         (URL(fileURLWithPath: "/Library/LaunchAgents"), .allUsers),
         (URL(fileURLWithPath: "/Library/LaunchDaemons"), .system)]
    }

    public static func scan(_ folders: [(URL, LaunchItem.Scope)]) -> [LaunchItem] {
        folders.flatMap { folder, scope -> [LaunchItem] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { $0.hasSuffix(".plist") }.sorted()
                .compactMap { parse(folder.appendingPathComponent($0), scope: scope) }
        }
    }

    /// Reads a launchd plist (XML or binary). An unreadable file yields `nil`; an empty one an empty item.
    public static func parse(_ url: URL, scope: LaunchItem.Scope) -> LaunchItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let arguments = (plist["ProgramArguments"] as? [String]) ?? []
        let program = (plist["Program"] as? String) ?? arguments.first
        let keepAlive: Bool = {
            if let flag = plist["KeepAlive"] as? Bool { return flag }
            return plist["KeepAlive"] is [String: Any]
        }()
        return LaunchItem(
            url: url, scope: scope,
            label: (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent,
            program: program.flatMap { $0.isEmpty ? nil : $0 },
            arguments: arguments,
            runsAtLoad: (plist["RunAtLoad"] as? Bool) ?? false,
            keepsAlive: keepAlive,
            associatedBundleIDs: (plist["AssociatedBundleIdentifiers"] as? [String])
                ?? ((plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []),
            isEmpty: plist.isEmpty)
    }

    /// Login items and launch agents shipped inside installed apps (informational).
    public static func insideApps(_ apps: [URL]) -> [LaunchItem] {
        apps.flatMap { app -> [LaunchItem] in
            let loginItems = app.appendingPathComponent("Contents/Library/LoginItems")
            let helpers = ((try? FileManager.default.contentsOfDirectory(atPath: loginItems.path)) ?? [])
                .filter { $0.hasSuffix(".app") }.sorted()
                .map { name -> LaunchItem in
                    let url = loginItems.appendingPathComponent(name)
                    return LaunchItem(url: url, scope: .insideApp, label: (name as NSString).deletingPathExtension,
                                      program: url.path, arguments: [], runsAtLoad: false, keepsAlive: false,
                                      associatedBundleIDs: [], isEmpty: false)
                }
            let agents = scan([(app.appendingPathComponent("Contents/Library/LaunchAgents"), .insideApp)])
            return helpers + agents
        }
    }
}

// MARK: - Audit

public enum LaunchFinding: Sendable, Hashable {
    /// The program it starts doesn't exist (usually the app was deleted).
    case programMissing
    /// It belongs to an app that is no longer installed.
    case appRemoved(String)
    /// The plist is empty and does nothing.
    case emptyJob
    /// The program isn't code-signed, or its signature is broken.
    case unsigned
    /// It runs from a temporary, Downloads or hidden folder: unusual for legitimate software.
    case unusualLocation(String)

    /// Orphans and no-ops are harmless clutter; unsigned or oddly placed programs deserve a closer look.
    public var isWarning: Bool {
        switch self {
        case .unsigned, .unusualLocation: true
        case .programMissing, .appRemoved, .emptyJob: false
        }
    }
}

public enum LaunchAuditor {
    /// - Parameters:
    ///   - exists: whether a path exists (injected for tests).
    ///   - isInstalled: whether an app with this bundle ID is installed (LaunchServices in the app).
    ///   - signature: code signature of the program, if checked.
    public static func findings(for item: LaunchItem, home: URL,
                                exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                                isInstalled: (String) -> Bool = { _ in true },
                                signature: CodeSignature.Status? = nil) -> [LaunchFinding] {
        if item.isEmpty { return [.emptyJob] }
        var findings: [LaunchFinding] = []
        // A bare name ("xcodebuild") is looked up by launchd on its search path, so only absolute
        // paths can be checked for existence or signature.
        if let program = item.program, program.hasPrefix("/") {
            if !exists(program) {
                findings.append(.programMissing)
            } else if let signature, signature == .unsigned || signature == .invalid {
                findings.append(.unsigned)
            }
            if let reason = unusualLocation(program, home: home) { findings.append(.unusualLocation(reason)) }
            // Interpreters running a script from an odd place: `bash -c ~/.hidden/x.sh`, `python /tmp/x.py`.
            let interpreters: Set<String> = ["sh", "bash", "zsh", "python", "python3", "perl", "ruby", "osascript", "node"]
            if interpreters.contains((program as NSString).lastPathComponent) {
                for argument in item.arguments.dropFirst() {
                    if let reason = unusualLocation(argument, home: home) {
                        findings.append(.unusualLocation(reason))
                        break
                    }
                }
            }
        }
        if let app = item.containingApp, !exists(app), !findings.contains(.programMissing) {
            findings.append(.appRemoved((app as NSString).lastPathComponent))
        }
        if let missing = item.associatedBundleIDs.first(where: { !isInstalled($0) }), item.containingApp == nil {
            findings.append(.appRemoved(missing))
        }
        return findings
    }

    static func unusualLocation(_ path: String, home: URL) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/tmp/") || expanded.hasPrefix("/private/tmp/")
            || expanded.hasPrefix("/var/folders/") || expanded.hasPrefix("/private/var/folders/") {
            return String(localized: "temporary folder", bundle: .module)
        }
        if expanded.hasPrefix(home.appendingPathComponent("Downloads").path + "/") {
            return String(localized: "Downloads folder", bundle: .module)
        }
        // A hidden folder anywhere below home, except well-known tool folders.
        let homePath = home.path + "/"
        if expanded.hasPrefix(homePath) {
            let relative = expanded.dropFirst(homePath.count).split(separator: "/").dropLast()
            let allowed: Set<String> = [".local", ".cargo", ".nvm", ".bun", ".deno", ".volta", ".rbenv", ".pyenv", ".sdkman", ".docker", ".orbstack"]
            if let hidden = relative.first(where: { $0.hasPrefix(".") }), !allowed.contains(String(hidden)) {
                return String(localized: "hidden folder (\(String(hidden)))", bundle: .module)
            }
        }
        return nil
    }
}

// MARK: - Code signature

public enum CodeSignature {
    public enum Status: Sendable, Hashable {
        case apple
        case developer(team: String)
        case adHoc
        case unsigned
        case invalid
    }

    /// Static signature check of a program or bundle on disk (offline; doesn't run anything).
    public static func status(of path: String) -> Status {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return .unsigned }
        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
        if validity == errSecCSUnsigned { return .unsigned }
        guard validity == errSecSuccess else { return .invalid }

        var requirement: SecRequirement?
        if SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
           let requirement, SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess {
            return .apple
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return .adHoc }
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .developer(team: team)
        }
        return .adHoc
    }
}

// MARK: - Security posture

public struct SecurityPosture: Sendable, Hashable {
    public var systemIntegrityProtection: Bool?
    public var gatekeeper: Bool?
    public var fileVault: Bool?
    public var firewall: Bool?
    public var xprotectVersion: String?

    public static func current() -> SecurityPosture {
        SecurityPosture(
            systemIntegrityProtection: run("/usr/bin/csrutil", ["status"]).flatMap(parseSIP),
            gatekeeper: run("/usr/sbin/spctl", ["--status"]).flatMap(parseGatekeeper),
            fileVault: run("/usr/bin/fdesetup", ["status"]).flatMap(parseFileVault),
            firewall: run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]).flatMap(parseFirewall),
            xprotectVersion: xprotect())
    }

    static func parseSIP(_ output: String) -> Bool? {
        output.contains("status: enabled") ? true : output.contains("status: disabled") ? false : nil
    }

    static func parseGatekeeper(_ output: String) -> Bool? {
        output.contains("assessments enabled") ? true : output.contains("assessments disabled") ? false : nil
    }

    static func parseFileVault(_ output: String) -> Bool? {
        output.contains("FileVault is On") ? true : output.contains("FileVault is Off") ? false : nil
    }

    static func parseFirewall(_ output: String) -> Bool? {
        output.contains("State = 0") || output.contains("disabled") ? false
            : output.contains("State = 1") || output.contains("State = 2") || output.contains("enabled") ? true : nil
    }

    static func xprotect() -> String? {
        let plist = "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
        guard let dict = NSDictionary(contentsOfFile: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Runs a read-only status tool with a short timeout.
    static func run(_ tool: String, _ arguments: [String]) -> String? {
        CommandRunner.system.run(Command(tool, arguments, timeout: 3)).flatMap { $0.timedOut ? nil : $0.output }
    }
}

// MARK: - Loaded jobs and removal

public enum Launchctl {
    /// Labels currently loaded in this user's session (`launchctl list`).
    public static func loadedLabels() -> Set<String> {
        guard let output = SecurityPosture.run("/bin/launchctl", ["list"]) else { return [] }
        return parseList(output)
    }

    static func parseList(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").dropFirst().compactMap { line in
            let columns = line.split(separator: "\t")
            return columns.count >= 3 ? String(columns[2]) : nil
        })
    }

    /// Stops a job in this user's session. Failure is fine: it may not be loaded.
    static func bootout(label: String) {
        _ = SecurityPosture.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
    }
}

/// Removes the user's own launch agents: stops the job, then moves its plist to the Restore Center.
/// Restoring it brings the job back at the next login.
public struct LaunchItemRemover: Sendable {
    public let store: RestoreStore
    public let home: URL
    let stopJob: @Sendable (String) -> Void

    public init(store: RestoreStore, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(store: store, home: home, stopJob: { Launchctl.bootout(label: $0) })
    }

    init(store: RestoreStore, home: URL, stopJob: @escaping @Sendable (String) -> Void) {
        self.store = store
        self.home = home
        self.stopJob = stopJob
    }

    public func remove(_ items: [LaunchItem], now: Date = .now) async throws -> CleanOutcome {
        let agents = SafetyGuard.realPath(home.appendingPathComponent("Library/LaunchAgents"))
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        for item in items {
            let parent = SafetyGuard.realPath(item.url.deletingLastPathComponent())
            guard item.scope == .user, parent == agents, item.url.pathExtension == "plist",
                  FileStat.lstatInfo(item.url).map({ ($0.st_mode & S_IFMT) == S_IFREG }) == true else {
                skipped.append(SkippedItem(path: item.url.path, size: 0, reason: .protectedPath))
                continue
            }
            moves.append(PlannedMove(url: item.url, ruleID: "startup." + item.label,
                                     size: DiskUsage.size(of: item.url), isDirectory: false))
        }
        guard !moves.isEmpty else { return CleanOutcome(operation: nil, skipped: skipped) }
        let (record, failures) = try await store.quarantine(moves, module: "startup", now: now)
        // Stop only the jobs whose plist really moved: one the Restore Center refused (ignored,
        // or the ignore list can't be read) keeps running as before.
        let moved = Set(record?.items.map(\.originalPath) ?? [])
        for item in items where moved.contains(item.url.path) { stopJob(item.label) }
        return CleanOutcome(operation: record,
                            skipped: skipped + failures.map { SkippedItem(path: $0.path, size: 0, reason: $0.reason) })
    }
}
