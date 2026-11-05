// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One cleanable (or skipped) thing found by a rule: usually a folder like `~/Library/Caches/com.foo`.
public struct ScanItem: Sendable, Identifiable, Hashable {
    /// The item's path. Unique within a scan.
    public var id: String { url.path }
    public let url: URL
    public let ruleID: String
    /// The rule root the item was found in (used for the safety re-check before cleaning).
    public let root: URL
    public let size: Int64
    public let fileCount: Int
    public let lastModified: Date
    public let isDirectory: Bool
    public let identity: FileIdentity
    /// Non-nil when the item will not be cleaned (in use, too recent, protected…).
    public let skipReason: SkipReason?

    public var isCleanable: Bool { skipReason == nil }

    public init(url: URL, ruleID: String, root: URL, size: Int64, fileCount: Int, lastModified: Date,
                isDirectory: Bool, identity: FileIdentity, skipReason: SkipReason?) {
        self.url = url
        self.ruleID = ruleID
        self.root = root
        self.size = size
        self.fileCount = fileCount
        self.lastModified = lastModified
        self.isDirectory = isDirectory
        self.identity = identity
        self.skipReason = skipReason
    }
}

public struct RuleScanResult: Sendable, Identifiable {
    public var id: String { rule.id }
    public let rule: Rule
    /// Sorted largest first.
    public let items: [ScanItem]
    /// macOS refused to list at least one of the rule's folders (usually: Full Disk Access is off).
    public let accessDenied: Bool

    public init(rule: Rule, items: [ScanItem], accessDenied: Bool = false) {
        self.rule = rule
        self.items = items
        self.accessDenied = accessDenied
    }

    public var cleanableItems: [ScanItem] { items.filter(\.isCleanable) }
    public var cleanableSize: Int64 { cleanableItems.reduce(0) { $0 + $1.size } }
    public var skippedSize: Int64 { items.filter { !$0.isCleanable }.reduce(0) { $0 + $1.size } }
}

public struct ScanReport: Sendable {
    public let results: [RuleScanResult]
    public let startedAt: Date
    public let finishedAt: Date
    public let wasCancelled: Bool

    public var cleanableSize: Int64 { results.reduce(0) { $0 + $1.cleanableSize } }
    public func result(for ruleID: String) -> RuleScanResult? { results.first { $0.rule.id == ruleID } }
}

public enum ScanEvent: Sendable {
    case started(ruleCount: Int)
    case ruleFinished(RuleScanResult, completed: Int, total: Int)
    case finished(ScanReport)
}

/// Facts about the environment a scan runs in. Injected so the engine is testable.
public struct ScanContext: Sendable {
    public var home: URL
    public var runningBundleIDs: Set<String>
    /// Lowercased names of running apps (display name, executable name, last bundle-ID component).
    /// Cache folders are often named after the app ("Dia", "Slack") rather than its bundle ID.
    public var runningAppNames: Set<String>
    public var now: Date
    /// Things the user never wants cleaned. Matches are reported with `.ignored`.
    public var ignore: IgnoreList

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                runningBundleIDs: Set<String> = [], runningAppNames: Set<String> = [], now: Date = .now,
                ignore: IgnoreList = IgnoreList()) {
        self.home = home
        self.ignore = ignore
        self.runningBundleIDs = runningBundleIDs
        self.runningAppNames = Set(runningAppNames.map { $0.lowercased() })
        self.now = now
    }

    /// The running app that owns an item named `name`, if any (matched by bundle ID or app name).
    public func runningOwner(of name: String) -> String? {
        if runningBundleIDs.contains(name) { return name }
        if runningAppNames.contains(name.lowercased()) { return name }
        return nil
    }
}

/// Expands rules, measures items and marks skip reasons. Never modifies the file system.
public struct Scanner: Sendable {
    public let maxConcurrentRules: Int

    public init(maxConcurrentRules: Int = 4) {
        self.maxConcurrentRules = max(1, maxConcurrentRules)
    }

