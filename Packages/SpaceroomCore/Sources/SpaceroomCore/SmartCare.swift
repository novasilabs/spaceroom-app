// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The tiles on the Smart Care results screen. Every Smart Care rule lands in exactly one.
public enum SmartCareArea: String, CaseIterable, Sendable {
    case systemJunk
    case developerJunk
    case trash

    public init(rule: Rule) {
        if rule.group == "trash" {
            self = .trash
        } else if rule.module == .devCleanup {
            self = .developerJunk
        } else {
            self = .systemJunk
        }
    }
}

extension RuleCatalog {
    /// Rules Smart Care runs in one click: only regenerable, default-selected data from every module.
    public var smartCareRules: [Rule] {
        rules.filter { $0.smartCare && $0.defaultSelected && !$0.requiresAdmin }
    }
}

extension CleanupEngine {
    /// Cleans on behalf of a cleaning module.
    public func clean(_ items: [ScanItem], rules: [Rule], module: CleanModule, context: ScanContext) async throws -> CleanOutcome {
        try await clean(items, rules: rules, operationName: module.rawValue, context: context)
    }
}
