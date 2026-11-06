// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SpaceroomCore

/// The `spaceroom` command. Same rules, safety checks and Restore Center as the app: anything
/// it cleans shows up in the app's Restore Center and can be restored from either.
public struct CLI: Sendable {
    /// Everything the commands touch from the outside, injectable for tests.
    public struct Environment: Sendable {
        public var home: URL
        public var storeDirectory: URL
        public var catalog: @Sendable () throws -> RuleCatalog
        public var runningBundleIDs: @Sendable () -> Set<String>
        public var runningAppNames: @Sendable () -> Set<String>
        /// Whether the Spaceroom app is running (two writers would clobber the Restore Center index).
        public var isAppRunning: @Sendable () -> Bool
        public var isInteractive: Bool
        public var readLine: @Sendable () -> String?
        public var write: @Sendable (String) -> Void
        public var writeError: @Sendable (String) -> Void
        public var retentionDays: @Sendable () -> Int
        public var now: @Sendable () -> Date

        public init(home: URL, storeDirectory: URL, catalog: @escaping @Sendable () throws -> RuleCatalog,
                    runningBundleIDs: @escaping @Sendable () -> Set<String>, runningAppNames: @escaping @Sendable () -> Set<String>,
                    isAppRunning: @escaping @Sendable () -> Bool, isInteractive: Bool, readLine: @escaping @Sendable () -> String?,
                    write: @escaping @Sendable (String) -> Void, writeError: @escaping @Sendable (String) -> Void,
                    retentionDays: @escaping @Sendable () -> Int, now: @escaping @Sendable () -> Date = { .now }) {
            self.home = home
            self.storeDirectory = storeDirectory
            self.catalog = catalog
            self.runningBundleIDs = runningBundleIDs
            self.runningAppNames = runningAppNames
            self.isAppRunning = isAppRunning
            self.isInteractive = isInteractive
            self.readLine = readLine
            self.write = write
            self.writeError = writeError
            self.retentionDays = retentionDays
            self.now = now
        }
    }

    public enum ExitCode: Int32, Sendable {
        case ok = 0, failure = 1, usage = 2, refused = 3
    }

    public static let version = "0.10.2"

    let env: Environment

    public init(environment: Environment) {
        env = environment
    }

    // MARK: Entry

    public func run(_ arguments: [String]) async -> ExitCode {
        var args = arguments
        let command = args.isEmpty ? "help" : args.removeFirst()
        let json = args.contains("--json")
        let flags = Set(args.filter { $0.hasPrefix("-") })
        let positional = args.filter { !$0.hasPrefix("-") }
        let known: Set<String> = ["--json", "--dry-run", "--yes", "-y", "--help", "-h"]
        if let unknown = flags.subtracting(known).first {
            env.writeError("spaceroom: unknown option \(unknown)\n")
            return .usage
        }
        if flags.contains("--help") || flags.contains("-h") { return help() }

        switch command {
        case "scan": return await scan(scope: positional.first, json: json)
        case "clean":
            return await clean(scope: positional.first, dryRun: flags.contains("--dry-run"),
                               assumeYes: flags.contains("--yes") || flags.contains("-y"), json: json)
        case "status": return await status(json: json)
        case "history": return await history(json: json)
        case "restore": return await restore(positional.first)
        case "version", "--version": env.write("spaceroom \(Self.version)\n"); return .ok
        case "help", "--help", "-h": return help()
        default:
            env.writeError("spaceroom: unknown command \(command). Run spaceroom help.\n")
            return .usage
        }
    }

    func help() -> ExitCode {
        env.write("""
        spaceroom: clean your Mac from the terminal. Uses the same engine and Restore Center as \
        the Spaceroom app.

        USAGE
          spaceroom scan    [cleanup|dev|all] [--json]   Show what can be cleaned (changes nothing)
          spaceroom clean   [cleanup|dev|all] [--dry-run] [--yes] [--json]
                                                         Move it to the Restore Center
          spaceroom status  [--json]                     Disks and the Restore Center
          spaceroom history [--json]                     Recent cleans
          spaceroom restore <operation-id>               Put a clean back
          spaceroom version

        clean uses the categories that are ticked by default in the app, skips anything in use,
        too recent or on your ignore list, and asks before moving anything (unless --yes). It
        refuses to run while the Spaceroom app is open, so the two never write the Restore
        Center at the same time.

        """)
        return .ok
    }