    /// Streams per-rule results as they finish, then the final report.
    ///
    /// - Parameter claimRules: every rule in the catalog. An item is left to the most specific
    ///   rule: a rule never takes an item that is, or contains, another rule's claimed path
    ///   (so `~/Library/Caches/Homebrew` belongs to the Homebrew rule, not "User caches").
    public func events(for rules: [Rule], claimRules: [Rule]? = nil, context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                let report = await scan(rules, claimRules: claimRules, context: context) { result, done, total in
                    continuation.yield(.ruleFinished(result, completed: done, total: total))
                }
                continuation.yield(.finished(report))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func scan(
        _ rules: [Rule],
        claimRules: [Rule]? = nil,
        context: ScanContext,
        onRuleFinished: @Sendable (RuleScanResult, Int, Int) -> Void = { _, _, _ in }
    ) async -> ScanReport {
        let started = Date.now
        let claims = Self.claims(for: claimRules ?? rules, home: context.home)
        var results: [String: RuleScanResult] = [:]

        await withTaskGroup(of: RuleScanResult.self) { group in
            var pending = rules[...]
            // Bounded fan-out: start N rules, add one each time one finishes.
            for _ in 0..<maxConcurrentRules {
                guard let rule = pending.popFirst() else { break }
                group.addTask { Self.scanRule(rule, claims: claims, context: context) }
            }
            while let result = await group.next() {
                results[result.rule.id] = result
                onRuleFinished(result, results.count, rules.count)
                if Task.isCancelled { group.cancelAll(); continue }
                if let rule = pending.popFirst() {
                    group.addTask { Self.scanRule(rule, claims: claims, context: context) }
                }
            }
        }

        return ScanReport(
            results: rules.compactMap { results[$0.id] },
            startedAt: started,
            finishedAt: .now,
            wasCancelled: Task.isCancelled
        )
    }

    /// Claimed real paths per rule ID.
    static func claims(for rules: [Rule], home: URL) -> [(ruleID: String, path: String)] {
        rules.flatMap { rule in
            rule.paths.compactMap { raw -> (String, String)? in
                guard let pattern = try? PathPattern(raw) else { return nil }
                return (rule.id, SafetyGuard.realPath(pattern.claimURL(home: home)))
            }
        }
    }

    static func scanRule(_ rule: Rule, claims: [(ruleID: String, path: String)], context: ScanContext) -> RuleScanResult {
        // An ignored category isn't scanned at all.
        if context.ignore.ignoresRule(rule.id) { return RuleScanResult(rule: rule, items: []) }
        let guardrail = SafetyGuard(home: context.home)
        let ruleInUse = rule.skipIfRunning.first { context.runningBundleIDs.contains($0) }
        var items: [ScanItem] = []
        var seen: Set<String> = []
        var accessDenied = false

        for raw in rule.paths {
            if Task.isCancelled { break }
            guard let pattern = try? PathPattern(raw) else { continue }
            let root = pattern.rootURL(home: context.home)
            if pattern.isAccessDenied(home: context.home) { accessDenied = true }

            for url in pattern.expand(home: context.home, exclude: rule.exclude) {
                if Task.isCancelled { break }
                let real = SafetyGuard.realPath(url)
                guard seen.insert(real).inserted else { continue }
                // Leave the item to a more specific rule that claims it or something inside it.
                let claimedElsewhere = claims.contains { claim in
                    claim.ruleID != rule.id && (claim.path == real || claim.path.hasPrefix(real + "/"))
                }
                if claimedElsewhere { continue }

                guard let m = FileStat.measure(url, isCancelled: { Task.isCancelled }) else { continue }

                var reason: SkipReason? = context.ignore.ignoresItem(at: url) ? .ignored : nil
                if reason == nil { reason = guardrail.check(url, root: root) }
                if reason == nil, let app = ruleInUse { reason = .inUse(bundleID: app) }
                if reason == nil, rule.skipIfOwnerRunning, let owner = context.runningOwner(of: url.lastPathComponent) {
                    reason = .inUse(bundleID: owner)
                }
                if reason == nil, rule.minAgeDays > 0,
                   context.now.timeIntervalSince(m.newestModification) < TimeInterval(rule.minAgeDays) * 86_400 {
                    reason = .tooRecent(minAgeDays: rule.minAgeDays)
                }

                items.append(ScanItem(
                    url: url, ruleID: rule.id, root: root, size: m.allocatedSize, fileCount: m.fileCount,
                    lastModified: m.newestModification, isDirectory: m.isDirectory, identity: m.identity,
                    skipReason: reason
                ))
            }
        }
        items.sort { $0.size > $1.size }
        return RuleScanResult(rule: rule, items: items, accessDenied: accessDenied)
    }
}
