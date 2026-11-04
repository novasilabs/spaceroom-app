// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A parsed rule path such as `~/Library/Caches/*`.
///
/// Patterns are intentionally limited: a literal root folder plus one leaf component,
/// which may contain `fnmatch` wildcards (`*`, `?`, `[...]`). Recursive `**` and
/// wildcards in the middle of a path are rejected, so a rule can never reach outside
/// the folder it names.
public struct PathPattern: Sendable, Hashable {
    public let raw: String
    public let isHomeRelative: Bool
    /// Literal components of the root folder (everything except the leaf).
    public let rootComponents: [String]
    public let leaf: String

    public var hasWildcard: Bool { Self.containsWildcard(leaf) }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case mustStartWithHomeOrSlash
        case invalidComponent(String)
        case wildcardOutsideLeaf(String)
        case recursiveWildcard
        case rootTooShallow
        case protectedRoot(String)

        public var description: String {
            switch self {
            case .mustStartWithHomeOrSlash: "must start with \"~/\" or \"/\""
            case .invalidComponent(let c): "invalid path component \"\(c)\""
            case .wildcardOutsideLeaf(let c): "wildcard only allowed in the last component (found in \"\(c)\")"
            case .recursiveWildcard: "\"**\" is not allowed"
            case .rootTooShallow: "root folder is too shallow"
            case .protectedRoot(let r): "root \"\(r)\" is a protected folder"
            }
        }
    }

    /// Folders directly under home that a rule root may never be.
    static let protectedHomeRoots: Set<String> = [
        "Applications", "Desktop", "Documents", "Downloads", "Library",
        "Movies", "Music", "Pictures", "Public",
    ]

    public init(_ raw: String) throws(ParseError) {
        self.raw = raw
        let body: Substring
        if raw.hasPrefix("~/") {
            isHomeRelative = true
            body = raw.dropFirst(2)
        } else if raw.hasPrefix("/") {
            isHomeRelative = false
            body = raw.dropFirst()
        } else {
            throw .mustStartWithHomeOrSlash
        }

        let components = body.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let leaf = components.last, !components.isEmpty else { throw .invalidComponent("") }
        for component in components {
            if component.isEmpty || component == "." || component == ".." {
                throw .invalidComponent(component)
            }
            if component.contains("**") { throw .recursiveWildcard }
        }
        let root = Array(components.dropLast())
        if let bad = root.first(where: Self.containsWildcard) { throw .wildcardOutsideLeaf(bad) }

        // Home rules need at least one root folder (e.g. ~/.Trash/*);
        // absolute rules need at least two (e.g. /Library/Caches/*).
        if isHomeRelative ? root.count < 1 : root.count < 2 { throw .rootTooShallow }
        if isHomeRelative, root.count == 1, Self.protectedHomeRoots.contains(root[0]) {
            throw .protectedRoot("~/" + root[0])
        }
        self.rootComponents = root
        self.leaf = leaf
    }

    public func rootURL(home: URL) -> URL {
        let base = isHomeRelative ? home : URL(fileURLWithPath: "/", isDirectory: true)
        return rootComponents.reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// The path this pattern "claims": the root for wildcard patterns, the exact path otherwise.
    /// A more general rule never takes an item that contains another rule's claim.
    public func claimURL(home: URL) -> URL {
        hasWildcard ? rootURL(home: home) : rootURL(home: home).appendingPathComponent(leaf)
    }

    /// Existing entries matching the pattern, excluding names matching `exclude`.
    public func expand(home: URL, exclude: [String] = [], fileManager: FileManager = .default) -> [URL] {
        let root = rootURL(home: home)
        let names: [String]
        if hasWildcard {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
            names = entries.filter { Self.matches($0, pattern: leaf) }
        } else {
            names = FileStat.exists(root.appendingPathComponent(leaf)) ? [leaf] : []
        }
        return names
            .filter { name in !exclude.contains { Self.matches(name, pattern: $0) } }
            .sorted()
            .map { root.appendingPathComponent($0) }
    }

    /// True when the folder to list exists but macOS refuses to read it (TCC / permissions).
    public func isAccessDenied(home: URL) -> Bool {
        let folder = hasWildcard ? rootURL(home: home) : rootURL(home: home).appendingPathComponent(leaf)
        guard FileStat.exists(folder) else { return false }
        let dir = opendir(folder.path)
        if let dir { closedir(dir); return false }
        return errno == EPERM || errno == EACCES
    }

    static func containsWildcard(_ s: String) -> Bool {
        s.contains { $0 == "*" || $0 == "?" || $0 == "[" }
    }

    static func matches(_ name: String, pattern: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}