    // MARK: Scan

    struct RuleSummary: Codable {
        let id: String
        let module: String
        let title: String
        let cleanableBytes: Int64
        let cleanableItems: Int
        let skippedItems: Int
        let selectedByDefault: Bool
        let needsFullDiskAccess: Bool
    }

    struct ScanSummary: Codable {
        let rules: [RuleSummary]
        let cleanableBytes: Int64
        let selectedBytes: Int64
    }

    func modules(for scope: String?) -> [CleanModule]? {
        switch scope ?? "all" {
        case "all": [.cleanup, .devCleanup]
        case "cleanup": [.cleanup]
        case "dev", "devCleanup": [.devCleanup]
        default: nil
        }
    }

    func context() throws -> ScanContext {
        ScanContext(home: env.home, runningBundleIDs: env.runningBundleIDs(), runningAppNames: env.runningAppNames(),
                    now: env.now(), ignore: try IgnoreListFile.load(directory: env.storeDirectory))
    }

    func scanReports(_ modules: [CleanModule], catalog: RuleCatalog, context: ScanContext) async -> [(CleanModule, ScanReport)] {
        var reports: [(CleanModule, ScanReport)] = []
        for module in modules {
            let rules = catalog.rules(for: module).filter { !$0.requiresAdmin }
            reports.append((module, await Scanner().scan(rules, claimRules: catalog.rules, context: context)))
        }
        return reports
    }

    func scan(scope: String?, json: Bool) async -> ExitCode {
        guard let modules = modules(for: scope) else { return usage("scan [cleanup|dev|all]") }
        let catalog: RuleCatalog
        let context: ScanContext
        do {
            catalog = try env.catalog()
            context = try self.context()
        } catch {
            env.writeError("spaceroom: \(error)\n")
            return .failure
        }
        let reports = await scanReports(modules, catalog: catalog, context: context)
        let rules = reports.flatMap { module, report in
            report.results.map { result in
                RuleSummary(id: result.rule.id, module: module.rawValue, title: result.rule.localizedTitle,
                            cleanableBytes: result.cleanableSize, cleanableItems: result.cleanableItems.count,
                            skippedItems: result.items.count - result.cleanableItems.count,
                            selectedByDefault: result.rule.defaultSelected, needsFullDiskAccess: result.accessDenied)
            }
        }
        let summary = ScanSummary(rules: rules, cleanableBytes: rules.reduce(0) { $0 + $1.cleanableBytes },
                                  selectedBytes: rules.filter(\.selectedByDefault).reduce(0) { $0 + $1.cleanableBytes })
        if json { return emit(summary) }
        let width = max(24, rules.map(\.title.count).max() ?? 0)
        for rule in rules where rule.cleanableItems > 0 || rule.needsFullDiskAccess {
            let mark = rule.selectedByDefault ? "•" : "○"
            let size = rule.needsFullDiskAccess && rule.cleanableItems == 0 ? "needs Full Disk Access" : Self.bytes(rule.cleanableBytes)
            env.write("\(mark) \(rule.title.padding(toLength: width, withPad: " ", startingAt: 0))  \(size)\n")
        }
        env.write("\n\(Self.bytes(summary.selectedBytes)) would be cleaned by `spaceroom clean` (• ticked by default)")
        if summary.cleanableBytes > summary.selectedBytes {
            env.write(", \(Self.bytes(summary.cleanableBytes)) in all categories")
        }
        env.write(".\n")
        return .ok
    }

    // MARK: Clean

    struct CleanSummary: Codable {
        let dryRun: Bool
        let plannedBytes: Int64
        let plannedItems: Int
        let movedBytes: Int64
        let operations: [String]
        let skipped: Int
    }

