// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An item that was moved out of its original place by a clean operation.
public struct QuarantinedItem: Codable, Sendable, Identifiable, Hashable {
    public enum Storage: String, Codable, Sendable {
        /// Inside Spaceroom's quarantine folder (same volume, instant rename).
        case quarantine
        /// In the item's volume Trash (cross-volume items; restorable from Finder too).
        case trash
    }

    public enum State: Codable, Sendable, Hashable {
        case stored
        case restored(at: Date, path: String)
        /// Permanently removed (expired or "Delete now"). Trash-stored items are left in the Trash.
        case purged(at: Date)
    }

    public let id: UUID
    public let originalPath: String
    public let storedPath: String
    public let storage: Storage
    public let ruleID: String
    public let size: Int64
    public let isDirectory: Bool
    public internal(set) var state: State

    public var name: String { (originalPath as NSString).lastPathComponent }
    public var isStored: Bool { state == .stored }
}

/// One clean operation: a card in the Restore Center timeline.
public struct OperationRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let date: Date
    /// Module that ran it, e.g. "cleanup".
    public let module: String
    public internal(set) var items: [QuarantinedItem]

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var storedItems: [QuarantinedItem] { items.filter(\.isStored) }
    public var storedSize: Int64 { storedItems.reduce(0) { $0 + $1.size } }
    public var hasStoredItems: Bool { items.contains(where: \.isStored) }

    public func expiryDate(retentionDays: Int) -> Date {
        date.addingTimeInterval(TimeInterval(retentionDays) * 86_400)
    }
}

public struct PlannedMove: Sendable {
    public let url: URL
    public let ruleID: String
    public let size: Int64
    public let isDirectory: Bool

    public init(url: URL, ruleID: String, size: Int64, isDirectory: Bool) {
        self.url = url
        self.ruleID = ruleID
        self.size = size
        self.isDirectory = isDirectory
    }
}

public struct MoveFailure: Sendable, Hashable {
    public let path: String
    public let reason: SkipReason
}

public enum RestoreOutcome: Sendable, Hashable {
    case restored(itemID: UUID, path: String)
    /// Restored next to the original because something new now exists at the original path.
    case restoredRenamed(itemID: UUID, path: String)
    case missing(itemID: UUID)
    case failed(itemID: UUID, message: String)
}

public enum RestoreStoreError: Error, CustomStringConvertible {
    case unreadableIndex(URL, underlying: String)
    case operationNotFound(UUID)

    public var description: String {
        switch self {
        case .unreadableIndex(let url, let underlying): "Restore Center index at \(url.path) is unreadable: \(underlying)"
        case .operationNotFound(let id): "Operation \(id) not found"
        }
    }
}

