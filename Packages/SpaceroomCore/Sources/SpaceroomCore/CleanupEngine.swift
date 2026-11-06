// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct SkippedItem: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let reason: SkipReason
}

/// The result of a dry run: what would move and what would be skipped, with reasons.
public struct CleanPlan: Sendable {
    public let moves: [PlannedMove]
    public let skipped: [SkippedItem]
    public var totalSize: Int64 { moves.reduce(0) { $0 + $1.size } }
}

public struct CleanOutcome: Sendable {
    /// `nil` when nothing was moved.
    public let operation: OperationRecord?
    public let skipped: [SkippedItem]
    public var freedSize: Int64 { operation?.totalSize ?? 0 }

    public init(operation: OperationRecord?, skipped: [SkippedItem]) {
        self.operation = operation
        self.skipped = skipped
    }
}

/// Turns reviewed scan items into a Restore Center operation.
///
/// Every item is re-verified right before it moves: it must still pass the safety guard,
/// its owning app must not have started, and it must be the same file-system object
/// (device + inode) that was scanned. Anything that fails is skipped, never forced.
public struct CleanupEngine: Sendable {
    public let store: RestoreStore

    public init(store: RestoreStore) {
        self.store = store
    }

    /// Dry run. Touches nothing.
    public func plan(_ items: [ScanItem], rules: [Rule], context: ScanContext) -> CleanPlan {
        let rulesByID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let guardrail = SafetyGuard(home: context.home)
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        // Build folders can hold programs people run (a CLI in target/release): check processes,
        // once, when any are being cleaned.
        let running = items.contains { rulesByID[$0.ruleID]?.projectArtifact != nil } ? RunningProcesses.current() : nil

        for item in items {
            if let reason = verify(item, rule: rulesByID[item.ruleID], guardrail: guardrail, context: context, running: running) {
                skipped.append(SkippedItem(path: item.url.path, size: item.size, reason: reason))
            } else {
                moves.append(PlannedMove(url: item.url, ruleID: item.ruleID, size: item.size, isDirectory: item.isDirectory))
            }
        }
        return CleanPlan(moves: moves, skipped: skipped)
    }

    /// Verifies and moves items into the Restore Center.
    ///
    /// - Parameter operationName: what the Restore Center shows as the source, e.g. "cleanup" or "smartCare".
    public func clean(_ items: [ScanItem], rules: [Rule], operationName: String, context: ScanContext) async throws -> CleanOutcome {
        let plan = plan(items, rules: rules, context: context)
        guard !plan.moves.isEmpty else { return CleanOutcome(operation: nil, skipped: plan.skipped) }
        let (record, failures) = try await store.quarantine(plan.moves, module: operationName, now: context.now)
        let sizes = Dictionary(plan.moves.map { ($0.url.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        let failed = failures.map { SkippedItem(path: $0.path, size: sizes[$0.path] ?? 0, reason: $0.reason) }
        return CleanOutcome(operation: record, skipped: plan.skipped + failed)
    }

    func verify(_ item: ScanItem, rule: Rule?, guardrail: SafetyGuard, context: ScanContext,
                running: RunningProcesses? = nil) -> SkipReason? {
        if let reason = item.skipReason { return reason }
        // Unknown rule: refuse. Items may only be cleaned on behalf of a loaded, validated rule.
        guard let rule else { return .outsideRoot }
        // Re-checked at clean time: the list may have changed since the scan.
        if context.ignore.ignoresRule(rule.id) || context.ignore.ignoresItem(at: item.url) { return .ignored }
        if let reason = guardrail.check(item.url, root: item.root) { return reason }
        if let app = rule.skipIfRunning.first(where: context.runningBundleIDs.contains) { return .inUse(bundleID: app) }
        // The same two names the scanner checks ("com.foo" and "com.foo.plist").
        if rule.skipIfOwnerRunning,
           let owner = context.runningOwner(of: item.url.lastPathComponent)
               ?? context.runningOwner(of: item.url.deletingPathExtension().lastPathComponent) {
            return .inUse(bundleID: owner)
        }
        if rule.projectArtifact != nil, let name = running?.program(inside: item.url) { return .running(name: name) }
        guard let identity = FileStat.identity(of: item.url) else { return .missing }
        if identity != item.identity { return .changedSinceScan }
        return nil
    }
}
