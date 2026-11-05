// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Why an item was not (or will not be) cleaned. Shown to the user next to the item.
public enum SkipReason: Codable, Sendable, Hashable {
    /// The owning app is running ("Close Xcode to clean this").
    case inUse(bundleID: String)
    /// Modified within the rule's minimum age.
    case tooRecent(minAgeDays: Int)
    /// Resolves outside the rule's root folder.
    case outsideRoot
    /// Is, or contains, a protected system or user folder.
    case protectedPath
    /// The item changed identity (replaced or swapped) since it was scanned.
    case changedSinceScan
    /// The item no longer exists.
    case missing
    /// macOS refused access (usually Full Disk Access is missing).
    case notPermitted
    /// Moving the item failed for another reason.
    case moveFailed(String)
    /// On the user's ignore list.
    case ignored
    /// Part of a Git repository's tracked files (`verified`), or inside a repository when Git
    /// isn't installed to check (`verified == false`). Committed folders are never offered.
    case trackedByGit(verified: Bool)
}

/// Last line of defence before anything is moved. Pure path logic, no side effects.
///
/// An item is allowed only if, after resolving symlinks in its parent folders:
/// - it is strictly inside the rule's root folder, and
/// - it is not a protected folder, does not contain one, and is not inside a system folder.
public struct SafetyGuard: Sendable {
    public let home: URL
    private let protectedPaths: Set<String>

    /// System trees nothing may ever be removed from.
    static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/var/db", "/private/var/db"]

    public init(home: URL) {
        self.home = home
        let realHome = Self.realPath(home)
        var paths: Set<String> = ["/", "/Applications", "/Library", "/Users", "/Volumes", "/private", "/var", realHome]
        for name in PathPattern.protectedHomeRoots {
            paths.insert(realHome + "/" + name)
        }
        protectedPaths = paths
    }

    /// Returns `nil` when the item may be cleaned, otherwise the reason it must not be.
    public func check(_ item: URL, root: URL) -> SkipReason? {
        let name = item.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !item.path.contains("/../") else { return .outsideRoot }

        // Resolve the parent (not the item itself): moving a symlink moves the link, not its target.
        let realParent = Self.realPath(item.deletingLastPathComponent())
        let realRoot = Self.realPath(root)
        guard realParent == realRoot || realParent.hasPrefix(realRoot + "/") else { return .outsideRoot }

        let realItem = realParent == "/" ? "/" + name : realParent + "/" + name
        if protectedPaths.contains(realItem) { return .protectedPath }
        if protectedPaths.contains(where: { $0.hasPrefix(realItem + "/") }) { return .protectedPath }
        if Self.systemPrefixes.contains(where: { realItem == $0 || realItem.hasPrefix($0 + "/") }) {
            return .protectedPath
        }
        return nil
    }

    /// Canonical path with symlinks resolved and `/private` normalised, so `/var/...` and
    /// `/private/var/...` compare equal.
    static func realPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") { path = String(path.dropFirst("/private".count)) }
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
