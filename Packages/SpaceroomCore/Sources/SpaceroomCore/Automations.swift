// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// When an automation runs.
public enum AutomationTrigger: Codable, Hashable, Sendable {
    /// Every day at a time.
    case daily(hour: Int, minute: Int)
    /// Every week on a weekday (1 = Sunday … 7 = Saturday, like `Calendar`) at a time.
    case weekly(weekday: Int, hour: Int, minute: Int)
    /// When the startup disk has less than this much free space.
    case lowDisk(freeBelowGB: Int)
    /// When Spaceroom opens, which is at login when it's set to open at login.
    case atLogin
    /// When a laptop is plugged into power.
    case pluggedIn

    public var isSchedule: Bool {
        switch self {
        case .daily, .weekly: true
        default: false
        }
    }
}

/// What an automation does. Every action only touches data that is safe to remove without
/// review (the same regenerable rules as one-click Smart Care), and cleaning always goes
/// through the Restore Center unless the user asked to free the space right away.
public enum AutomationAction: Codable, Hashable, Sendable {
    /// Scan with the Smart Care rules and report what could be cleaned. Never removes anything.
    case scanAndNotify
    /// Clean what one-click Smart Care would clean.
    case smartCareClean
    /// Move the Trash's contents into the Restore Center.
    case emptyTrash
    /// Clean Xcode DerivedData folders untouched for at least this many days.
    case purgeDerivedData(olderThanDays: Int)

    public var removesFiles: Bool { self != .scanAndNotify }
}

public struct Automation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var trigger: AutomationTrigger
    public var action: AutomationAction
    public var isEnabled: Bool
    /// Post a notification after each run.
    public var notifies: Bool
    /// Delete cleaned items straight away instead of keeping them in the Restore Center.
    public var freesSpaceNow: Bool
    /// When it was made, switched on or rescheduled. Schedules never catch up on moments before this.
    public var createdAt: Date
    public var lastRun: Date?

    public init(id: UUID = UUID(), trigger: AutomationTrigger, action: AutomationAction, isEnabled: Bool = true,
                notifies: Bool = true, freesSpaceNow: Bool = false, createdAt: Date = .now, lastRun: Date? = nil) {
        self.id = id
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
        self.notifies = notifies
        self.freesSpaceNow = freesSpaceNow
        self.createdAt = createdAt
        self.lastRun = lastRun
    }
}

/// The moment an automation check happens.
public struct AutomationContext: Sendable {
    public var now: Date
    /// Free space on the startup disk, if known.
    public var freeBytes: Int64?
    /// This check happens right after Spaceroom opened.
    public var isLaunch: Bool
    /// Power was connected since the previous check.
    public var didPlugIn: Bool

    public init(now: Date = .now, freeBytes: Int64? = nil, isLaunch: Bool = false, didPlugIn: Bool = false) {
        self.now = now
        self.freeBytes = freeBytes
        self.isLaunch = isLaunch
        self.didPlugIn = didPlugIn
    }
}

/// Decides when automations are due. Pure, so every rule is testable.
public enum AutomationSchedule {
    /// A low-disk automation runs at most this often, so a disk that stays full doesn't loop.
    public static let lowDiskCooldown: TimeInterval = 12 * 3600
    public static let pluggedInCooldown: TimeInterval = 6 * 3600
    public static let loginCooldown: TimeInterval = 3600

    public static func isDue(_ automation: Automation, context: AutomationContext, calendar: Calendar = .current) -> Bool {
        guard automation.isEnabled else { return false }
        let now = context.now
        func cooledDown(_ interval: TimeInterval) -> Bool {
            automation.lastRun.map { now.timeIntervalSince($0) >= interval } ?? true
        }
        switch automation.trigger {
        case .daily, .weekly:
            // Due once the most recent scheduled moment has passed since the last run (or since the
            // automation was armed). A Mac that slept through 9:00 catches up once when it wakes.
            guard let latest = latestFire(automation.trigger, atOrBefore: now, calendar: calendar) else { return false }
            return latest > max(automation.lastRun ?? .distantPast, automation.createdAt)
        case .lowDisk(let gigabytes):
            guard let free = context.freeBytes else { return false }
            return free < Int64(gigabytes) * 1_000_000_000 && cooledDown(lowDiskCooldown)
        case .atLogin:
            return context.isLaunch && cooledDown(loginCooldown)
        case .pluggedIn:
            return context.didPlugIn && cooledDown(pluggedInCooldown)
        }
    }

