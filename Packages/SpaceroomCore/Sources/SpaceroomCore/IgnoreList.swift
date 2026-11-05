// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One thing the user never wants Spaceroom to clean, uninstall or move.
public struct IgnoreEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A file or folder, and everything inside it.
        case path
        /// An app's data everywhere (caches, leftovers…), by bundle ID.
        case app
        /// A whole cleaning category, by rule ID.
        case rule
    }

    public var kind: Kind
    /// Real (symlink-resolved) path, bundle ID or rule ID.
    public var value: String
    public var addedAt: Date

    public var id: String { "\(kind.rawValue):\(value)" }

    public init(kind: Kind, value: String, addedAt: Date = .now) {
        self.kind = kind
        self.value = kind == .path ? SafetyGuard.realPath(URL(fileURLWithPath: value)) : value
        // Whole seconds, so a saved and reloaded entry compares equal.
        self.addedAt = Date(timeIntervalSince1970: addedAt.timeIntervalSince1970.rounded(.down))
    }

    public static func path(_ url: URL) -> IgnoreEntry { IgnoreEntry(kind: .path, value: url.path) }
    public static func app(_ bundleID: String) -> IgnoreEntry { IgnoreEntry(kind: .app, value: bundleID) }
    public static func rule(_ id: String) -> IgnoreEntry { IgnoreEntry(kind: .rule, value: id) }
}

/// The user's ignore list. Every scan marks matches as ignored, and the Restore Center refuses to
/// move them, so nothing on the list can be removed by any module.
public struct IgnoreList: Codable, Hashable, Sendable {
    public private(set) var entries: [IgnoreEntry]

    public init(entries: [IgnoreEntry] = []) {
        self.entries = []
        for entry in entries { add(entry) }
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func contains(_ entry: IgnoreEntry) -> Bool { entries.contains { $0.id == entry.id } }

    public mutating func add(_ entry: IgnoreEntry) {
        guard !contains(entry) else { return }
        entries.append(entry)
    }

    public mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    private var paths: [String] { entries.filter { $0.kind == .path }.map(\.value) }

    /// The ignored path that protects `url`: `url` is it, is inside it, or contains it (cleaning a
    /// folder must never take an ignored file along).
    public func protectingPath(for url: URL) -> String? {
        let real = SafetyGuard.realPath(url)
        return paths.first { path in
            real == path || real.hasPrefix(path + "/") || path.hasPrefix(real + "/")
        }
    }

    public func ignores(_ url: URL) -> Bool { protectingPath(for: url) != nil }

    public func ignoresApp(_ bundleID: String) -> Bool {
        entries.contains { $0.kind == .app && $0.value.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    public func ignoresRule(_ id: String) -> Bool {
        entries.contains { $0.kind == .rule && $0.value == id }
    }

    /// App data is usually named after its bundle ID ("com.example.app", "com.example.app.helper",
    /// "com.example.app.savedState", "group.com.example.app").
    public func ignoresItem(named name: String) -> Bool {
        entries.contains { entry in
            guard entry.kind == .app else { return false }
            let id = entry.value.lowercased(), name = name.lowercased()
            return name == id || name.hasPrefix(id + ".") || name == "group." + id || name.hasSuffix("." + id)
        }
    }

    /// Everything that makes `url` off-limits: its path, or an ignored app's data by name.
    public func ignoresItem(at url: URL) -> Bool {
        ignores(url) || ignoresItem(named: url.lastPathComponent)
    }
}

/// `ignore.json` next to the Restore Center. Fail-closed: a file that exists but can't be read
/// throws, and the caller must then refuse to clean anything.
public enum IgnoreListFile {
    public static func url(in directory: URL) -> URL { directory.appendingPathComponent("ignore.json") }

    public static func load(directory: URL = RestoreStore.defaultDirectory) throws -> IgnoreList {
        let file = url(in: directory)
        guard FileManager.default.fileExists(atPath: file.path) else { return IgnoreList() }
        return try decoder.decode(IgnoreList.self, from: Data(contentsOf: file))
    }

    public static func save(_ list: IgnoreList, directory: URL = RestoreStore.defaultDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(list).write(to: url(in: directory), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