/// Owns the quarantine folder and its index. All cleaning goes through here so everything is undoable.
///
/// Layout: `<directory>/Quarantine/<operation-id>/<n>-<name>` plus `<directory>/operations.json`.
public actor RestoreStore {
    public let directory: URL
    private var records: [OperationRecord]
    private let fileManager = FileManager.default

    var indexURL: URL { directory.appendingPathComponent("operations.json") }
    var quarantineRoot: URL { directory.appendingPathComponent("Quarantine", isDirectory: true) }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spaceroom", isDirectory: true)
    }

    /// Loads the index. Throws (fail-closed) if an existing index can't be read, so callers
    /// never overwrite history they couldn't parse.
    public init(directory: URL = RestoreStore.defaultDirectory) throws {
        self.directory = directory
        let index = directory.appendingPathComponent("operations.json")
        if FileManager.default.fileExists(atPath: index.path) {
            do {
                records = try Self.decoder.decode([OperationRecord].self, from: Data(contentsOf: index))
            } catch {
                throw RestoreStoreError.unreadableIndex(index, underlying: String(describing: error))
            }
        } else {
            records = []
        }
    }

    /// Newest first.
    public var operations: [OperationRecord] { records.sorted { $0.date > $1.date } }

    public var storedSize: Int64 { records.reduce(0) { $0 + $1.storedSize } }

    public func operation(_ id: UUID) -> OperationRecord? { records.first { $0.id == id } }

    // MARK: Quarantine

    /// Moves items out of place. Items that fail are reported, the rest still move.
    /// Returns `nil` for the record when nothing moved.
    public func quarantine(_ moves: [PlannedMove], module: String, now: Date = .now)
        throws -> (record: OperationRecord?, failures: [MoveFailure])
    {
        let opID = UUID()
        let opFolder = quarantineRoot.appendingPathComponent(opID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: opFolder, withIntermediateDirectories: true)
        let quarantineDevice = FileStat.device(of: opFolder)

        var items: [QuarantinedItem] = []
        var failures: [MoveFailure] = []

        for (index, move) in moves.enumerated() {
            do {
                let storedURL: URL
                let storage: QuarantinedItem.Storage
                if let device = FileStat.device(of: move.url), device == quarantineDevice {
                    storedURL = opFolder.appendingPathComponent("\(index)-\(move.url.lastPathComponent)")
                    try fileManager.moveItem(at: move.url, to: storedURL)
                    storage = .quarantine
                } else {
                    var resulting: NSURL?
                    try fileManager.trashItem(at: move.url, resultingItemURL: &resulting)
                    guard let url = resulting as URL? else { throw CocoaError(.fileWriteUnknown) }
                    storedURL = url
                    storage = .trash
                }
                items.append(QuarantinedItem(
                    id: UUID(), originalPath: move.url.path, storedPath: storedURL.path, storage: storage,
                    ruleID: move.ruleID, size: move.size, isDirectory: move.isDirectory, state: .stored
                ))
            } catch {
                failures.append(MoveFailure(path: move.url.path, reason: Self.reason(for: error)))
            }
        }

        guard !items.isEmpty else {
            try? fileManager.removeItem(at: opFolder)
            return (nil, failures)
        }
        let record = OperationRecord(id: opID, date: now, module: module, items: items)
        records.append(record)
        try save()
        return (record, failures)
    }

    // MARK: Restore

    public func restore(_ itemIDs: Set<UUID>, in operationID: UUID, now: Date = .now) throws -> [RestoreOutcome] {
        guard let opIndex = records.firstIndex(where: { $0.id == operationID }) else {
            throw RestoreStoreError.operationNotFound(operationID)
        }
        var outcomes: [RestoreOutcome] = []
        for itemIndex in records[opIndex].items.indices {
            let item = records[opIndex].items[itemIndex]
            guard itemIDs.contains(item.id), item.isStored else { continue }
            let stored = URL(fileURLWithPath: item.storedPath)
            guard FileStat.exists(stored) else {
                outcomes.append(.missing(itemID: item.id))
                continue
            }
            let original = URL(fileURLWithPath: item.originalPath)
            let destination = Self.freeDestination(for: original, isDirectory: item.isDirectory)
            do {
                try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: stored, to: destination)
                records[opIndex].items[itemIndex].state = .restored(at: now, path: destination.path)
                outcomes.append(destination == original
                    ? .restored(itemID: item.id, path: destination.path)
                    : .restoredRenamed(itemID: item.id, path: destination.path))
            } catch {
                outcomes.append(.failed(itemID: item.id, message: error.localizedDescription))
            }
        }
        try save()
        removeEmptyOperationFolder(operationID)
        return outcomes
    }

    public func restoreAll(in operationID: UUID, now: Date = .now) throws -> [RestoreOutcome] {
        guard let record = operation(operationID) else { throw RestoreStoreError.operationNotFound(operationID) }
        return try restore(Set(record.storedItems.map(\.id)), in: operationID, now: now)
    }

    // MARK: Purge

    /// Permanently deletes an operation's quarantined items ("Delete now"). Returns bytes freed.
    @discardableResult
    public func purge(_ operationID: UUID, now: Date = .now) throws -> Int64 {
        guard let opIndex = records.firstIndex(where: { $0.id == operationID }) else {
            throw RestoreStoreError.operationNotFound(operationID)
        }
        var freed: Int64 = 0
        for itemIndex in records[opIndex].items.indices where records[opIndex].items[itemIndex].isStored {
            let item = records[opIndex].items[itemIndex]
            if item.storage == .quarantine {
                let url = URL(fileURLWithPath: item.storedPath)
                if FileStat.exists(url) { try? fileManager.removeItem(at: url) }
                freed += item.size
            }
            records[opIndex].items[itemIndex].state = .purged(at: now)
        }
        try save()
        removeEmptyOperationFolder(operationID, force: true)
        return freed
    }

    /// Purges operations older than the retention period. Returns bytes freed.
    @discardableResult
    public func purgeExpired(retentionDays: Int, now: Date = .now) throws -> Int64 {
        let expired = records.filter { $0.hasStoredItems && $0.expiryDate(retentionDays: retentionDays) <= now }
        var freed: Int64 = 0
        for record in expired { freed += try purge(record.id, now: now) }
        return freed
    }

    // MARK: Private

    private func save() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(records).write(to: indexURL, options: .atomic)
    }

    private func removeEmptyOperationFolder(_ id: UUID, force: Bool = false) {
        let folder = quarantineRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let contents = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        if force || contents.isEmpty { try? fileManager.removeItem(at: folder) }
    }

    /// `name`, `name (restored)`, `name (restored 2)`… — first path that doesn't exist.
    /// Folders keep their full name (`com.example (restored)`); files keep their extension
    /// (`report (restored).log`).
    static func freeDestination(for original: URL, isDirectory: Bool) -> URL {
        guard FileStat.exists(original) else { return original }
        let folder = original.deletingLastPathComponent()
        let ext = isDirectory ? "" : original.pathExtension
        let base = ext.isEmpty ? original.lastPathComponent : original.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let suffix = n == 1 ? " (restored)" : " (restored \(n))"
            let name = base + suffix + (ext.isEmpty ? "" : "." + ext)
            let candidate = folder.appendingPathComponent(name)
            if !FileStat.exists(candidate) { return candidate }
            n += 1
        }
    }

    static func reason(for error: any Error) -> SkipReason {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain,
           ns.code == CocoaError.fileWriteNoPermission.rawValue || ns.code == CocoaError.fileReadNoPermission.rawValue {
            return .notPermitted
        }
        if let posix = ns.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain,
           posix.code == Int(EPERM) || posix.code == Int(EACCES) {
            return .notPermitted
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == CocoaError.fileNoSuchFile.rawValue { return .missing }
        return .moveFailed(ns.localizedDescription)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
