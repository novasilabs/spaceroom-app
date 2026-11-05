// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum RuleCatalogError: Error, Equatable, CustomStringConvertible {
    case missingRulesFolder
    case unreadableFile(String, underlying: String)
    case unsupportedVersion(String, Int)
    case duplicateID(String)
    case emptyField(ruleID: String, field: String)
    case invalidPattern(ruleID: String, pattern: String, reason: String)
    case invalidMinAge(ruleID: String)

    public var description: String {
        switch self {
        case .missingRulesFolder: "Rules folder not found in bundle"
        case .unreadableFile(let f, let u): "Rule file \(f) is unreadable: \(u)"
        case .unsupportedVersion(let f, let v): "Rule file \(f) has unsupported version \(v)"
        case .duplicateID(let id): "Duplicate rule ID \(id)"
        case .emptyField(let id, let field): "Rule \(id): \(field) must not be empty"
        case .invalidPattern(let id, let p, let r): "Rule \(id): path \"\(p)\" \(r)"
        case .invalidMinAge(let id): "Rule \(id): min_age_days must be ≥ 0"
        }
    }
}

/// The validated set of cleaning rules. Loading is fail-closed: if any file or rule is invalid,
/// the whole catalog fails to load and the app disables cleaning (scanning UI still explains why).
public struct RuleCatalog: Sendable {
    public static let supportedVersion = 1

    public let rules: [Rule]

    public init(rules: [Rule]) throws(RuleCatalogError) {
        try Self.validate(rules)
        self.rules = rules
    }

    public func rules(for module: CleanModule) -> [Rule] { rules.filter { $0.module == module } }

    public func rule(_ id: String) -> Rule? { rules.first { $0.id == id } }

    /// Rules shipped inside the SpaceroomCore bundle.
    public static func bundled() throws(RuleCatalogError) -> RuleCatalog {
        guard let folder = Bundle.module.url(forResource: "Rules", withExtension: nil) else {
            throw .missingRulesFolder
        }
        return try load(from: folder)
    }

    /// Loads every `*.json` file in a folder. Each file is `{ "version": 1, "rules": [...] }`.
    public static func load(from folder: URL) throws(RuleCatalogError) -> RuleCatalog {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw .unreadableFile(folder.lastPathComponent, underlying: error.localizedDescription)
        }
        var rules: [Rule] = []
        for file in files {
            let decoded: RuleFile
            do {
                decoded = try decoder.decode(RuleFile.self, from: Data(contentsOf: file))
            } catch {
                throw .unreadableFile(file.lastPathComponent, underlying: String(describing: error))
            }
            guard decoded.version == supportedVersion else {
                throw .unsupportedVersion(file.lastPathComponent, decoded.version)
            }
            rules += decoded.rules
        }
        return try RuleCatalog(rules: rules)
    }

    public static func validate(_ rules: [Rule]) throws(RuleCatalogError) {
        var ids: Set<String> = []
        for rule in rules {
            guard ids.insert(rule.id).inserted else { throw .duplicateID(rule.id) }
            for (field, value) in [("id", rule.id), ("group", rule.group), ("title", rule.title), ("why_safe", rule.whySafe)]
            where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw .emptyField(ruleID: rule.id, field: field)
            }
            if rule.paths.isEmpty { throw .emptyField(ruleID: rule.id, field: "paths") }
            if rule.minAgeDays < 0 { throw .invalidMinAge(ruleID: rule.id) }
            if let spec = rule.projectArtifact {
                try validateProjectRule(rule, spec)
                continue
            }
            for raw in rule.paths {
                do {
                    _ = try PathPattern(raw)
                } catch {
                    throw .invalidPattern(ruleID: rule.id, pattern: raw, reason: error.description)
                }
            }
        }
    }

    /// Project rules search folders such as `~/Documents` (which may never be a cleaning root),
    /// so their paths are checked separately: plain home folders, no wildcards, never Library.
    static func validateProjectRule(_ rule: Rule, _ spec: ProjectArtifactSpec) throws(RuleCatalogError) {
        if spec.folders.isEmpty { throw .emptyField(ruleID: rule.id, field: "project_artifact.folders") }
        if spec.markers.isEmpty { throw .emptyField(ruleID: rule.id, field: "project_artifact.markers") }
        for name in spec.folders + spec.markers where name.isEmpty || name.contains("/") || name == "." || name == ".." {
            throw .invalidPattern(ruleID: rule.id, pattern: name, reason: "must be a plain name")
        }
        for name in spec.folders where name.contains("*") || name.contains("?") || name.contains("[") {
            throw .invalidPattern(ruleID: rule.id, pattern: name, reason: "must not contain wildcards")
        }
        for raw in rule.paths {
            let components = raw.hasPrefix("~/") ? raw.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) : []
            let valid = !components.isEmpty && components.count <= 2
                && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("*") && !$0.contains("?") }
                && components.first != "Library"
            if !valid {
                throw .invalidPattern(ruleID: rule.id, pattern: raw,
                                      reason: "must be a folder in the home folder (not Library), without wildcards")
            }
        }
    }

    struct RuleFile: Decodable {
        let version: Int
        let rules: [Rule]
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}