    /// The most recent scheduled moment at or before `now`.
    public static func latestFire(_ trigger: AutomationTrigger, atOrBefore now: Date, calendar: Calendar = .current) -> Date? {
        guard let components = components(trigger) else { return nil }
        return calendar.nextDate(after: now.addingTimeInterval(1), matching: components,
                                 matchingPolicy: .nextTime, direction: .backward)
    }

    /// The next scheduled moment after `now`, for "Next run" labels.
    public static func nextFire(_ trigger: AutomationTrigger, after now: Date, calendar: Calendar = .current) -> Date? {
        guard let components = components(trigger) else { return nil }
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime, direction: .forward)
    }

    private static func components(_ trigger: AutomationTrigger) -> DateComponents? {
        switch trigger {
        case .daily(let hour, let minute):
            DateComponents(hour: hour, minute: minute, second: 0)
        case .weekly(let weekday, let hour, let minute):
            DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday)
        default:
            nil
        }
    }
}

/// The record of one automation run, shown in the history list.
public struct AutomationRun: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var automationID: UUID
    public var date: Date
    public var action: AutomationAction
    /// What the scan found that could be cleaned.
    public var foundBytes: Int64
    /// What was moved out (into the Restore Center, or deleted when `freedNow`).
    public var cleanedBytes: Int64
    public var freedNow: Bool
    /// The Restore Center operation, for Undo.
    public var operationID: UUID?
    /// Items left alone (app running, too new, changed since the scan…).
    public var skippedCount: Int
    public var error: String?

    public init(id: UUID = UUID(), automationID: UUID, date: Date, action: AutomationAction, foundBytes: Int64 = 0,
                cleanedBytes: Int64 = 0, freedNow: Bool = false, operationID: UUID? = nil, skippedCount: Int = 0,
                error: String? = nil) {
        self.id = id
        self.automationID = automationID
        self.date = date
        self.action = action
        self.foundBytes = foundBytes
        self.cleanedBytes = cleanedBytes
        self.freedNow = freedNow
        self.operationID = operationID
        self.skippedCount = skippedCount
        self.error = error
    }
}

/// Runs an automation's action with the normal scanner and cleanup engine.
public struct AutomationRunner: Sendable {
    public static let operationName = "automations"
    public static let derivedDataRuleID = "dev.xcode.derived-data"

    public let catalog: RuleCatalog
    public let store: RestoreStore

    public init(catalog: RuleCatalog, store: RestoreStore) {
        self.catalog = catalog
        self.store = store
    }

    /// The rules an action uses. Only Smart Care–eligible, non-admin rules ever run unattended.
    public func rules(for action: AutomationAction) -> [Rule] {
        let safe = catalog.smartCareRules
        switch action {
        case .scanAndNotify, .smartCareClean:
            return safe
        case .emptyTrash:
            return safe.filter { $0.group == "trash" }
        case .purgeDerivedData(let days):
            return safe.filter { $0.id == Self.derivedDataRuleID }.map { rule in
                var rule = rule
                rule.minAgeDays = max(rule.minAgeDays, days)
                return rule
            }
        }
    }

    /// What an action would clean, measured but untouched.
    public struct Plan: Sendable {
        public let action: AutomationAction
        public let rules: [Rule]
        public let items: [ScanItem]
        /// Items found but left alone (app running, too new…).
        public let skippedCount: Int
        public var size: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    /// What happened when a plan was cleaned.
    public struct CleanResult: Sendable {
        public var cleanedBytes: Int64 = 0
        public var operationID: UUID?
        public var freedNow = false
        public var skippedCount = 0
        public var error: String?
    }

