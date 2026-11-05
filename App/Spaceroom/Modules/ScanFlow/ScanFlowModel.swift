// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SpaceroomCore
import SwiftUI

/// Which rules a scan flow runs.
enum FlowKind: Hashable {
    /// One click across every module: only `smart_care` rules.
    case smartCare
    case module(CleanModule)

    /// Name recorded on Restore Center operations (matches `SidebarModule.rawValue`).
    var operationName: String {
        switch self {
        case .smartCare: "smartCare"
        case .module(let module): module.rawValue
        }
    }
}

/// State machine behind every scan-based module: Intro → Scanning → Results → Cleaning → Done.
@MainActor
@Observable
final class ScanFlowModel {
    enum Phase: Equatable {
        case intro
        case scanning
        case results
        case cleaning
        case done
    }

    /// One card on the results screen.
    struct GroupSummary: Identifiable {
        let id: String
        let info: GroupInfo
        let ruleIDs: [String]
        let cleanableSize: Int64
        let selectedSize: Int64
        let isSelected: Bool
        /// Nothing found because macOS denied access (Full Disk Access off).
        let needsAccess: Bool
    }

    let kind: FlowKind
    private unowned let app: AppModel

    private(set) var phase: Phase = .intro
    private(set) var results: [RuleScanResult] = []
    private(set) var completedRules = 0
    private(set) var totalRules = 0
    private(set) var lastOutcome: CleanOutcome?
    /// The last clean was released from the Restore Center ("Free Up Now"), so its space is free.
    private(set) var isReleased = false
    /// Short confirmation shown on the intro screen ("Restored 8.4 GB").
    private(set) var notice: String?
    /// The startup disk when results arrived (Smart Care's disk tile).
    private(set) var volumeAtResults: VolumeInfo?

    var selectedRuleIDs: Set<String> = []
    /// Individual items the user unticked in Review Details.
    var deselectedItemIDs: Set<String> = []
    var isReviewing = false
    var focusedRuleID: String?

    private var scanTask: Task<Void, Never>?

    init(kind: FlowKind, app: AppModel) {
        self.kind = kind
        self.app = app
    }

    var rules: [Rule] {
        guard let catalog = app.catalog else { return [] }
        switch kind {
        case .smartCare: return catalog.smartCareRules
        case .module(let module): return catalog.rules(for: module)
        }
    }

    /// Card a rule belongs to: Smart Care groups by area, modules by rule group.
    func groupKey(for rule: Rule) -> String {
        switch kind {
        case .smartCare: "smartCare." + SmartCareArea(rule: rule).rawValue
        case .module: rule.group
        }
    }

    /// Scan progress per card, for Smart Care's tile rings.
    var groupProgress: [(key: String, info: GroupInfo, done: Int, total: Int)] {
        var order: [String] = []
        var totals: [String: Int] = [:]
        for rule in rules {
            let key = groupKey(for: rule)
            if totals[key] == nil { order.append(key) }
            totals[key, default: 0] += 1
        }
        var done: [String: Int] = [:]
        for result in results { done[groupKey(for: result.rule), default: 0] += 1 }
        return sortedKeys(order).map { ($0, GroupInfo.forGroup($0), done[$0] ?? 0, totals[$0] ?? 0) }
    }

    // MARK: Derived

    var scanProgress: Double { totalRules == 0 ? 0 : Double(completedRules) / Double(totalRules) }

    var foundSize: Int64 { results.reduce(0) { $0 + $1.cleanableSize } }

