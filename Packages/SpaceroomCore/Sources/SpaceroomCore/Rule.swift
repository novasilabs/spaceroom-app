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
    /// Set for rules that find build folders inside projects (`node_modules` next to
    /// `package.json`). `paths` are then the folders to search, not the folders to clean, and
    /// `min_age_days` counts from the project's last change instead of the item's.
    public var projectArtifact: ProjectArtifactSpec?
    /// Keep only items whose content fails this check (for example preference files that no
    /// longer parse). Items that can't be read at all are left out, never treated as broken.
    public var contentCheck: ContentCheck?
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
        projectArtifact: ProjectArtifactSpec? = nil,
        contentCheck: ContentCheck? = nil,
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
        self.projectArtifact = projectArtifact
        self.contentCheck = contentCheck
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
        projectArtifact = try c.decodeIfPresent(ProjectArtifactSpec.self, forKey: .projectArtifact)
        contentCheck = try c.decodeIfPresent(ContentCheck.self, forKey: .contentCheck)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        sourceRef = try c.decodeIfPresent(String.self, forKey: .sourceRef)
    }
}

public enum ContentCheck: String, Codable, Sendable, Hashable {
    /// A property list that is empty or doesn't parse. The app it belongs to starts with
    /// default settings once it's gone.
    case brokenPropertyList = "broken_property_list"

    /// Whether `url` fails the check. `false` when the file can't be read (no permission).
    func fails(_ url: URL) -> Bool {
        switch self {
        case .brokenPropertyList:
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            // Preference files are small; a huge one isn't a settings file to judge.
            // `read` returns nil at the end of the file (an empty file) and throws on errors.
            let data: Data
            do { data = try handle.read(upToCount: 8 << 20) ?? Data() } catch { return false }
            if data.isEmpty { return true }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil
        }
    }
}

/// Which build folders a project rule collects, and how it recognises a project.
public struct ProjectArtifactSpec: Codable, Sendable, Hashable {
    /// Folder names to collect, e.g. `node_modules`. Plain names, never paths.
    public var folders: [String]
    /// `fnmatch` patterns for files that mark a project of this kind, e.g. `package.json`.
    /// A folder qualifies only next to one of these.
    public var markers: [String]

    public init(folders: [String], markers: [String]) {
        self.folders = folders
        self.markers = markers
    }
}

extension Rule {
    /// Title, explanation and rebuild hint in the user's language. Rules are data, so their
    /// translations live in the `Rules` table, keyed by the English text.
    public var localizedTitle: String { Self.translate(title) }
    public var localizedWhySafe: String { Self.translate(whySafe) }
    public var localizedRebuildHint: String? { rebuildHint.map(Self.translate) }

    static func translate(_ english: String) -> String {
        Bundle.module.localizedString(forKey: english, value: english, table: "Rules")
    }
}
