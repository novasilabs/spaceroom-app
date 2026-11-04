// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SpaceroomCore
import SwiftUI

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

    let module: CleanModule
    private unowned let app: AppModel

    private(set) var phase: Phase = .intro
    private(set) var results: [RuleScanResult] = []
    private(set) var completedRules = 0
    private(set) var totalRules = 0
    private(set) var lastOutcome: CleanOutcome?
    /// Short confirmation shown on the intro screen ("Restored 8.4 GB").
    private(set) var notice: String?

    var selectedRuleIDs: Set<String> = []
    /// Individual items the user unticked in Review Details.
    var deselectedItemIDs: Set<String> = []
    var isReviewing = false
    var focusedRuleID: String?

    private var scanTask: Task<Void, Never>?

    init(module: CleanModule, app: AppModel) {
        self.module = module
        self.app = app
    }

    var rules: [Rule] { app.catalog?.rules(for: module) ?? [] }

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
            if byGroup[result.rule.group] == nil { order.append(result.rule.group) }
            byGroup[result.rule.group, default: []].append(result)
        }
        return order.map { group in
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

    func selectedSize(of result: RuleScanResult) -> Int64 {
        guard selectedRuleIDs.contains(result.rule.id) else { return 0 }
        return result.cleanableItems.filter { !deselectedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    // MARK: Actions

    func startScan() {
        guard phase != .scanning else { return }
        notice = nil
        results = []
        completedRules = 0
        let rules = rules
        totalRules = rules.count
        deselectedItemIDs = []
        selectedRuleIDs = Set(rules.filter(\.defaultSelected).map(\.id))
        isReviewing = false
        withAnimation(.spring(duration: 0.5)) { phase = .scanning }

        let context = app.scanContext()
        let claimRules = app.catalog?.rules ?? rules
        scanTask = Task { [weak self] in
            for await event in Scanner().events(for: rules, claimRules: claimRules, context: context) {
                guard let self else { return }
                switch event {
                case .started:
                    break
                case .ruleFinished(let result, let completed, _):
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.results.append(result)
                        self.completedRules = completed
                    }
                case .finished(let report):
                    guard !report.wasCancelled else { return }
                    // Keep catalog order (results streamed in completion order).
                    self.results = report.results
                    withAnimation(.spring(duration: 0.5)) { self.phase = .results }
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        withAnimation(.spring(duration: 0.4)) { phase = .intro }
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
        let module = module
        isReviewing = false
        withAnimation(.spring(duration: 0.5)) { phase = .cleaning }

        Task {
            // Keep the cleaning state on screen briefly so the transition reads as an action.
            let minimumDisplay = ContinuousClock.now + .milliseconds(700)
            do {
                let outcome = try await CleanupEngine(store: store)
                    .clean(items, rules: catalog.rules, module: module, context: context)
                try? await Task.sleep(until: minimumDisplay)
                lastOutcome = outcome
                await app.refreshOperations()
                withAnimation(.spring(duration: 0.5)) { phase = .done }
            } catch {
                try? await Task.sleep(until: minimumDisplay)
                app.show(String(localized: "Cleaning failed"), error)
                withAnimation(.spring(duration: 0.5)) { phase = .results }
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
            withAnimation(.spring(duration: 0.5)) { phase = .intro }
        }
    }

    func finish() {
        lastOutcome = nil
        results = []
        withAnimation(.spring(duration: 0.5)) { phase = .intro }
    }
}