    func clean(scope: String?, dryRun: Bool, assumeYes: Bool, json: Bool) async -> ExitCode {
        guard let modules = modules(for: scope) else { return usage("clean [cleanup|dev|all]") }
        if !dryRun, env.isAppRunning() {
            env.writeError("spaceroom: Spaceroom is open. Quit it first, or clean from the app.\n")
            return .refused
        }
        let catalog: RuleCatalog
        let context: ScanContext
        let store: RestoreStore
        do {
            catalog = try env.catalog()
            context = try self.context()
            store = try RestoreStore(directory: env.storeDirectory, ignore: .list(context.ignore))
        } catch {
            env.writeError("spaceroom: \(error)\n")
            return .failure
        }
        let reports = await scanReports(modules, catalog: catalog, context: context)
        let engine = CleanupEngine(store: store)
        var plans: [(CleanModule, [ScanItem], CleanPlan)] = []
        for (module, report) in reports {
            let items = report.results.filter { $0.rule.defaultSelected }.flatMap(\.cleanableItems)
            plans.append((module, items, engine.plan(items, rules: catalog.rules, context: context)))
        }
        let plannedBytes = plans.flatMap(\.2.moves).reduce(0) { $0 + $1.size }
        let plannedItems = plans.reduce(0) { $0 + $1.2.moves.count }

        if !json {
            for (_, _, plan) in plans {
                let byRule = Dictionary(grouping: plan.moves, by: \.ruleID)
                for (ruleID, moves) in byRule.sorted(by: { $0.key < $1.key }) {
                    let title = catalog.rules.first { $0.id == ruleID }?.localizedTitle ?? ruleID
                    env.write("  \(title): \(moves.count) items, \(Self.bytes(moves.reduce(0) { $0 + $1.size }))\n")
                }
            }
        }
        guard plannedItems > 0 else {
            if json { return emit(CleanSummary(dryRun: dryRun, plannedBytes: 0, plannedItems: 0, movedBytes: 0, operations: [], skipped: 0)) }
            env.write("Nothing to clean.\n")
            return .ok
        }
        if dryRun {
            if json {
                return emit(CleanSummary(dryRun: true, plannedBytes: plannedBytes, plannedItems: plannedItems,
                                         movedBytes: 0, operations: [], skipped: 0))
            }
            env.write("\nDry run: \(Self.bytes(plannedBytes)) in \(plannedItems) items would move to the Restore Center. Nothing was changed.\n")
            return .ok
        }
        if !assumeYes {
            guard env.isInteractive else {
                env.writeError("spaceroom: not a terminal; pass --yes to clean without asking.\n")
                return .refused
            }
            env.write("\nMove \(Self.bytes(plannedBytes)) in \(plannedItems) items to the Restore Center? [y/N] ")
            guard let answer = env.readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), ["y", "yes"].contains(answer) else {
                env.write("Nothing was changed.\n")
                return .refused
            }
        }
        // The scan and the question can take a while: check again right before writing.
        if env.isAppRunning() {
            env.writeError("spaceroom: Spaceroom was opened meanwhile. Nothing was changed; quit it and run this again.\n")
            return .refused
        }
        var moved: Int64 = 0
        var operations: [String] = []
        var skipped = 0
        for (module, items, _) in plans where !items.isEmpty {
            do {
                // The engine re-verifies every item (identity, app running, ignore list) right before it moves.
                let outcome = try await engine.clean(items, rules: catalog.rules, operationName: module.rawValue, context: context)
                if let operation = outcome.operation {
                    moved += operation.totalSize
                    operations.append(operation.id.uuidString)
                }
                skipped += outcome.skipped.count
            } catch {
                env.writeError("spaceroom: \(error)\n")
                return .failure
            }
        }
        if json {
            return emit(CleanSummary(dryRun: false, plannedBytes: plannedBytes, plannedItems: plannedItems,
                                     movedBytes: moved, operations: operations, skipped: skipped))
        }
        env.write("Moved \(Self.bytes(moved)) to the Restore Center. It's kept for \(env.retentionDays()) days, then deleted.\n")
        if skipped > 0 { env.write("\(skipped) items were skipped because they changed or came into use.\n") }
        for id in operations { env.write("Undo: spaceroom restore \(id.prefix(8).lowercased())\n") }
        return .ok
    }

    // MARK: Status and history

    struct Status: Codable {
        struct Volume: Codable {
            let name: String
            let path: String
            let totalBytes: Int64
            let availableBytes: Int64
        }
        let volumes: [Volume]
        let restoreCenterBytes: Int64
        let restoreCenterOperations: Int
        let retentionDays: Int
    }

    func status(json: Bool) async -> ExitCode {
        let store: RestoreStore
        do { store = try RestoreStore(directory: env.storeDirectory) } catch {
            env.writeError("spaceroom: \(error)\n")
            return .failure
        }
        let operations = await store.operations.filter(\.hasStoredItems)
        let status = Status(
            volumes: Volumes.mounted().map { Status.Volume(name: $0.name, path: $0.url.path, totalBytes: $0.totalBytes, availableBytes: $0.availableBytes) },
            restoreCenterBytes: operations.reduce(0) { $0 + $1.storedSize },
            restoreCenterOperations: operations.count,
            retentionDays: env.retentionDays())
        if json { return emit(status) }
        for volume in status.volumes {
            env.write("\(volume.name): \(Self.bytes(volume.availableBytes)) free of \(Self.bytes(volume.totalBytes))\n")
        }
        env.write("Restore Center: \(Self.bytes(status.restoreCenterBytes)) in \(status.restoreCenterOperations) cleans, kept \(status.retentionDays) days\n")
        return .ok
    }

    struct HistoryEntry: Codable {
        let id: String
        let date: Date
        let module: String
        let items: Int
        let totalBytes: Int64
        let restorable: Bool
    }

    func history(json: Bool) async -> ExitCode {
        let store: RestoreStore
        do { store = try RestoreStore(directory: env.storeDirectory) } catch {
            env.writeError("spaceroom: \(error)\n")
            return .failure
        }
        let entries = await store.operations.prefix(20).map {
            HistoryEntry(id: $0.id.uuidString, date: $0.date, module: $0.module, items: $0.items.count,
                         totalBytes: $0.totalSize, restorable: $0.hasStoredItems)
        }
        if json { return emit(entries) }
        if entries.isEmpty { env.write("No cleans yet.\n") }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for entry in entries {
            let state = entry.restorable ? "restorable" : "gone"
            env.write("\(entry.id.prefix(8).lowercased())  \(formatter.string(from: entry.date))  \(entry.module.padding(toLength: 12, withPad: " ", startingAt: 0))  \(entry.items) items  \(Self.bytes(entry.totalBytes))  \(state)\n")
        }
        return .ok
    }

    // MARK: Restore

    func restore(_ prefix: String?) async -> ExitCode {
        guard let prefix = prefix?.lowercased(), prefix.count >= 6 else {
            return usage("restore <operation-id> (at least 6 characters, see spaceroom history)")
        }
        if env.isAppRunning() {
            env.writeError("spaceroom: Spaceroom is open. Restore from its Restore Center, or quit it first.\n")
            return .refused
        }
        do {
            let store = try RestoreStore(directory: env.storeDirectory)
            let matches = await store.operations.filter { $0.id.uuidString.lowercased().hasPrefix(prefix) }
            guard matches.count == 1, let operation = matches.first else {
                env.writeError(matches.isEmpty ? "spaceroom: no clean matches \(prefix).\n" : "spaceroom: \(prefix) matches several cleans; use more characters.\n")
                return .failure
            }
            let outcomes = try await store.restoreAll(in: operation.id)
            let restored = outcomes.filter {
                switch $0 {
                case .restored, .restoredRenamed: true
                default: false
                }
            }.count
            env.write("Restored \(restored) of \(outcomes.count) items.\n")
            return restored == outcomes.count ? .ok : .failure
        } catch {
            env.writeError("spaceroom: \(error)\n")
            return .failure
        }
    }

    // MARK: Output

    func usage(_ text: String) -> ExitCode {
        env.writeError("usage: spaceroom \(text)\n")
        return .usage
    }

    func emit<T: Encodable>(_ value: T) -> ExitCode {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return .failure }
        env.write(String(decoding: data, as: UTF8.self) + "\n")
        return .ok
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
