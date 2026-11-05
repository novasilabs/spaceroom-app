// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Smart Care")
struct SmartCareTests {
    @Test func usesOnlySafeRulesFromEveryModule() throws {
        let catalog = try RuleCatalog.bundled()
        let rules = catalog.smartCareRules
        #expect(rules.allSatisfy { $0.smartCare && $0.defaultSelected && !$0.requiresAdmin })
        #expect(Set(rules.map(\.module)) == [.cleanup, .devCleanup])
        // Expensive-to-rebuild data never runs in one click.
        #expect(!rules.contains { $0.id == "dev.gradle.caches" || $0.id == "dev.xcode.ios-device-support" })
    }

    @Test func everyBundledSmartCareRuleHasAnArea() throws {
        let areas = Set(try RuleCatalog.bundled().smartCareRules.map(SmartCareArea.init(rule:)))
        #expect(areas == Set(SmartCareArea.allCases))
    }

    @Test("Areas", arguments: [
        (Rule.test("t", paths: ["~/.Trash/*"]).with(group: "trash"), SmartCareArea.trash),
        (Rule.test("d", module: .devCleanup), .developerJunk),
        (Rule.test("c"), .systemJunk),
    ])
    func areaMapping(rule: Rule, expected: SmartCareArea) {
        #expect(SmartCareArea(rule: rule) == expected)
    }

    @Test func operationIsRecordedUnderSmartCare() async throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example/data")
        let rule = Rule.test()
        let report = await Scanner().scan([rule], context: box.context())
        let outcome = try await CleanupEngine(store: try box.store())
            .clean(report.results[0].items, rules: [rule], operationName: "smartCare", context: box.context())
        #expect(outcome.operation?.module == "smartCare")
    }
}

extension Rule {
    func with(group: String) -> Rule {
        var copy = self
        copy.group = group
        return copy
    }
}
