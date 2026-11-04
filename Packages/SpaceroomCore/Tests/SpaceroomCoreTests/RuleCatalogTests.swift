// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Rule catalog")
struct RuleCatalogTests {
    @Test func bundledRulesLoadAndValidate() throws {
        let catalog = try RuleCatalog.bundled()
        #expect(!catalog.rules(for: .cleanup).isEmpty)
        #expect(!catalog.rules(for: .devCleanup).isEmpty)
    }

    @Test func bundledRulesFollowAuthoringRules() throws {
        for rule in try RuleCatalog.bundled().rules {
            #expect(rule.whySafe.count >= 20, "\(rule.id): why_safe should be a real explanation")
            #expect(rule.id.contains("."), "\(rule.id): use a dotted id like group.name")
            #expect(!rule.requiresAdmin, "\(rule.id): admin rules need the privileged helper (v0.5)")
            if rule.smartCare { #expect(rule.defaultSelected, "\(rule.id): Smart Care rules must be default-selected") }
            if rule.source == "mole" { #expect(rule.sourceRef != nil, "\(rule.id): ported rules need source_ref") }
        }
    }

    @Test func rejectsDuplicateIDs() {
        #expect(throws: RuleCatalogError.duplicateID("a.b")) {
            try RuleCatalog(rules: [.test("a.b"), .test("a.b")])
        }
    }

    @Test func rejectsUnsafePattern() {
        #expect(throws: RuleCatalogError.self) {
            try RuleCatalog(rules: [.test("bad.rule", paths: ["~/Documents/*"])])
        }
    }

    @Test func rejectsEmptyExplanation() {
        var rule = Rule.test("x.y")
        rule.whySafe = "  "
        #expect(throws: RuleCatalogError.emptyField(ruleID: "x.y", field: "why_safe")) {
            try RuleCatalog(rules: [rule])
        }
    }

    @Test func badFileFailsTheWholeCatalog() throws {
        let box = try Sandbox()
        let folder = try box.folder("rules")
        try Data(#"{"version":1,"rules":[]}"#.utf8).write(to: folder.appendingPathComponent("a.json"))
        try Data(#"{"version":1,"rules":[{"id":"x"}]}"#.utf8).write(to: folder.appendingPathComponent("b.json"))
        #expect(throws: RuleCatalogError.self) { try RuleCatalog.load(from: folder) }
    }

    @Test func rejectsUnknownVersion() throws {
        let box = try Sandbox()
        let folder = try box.folder("rules")
        try Data(#"{"version":2,"rules":[]}"#.utf8).write(to: folder.appendingPathComponent("a.json"))
        #expect(throws: RuleCatalogError.unsupportedVersion("a.json", 2)) { try RuleCatalog.load(from: folder) }
    }
}