    var selectedItems: [ScanItem] {
        results
            .filter { selectedRuleIDs.contains($0.rule.id) }
            .flatMap(\.cleanableItems)
            .filter { !deselectedItemIDs.contains($0.id) }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var skippedItemCount: Int { results.reduce(0) { $0 + $1.items.count - $1.cleanableItems.count } }

    var groups: [GroupSummary] {
        var order: [String] = []
        var byGroup: [String: [RuleScanResult]] = [:]
        for result in results where !result.items.isEmpty || result.accessDenied {
            let key = groupKey(for: result.rule)
            if byGroup[key] == nil { order.append(key) }
            byGroup[key, default: []].append(result)
        }
        return sortedKeys(order).map { group in
            let members = byGroup[group] ?? []
            let selected = members.filter { selectedRuleIDs.contains($0.rule.id) }
            return GroupSummary(
                id: group,
                info: .forGroup(group),
                ruleIDs: members.map(\.rule.id),
                cleanableSize: members.reduce(0) { $0 + $1.cleanableSize },
                selectedSize: selected.reduce(0) { $0 + selectedSize(of: $1) },
                isSelected: !selected.isEmpty && members.contains { !$0.items.isEmpty },
                needsAccess: members.allSatisfy { $0.items.isEmpty && $0.accessDenied }
            )
        }
    }

    /// Smart Care tiles always read System Junk → Developer Junk → Trash; modules keep rule order.
    private func sortedKeys(_ keys: [String]) -> [String] {
        guard kind == .smartCare else { return keys }
        let rank = Dictionary(uniqueKeysWithValues: SmartCareArea.allCases.enumerated().map { ("smartCare." + $1.rawValue, $0) })
        return keys.sorted { (rank[$0] ?? .max) < (rank[$1] ?? .max) }
    }

    func selectedSize(of result: RuleScanResult) -> Int64 {
        guard selectedRuleIDs.contains(result.rule.id) else { return 0 }
        return result.cleanableItems.filter { !deselectedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    // MARK: Actions

    func startScan() {
        guard phase != .scanning else { return }
        notice = nil
        isReleased = false
        results = []
        completedRules = 0
        let rules = rules
        totalRules = rules.count
        deselectedItemIDs = []
        selectedRuleIDs = Set(rules.filter(\.defaultSelected).map(\.id))
        isReviewing = false
        withAnimation(Motion.phaseChange) { phase = .scanning }

        let context = app.scanContext()
        let claimRules = app.catalog?.rules ?? rules
        scanTask = Task { [weak self] in
            for await event in Scanner().events(for: rules, claimRules: claimRules, context: context) {
                guard let self else { return }
                switch event {
                case .started:
                    break
                case .ruleFinished(let result, let completed, _):
                    withAnimation(Easing.out(0.2)) {
                        self.results.append(result)
                        self.completedRules = completed
                    }
                case .finished(let report):
                    guard !report.wasCancelled else { return }
                    // Keep catalog order (results streamed in completion order).
                    self.results = report.results
                    self.volumeAtResults = Volumes.root()
                    withAnimation(Motion.phaseChange) { self.phase = .results }
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        withAnimation(Motion.phaseChange) { phase = .intro }
    }

    func toggleGroup(_ group: GroupSummary) {
        if group.isSelected {
            selectedRuleIDs.subtract(group.ruleIDs)
        } else {
            selectedRuleIDs.formUnion(group.ruleIDs)
        }
    }

    func toggleRule(_ ruleID: String) {
        if selectedRuleIDs.contains(ruleID) { selectedRuleIDs.remove(ruleID) } else { selectedRuleIDs.insert(ruleID) }
    }

    func toggleItem(_ item: ScanItem) {
        if deselectedItemIDs.contains(item.id) { deselectedItemIDs.remove(item.id) } else { deselectedItemIDs.insert(item.id) }
        // Ticking an item in an unticked rule selects the rule.
        if !deselectedItemIDs.contains(item.id) { selectedRuleIDs.insert(item.ruleID) }
    }

    func clean() {
        guard let store = app.store, let catalog = app.catalog, !selectedItems.isEmpty else { return }
        let items = selectedItems
        let context = app.scanContext()
        let operationName = kind.operationName
        isReviewing = false
        withAnimation(Motion.phaseChange) { phase = .cleaning }

        Task {
            // Keep the cleaning state on screen briefly so the transition reads as an action.
            let minimumDisplay = ContinuousClock.now + .milliseconds(700)
            do {
                let outcome = try await CleanupEngine(store: store)
                    .clean(items, rules: catalog.rules, operationName: operationName, context: context)
                try? await Task.sleep(until: minimumDisplay)
                lastOutcome = outcome
                await app.refreshOperations()
                withAnimation(Motion.phaseChange) { phase = .done }
            } catch {
                try? await Task.sleep(until: minimumDisplay)
                app.show(String(localized: "Cleaning failed"), error)
                withAnimation(Motion.phaseChange) { phase = .results }
            }
        }
    }

    /// Restores everything the last clean moved, then returns to the intro screen.
    func undoLastClean() {
        guard let operation = lastOutcome?.operation else { return }
        Task {
            if await app.restoreAll(operation.id) {
                notice = String(localized: "Restored \(operation.totalSize.bytesText). Everything is back where it was.")
            }
            lastOutcome = nil
            withAnimation(Motion.phaseChange) { phase = .intro }
        }
    }

    /// Permanently deletes what the last clean moved, so the disk space is free right away.
    func freeUpNow() {
        guard let operation = lastOutcome?.operation else { return }
        Task {
            if await app.purge(operation.id) {
                withAnimation(Motion.hover) { isReleased = true }
            }
        }
    }

    func finish() {
        isReleased = false
        lastOutcome = nil
        results = []
        withAnimation(Motion.phaseChange) { phase = .intro }
    }
}
