// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The app module a rule belongs to. Each module scans only its own rules.
public enum CleanModule: String, Codable, Sendable, CaseIterable {
    case cleanup
    case devCleanup
}

/// What happens to an item when it is cleaned.
public enum CleanAction: String, Codable, Sendable {
    /// Move into the Restore Center (default). Restorable until retention expires.
    case quarantine
}

/// A declarative cleaning rule, loaded from the bundled JSON rule files.
///
/// Rules are data, not code, so they can be reviewed, tested and (later) updated
/// without an app release. See CONTRIBUTING.md for the authoring checklist.
public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var module: CleanModule
    /// Category shown as one card in the results screen, e.g. "caches", "xcode".
    public var group: String
    public var title: String
    /// Plain-language explanation shown next to every item ("Why is this safe?").
    public var whySafe: String
    /// What it costs to get the data back, e.g. "Next build takes longer".
    public var rebuildHint: String?
    /// Path patterns. `~/` is the user's home. A wildcard may only appear in the last component.
    public var paths: [String]
    /// `fnmatch` patterns matched against item names to leave out.
    public var exclude: [String]
    /// Items modified more recently than this are skipped.
    public var minAgeDays: Int
    /// Skip every item of the rule while one of these bundle IDs is running.
    public var skipIfRunning: [String]
    /// Treat each item's name as the owning app's bundle ID and skip it while that app runs.
    public var skipIfOwnerRunning: Bool
    public var requiresAdmin: Bool
    public var defaultSelected: Bool
    /// Eligible for one-click Smart Care (regenerable data only).
    public var smartCare: Bool
    public var action: CleanAction
    /// "mole" when ported from Mole; `sourceRef` then holds the upstream commit.
    public var source: String?
    public var sourceRef: String?

    public init(
        id: String,
        module: CleanModule,
        group: String,
        title: String,
        whySafe: String,
        rebuildHint: String? = nil,
        paths: [String],
        exclude: [String] = [],
        minAgeDays: Int = 0,
        skipIfRunning: [String] = [],
        skipIfOwnerRunning: Bool = false,
        requiresAdmin: Bool = false,
        defaultSelected: Bool = true,
        smartCare: Bool = false,
        action: CleanAction = .quarantine,
        source: String? = nil,
        sourceRef: String? = nil
    ) {
        self.id = id
        self.module = module
        self.group = group
        self.title = title
        self.whySafe = whySafe
        self.rebuildHint = rebuildHint
        self.paths = paths
        self.exclude = exclude
        self.minAgeDays = minAgeDays
        self.skipIfRunning = skipIfRunning
        self.skipIfOwnerRunning = skipIfOwnerRunning
        self.requiresAdmin = requiresAdmin
        self.defaultSelected = defaultSelected
        self.smartCare = smartCare
        self.action = action
        self.source = source
        self.sourceRef = sourceRef
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        module = try c.decode(CleanModule.self, forKey: .module)
        group = try c.decode(String.self, forKey: .group)
        title = try c.decode(String.self, forKey: .title)
        whySafe = try c.decode(String.self, forKey: .whySafe)
        rebuildHint = try c.decodeIfPresent(String.self, forKey: .rebuildHint)
        paths = try c.decode([String].self, forKey: .paths)
        exclude = try c.decodeIfPresent([String].self, forKey: .exclude) ?? []
        minAgeDays = try c.decodeIfPresent(Int.self, forKey: .minAgeDays) ?? 0
        skipIfRunning = try c.decodeIfPresent([String].self, forKey: .skipIfRunning) ?? []
        skipIfOwnerRunning = try c.decodeIfPresent(Bool.self, forKey: .skipIfOwnerRunning) ?? false
        requiresAdmin = try c.decodeIfPresent(Bool.self, forKey: .requiresAdmin) ?? false
        defaultSelected = try c.decodeIfPresent(Bool.self, forKey: .defaultSelected) ?? true
        smartCare = try c.decodeIfPresent(Bool.self, forKey: .smartCare) ?? false
        action = try c.decodeIfPresent(CleanAction.self, forKey: .action) ?? .quarantine
        source = try c.decodeIfPresent(String.self, forKey: .source)
        sourceRef = try c.decodeIfPresent(String.self, forKey: .sourceRef)
    }
}