    /// Scans for an action. Never modifies the file system.
    public func plan(_ action: AutomationAction, context: ScanContext) async -> Plan {
        let rules = rules(for: action)
        guard !rules.isEmpty else { return Plan(action: action, rules: [], items: [], skippedCount: 0) }
        let report = await Scanner().scan(rules, claimRules: catalog.rules, context: context)
        let items = report.results.flatMap(\.cleanableItems)
        return Plan(action: action, rules: rules, items: items,
                    skippedCount: report.results.flatMap(\.items).count - items.count)
    }

    /// Cleans a plan into the Restore Center (re-checking every item), optionally freeing the space at once.
    public func clean(_ plan: Plan, operationName: String = AutomationRunner.operationName, freesSpaceNow: Bool = false,
                      context: ScanContext) async -> CleanResult {
        var result = CleanResult()
        guard plan.action.removesFiles, !plan.items.isEmpty else { return result }
        do {
            let outcome = try await CleanupEngine(store: store)
                .clean(plan.items, rules: plan.rules, operationName: operationName, context: context)
            result.skippedCount = outcome.skipped.count
            guard let operation = outcome.operation else { return result }
            result.cleanedBytes = operation.totalSize
            result.operationID = operation.id
            if freesSpaceNow {
                _ = try await store.purge(operation.id)
                // Anything macOS wouldn't let us delete stays in the Restore Center, still undoable.
                result.freedNow = await store.operation(operation.id)?.hasStoredItems != true
                if result.freedNow { result.operationID = nil }
            }
        } catch {
            result.error = error.localizedDescription
        }
        return result
    }

    public func run(_ automation: Automation, context: ScanContext) async -> AutomationRun {
        var run = AutomationRun(automationID: automation.id, date: context.now, action: automation.action)
        let plan = await plan(automation.action, context: context)
        guard !plan.rules.isEmpty else {
            run.error = "No cleaning rules are available for this action."
            return run
        }
        run.foundBytes = plan.size
        run.skippedCount = plan.skippedCount
        let cleaned = await clean(plan, freesSpaceNow: automation.freesSpaceNow, context: context)
        run.cleanedBytes = cleaned.cleanedBytes
        run.operationID = cleaned.operationID
        run.freedNow = cleaned.freedNow
        run.skippedCount += cleaned.skippedCount
        run.error = cleaned.error
        return run
    }
}

/// Saved automations and their run history, in `automations.json` next to the Restore Center.
public actor AutomationStore {
    public static let historyLimit = 100

    public private(set) var automations: [Automation]
    public private(set) var history: [AutomationRun]
    private let url: URL

    private struct File: Codable {
        var version = 1
        var automations: [Automation]
        var history: [AutomationRun]
    }

    /// Throws (fail-closed) if an existing file can't be read, so it is never overwritten.
    public init(directory: URL = RestoreStore.defaultDirectory) throws {
        url = directory.appendingPathComponent("automations.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let file = try Self.decoder.decode(File.self, from: Data(contentsOf: url))
            automations = file.automations
            history = file.history
        } else {
            automations = []
            history = []
        }
    }

    /// Adds the automation, or replaces the one with the same ID.
    public func save(_ automation: Automation) throws {
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[index] = automation
        } else {
            automations.append(automation)
        }
        try write()
    }

    public func delete(_ id: UUID) throws {
        automations.removeAll { $0.id == id }
        try write()
    }

    /// Stores a finished run and stamps the automation's last run.
    public func record(_ run: AutomationRun) throws {
        if let index = automations.firstIndex(where: { $0.id == run.automationID }) {
            automations[index].lastRun = run.date
        }
        history.insert(run, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        try write()
    }

    private func write() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(File(automations: automations, history: history)).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
