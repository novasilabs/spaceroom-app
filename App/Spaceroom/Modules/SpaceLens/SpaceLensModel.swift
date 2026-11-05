// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import SwiftUI

/// Space Lens state: what to scan, live progress, the finished map and where the user is in it.
@MainActor
@Observable
final class SpaceLensModel {
    enum Phase: Equatable { case intro, scanning, results }
    enum ChartStyle: String { case sunburst, treemap }

    /// Remembered between launches (except during the snapshot tour, which never saves settings).
    var chartStyle: ChartStyle = ChartStyle(rawValue: UserDefaults.standard.string(forKey: "spaceLensChart") ?? "") ?? .sunburst {
        didSet {
            guard ProcessInfo.processInfo.environment["SPACEROOM_SNAPSHOT_DIR"] == nil else { return }
            UserDefaults.standard.set(chartStyle.rawValue, forKey: "spaceLensChart")
        }
    }

    struct Target: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let url: URL
        /// The volume, for "used vs. scanned" (the gap is system data and hidden items).
        let volume: VolumeInfo?
    }

    private unowned let app: AppModel

    private(set) var phase: Phase = .intro
    private(set) var targets: [Target] = []
    var selectedTargetID: String = "home"

    private(set) var scannedItems = 0
    private(set) var scannedBytes: Int64 = 0
    private(set) var scanStarted: Date?
    private(set) var scanDuration: TimeInterval?
    /// Top-level folders finished so far (the map grows from these while scanning).
    private(set) var liveChildren: [DiskNode] = []
    private(set) var root: DiskNode?
    /// Drill-down path below the root (empty = at the root).
    private(set) var path: [DiskNode] = []
    var hoveredID: String?

    /// Items ticked for removal, by path. Kept while drilling around, like a shopping basket.
    private(set) var selection: [String: DiskNode] = [:]
    private(set) var isRemoving = false
    private(set) var lastResult: (message: String, operationID: UUID?)?
    /// The map before the last removal, so Undo can put it back without a rescan.
    @ObservationIgnored private var rootBeforeRemoval: DiskNode?

    private var scanTask: Task<Void, Never>?
    private var scannedTarget: Target?
    // Progress arrives thousands of times a minute; publish it at most 4× a second.
    @ObservationIgnored private var pendingItems = 0
    @ObservationIgnored private var pendingBytes: Int64 = 0
    @ObservationIgnored private var lastPublish = Date.distantPast

    init(app: AppModel) {
        self.app = app
        refreshTargets()
    }

    // MARK: Targets

    func refreshTargets() {
        var list: [Target] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let rootVolume = Volumes.root()
        list.append(Target(id: "home", name: String(localized: "Home Folder"),
                           detail: home.path, symbol: "house", url: home, volume: nil))
        if let rootVolume {
            // On APFS the user's data lives on the Data volume, firmlinked into "/".
            let data = URL(fileURLWithPath: "/System/Volumes/Data")
            let url = FileManager.default.fileExists(atPath: data.path) ? data : URL(fileURLWithPath: "/")
            list.append(Target(id: "startup", name: rootVolume.name,
                               detail: String(localized: "\(rootVolume.usedBytes.bytesText) used of \(rootVolume.totalBytes.bytesText)"),
                               symbol: "internaldrive", url: url, volume: rootVolume))
        }
        for volume in Volumes.mounted() where !volume.isRoot {
            list.append(Target(id: volume.id, name: volume.name,
                               detail: String(localized: "\(volume.usedBytes.bytesText) used of \(volume.totalBytes.bytesText)"),
                               symbol: "externaldrive", url: volume.url, volume: volume))
        }
        targets = list
        if !targets.contains(where: { $0.id == selectedTargetID }) { selectedTargetID = "home" }
    }

    var selectedTarget: Target? { targets.first { $0.id == selectedTargetID } }

    #if DEBUG
    /// Snapshot tour: scan a small folder instead of the whole home folder.
    func useDebugTarget(_ url: URL) {
        targets.append(Target(id: "debug", name: url.lastPathComponent, detail: url.path, symbol: "folder",
                              url: url, volume: nil))
        selectedTargetID = "debug"
    }
    #endif

    // MARK: Scan

    func start() {
        guard let target = selectedTarget, phase != .scanning else { return }
        scannedTarget = target
        scannedItems = 0
        scannedBytes = 0
        pendingItems = 0
        pendingBytes = 0
        liveChildren = []
        root = nil
        path = []
        hoveredID = nil
        selection = [:]
        lastResult = nil
        rootBeforeRemoval = nil
        scanDuration = nil
        scanStarted = .now
        withAnimation(Motion.phaseChange) { phase = .scanning }

        let stream = DiskScanner().events(for: target.url)
        scanTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .progress(let items, let bytes):
                    self.pendingItems += items
                    self.pendingBytes += bytes
                    if Date.now.timeIntervalSince(self.lastPublish) >= 0.25 { self.publishProgress() }
                case .topLevelFinished(let node):
                    self.liveChildren.append(node)
                    self.liveChildren.sort { $0.size > $1.size }
                case .finished(let node):
                    self.publishProgress()
                    self.root = node
                    self.scanDuration = self.scanStarted.map { Date.now.timeIntervalSince($0) }
                    withAnimation(Motion.phaseChange) { self.phase = .results }
                }
            }
        }
    }

    private func publishProgress() {
        scannedItems += pendingItems
        scannedBytes += pendingBytes
        pendingItems = 0
        pendingBytes = 0
        lastPublish = .now
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        // Keep what's finished so far so the user can still explore it.
        if !liveChildren.isEmpty {
            root = provisionalRoot
            scanDuration = scanStarted.map { Date.now.timeIntervalSince($0) }
            withAnimation(Motion.phaseChange) { phase = .results }
        } else {
            withAnimation(Motion.phaseChange) { phase = .intro }
        }
    }

    func newScan() {
        refreshTargets()
        withAnimation(Motion.phaseChange) { phase = .intro }
    }

    /// Root built from finished top-level folders while the scan runs.
    private var provisionalRoot: DiskNode? {
        guard let target = scannedTarget else { return nil }
        let size = liveChildren.reduce(0) { $0 + $1.size }
        return DiskNode(name: target.name, path: target.url.path, kind: .folder, size: size,
                        itemCount: liveChildren.reduce(0) { $0 + $1.itemCount }, children: liveChildren, isPartial: true)
    }

    // MARK: Navigation

    /// The folder the chart and list show.
    var current: DiskNode? {
        if let last = path.last { return last }
        return root ?? provisionalRoot
    }

    /// Root first, then each drilled-into folder.
    var breadcrumb: [DiskNode] {
        guard let base = root ?? provisionalRoot else { return [] }
        return [base] + path
    }

    var displayName: String { scannedTarget?.name ?? "" }

    /// Opens `node` when it's inside the folder on screen. Clicking an outer ring adds the
    /// folders in between, so the breadcrumb stays a real path. A tap on the chart that is
    /// still animating out (a fast double-click) names a folder that isn't inside the current one
    /// any more and is ignored, instead of opening the same folder twice.
    func drill(into node: DiskNode) {
        guard node.isContainer, let current, let chain = Self.chain(from: current, to: node) else { return }
        hoveredID = nil
        path.append(contentsOf: chain)
    }

    /// The folders below `folder` down to and including `target`, or nil when `target` isn't
    /// inside `folder`. Only follows children whose path contains the target's, so a miss costs
    /// one level of children rather than a walk of the whole tree.
    static func chain(from folder: DiskNode, to target: DiskNode) -> [DiskNode]? {
        for child in folder.children {
            if child.id == target.id { return [child] }
            let prefix = child.path.hasSuffix("/") ? child.path : child.path + "/"
            guard child.isContainer, target.path.hasPrefix(prefix) else { continue }
            if let rest = chain(from: child, to: target) { return [child] + rest }
        }
        return nil
    }

    func goUp() {
        guard !path.isEmpty else { return }
        hoveredID = nil
        path.removeLast()
    }

    func go(toBreadcrumb index: Int) {
        hoveredID = nil
        path = Array(path.prefix(index))
    }

    // MARK: Facts

    /// Used space the scan couldn't see: system files, snapshots, other users, protected folders.
    var hiddenBytes: Int64? {
        guard path.isEmpty, phase == .results, let volume = scannedTarget?.volume, let root else { return nil }
        let gap = volume.usedBytes - root.size
        return gap > 1_000_000_000 ? gap : nil
    }

    var isPartial: Bool { (root ?? provisionalRoot)?.isPartial ?? false }

    func reveal(_ node: DiskNode) { Finder.reveal(node.url) }

    func copyPath(_ node: DiskNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    // MARK: Selection and removal

    private var policy: LensRemovalPolicy? {
        app.store.map { LensRemovalPolicy(ownData: $0.directory) }
    }

    /// Whether `node` can be ticked. Only finished scans can remove anything.
    func verdict(for node: DiskNode) -> LensVerdict {
        guard let policy else { return .spaceroomData }
        return policy.verdict(for: node)
    }

    var canSelect: Bool { phase == .results && app.cleaningBlockedReason == nil && !isRemoving }

    func isSelected(_ node: DiskNode) -> Bool { selection[node.path] != nil }

    /// Ticked because a folder above it is ticked (removing the folder takes it along).
    func isCoveredBySelection(_ node: DiskNode) -> Bool {
        selection.keys.contains { node.path.hasPrefix($0 + "/") }
    }

    func toggle(_ node: DiskNode) {
        guard canSelect, verdict(for: node) == .allowed, !isCoveredBySelection(node) else { return }
        if selection.removeValue(forKey: node.path) == nil {
            // Ticking a folder replaces anything already ticked inside it.
            for key in selection.keys where key.hasPrefix(node.path + "/") { selection.removeValue(forKey: key) }
            selection[node.path] = node
        }
    }

    func clearSelection() { selection = [:] }

    var selectedNodes: [DiskNode] { selection.values.sorted { $0.size > $1.size } }
    var selectedSize: Int64 { selection.values.reduce(0) { $0 + $1.size } }

    func removeSelected() {
        guard let store = app.store, let root, canSelect else { return }
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        isRemoving = true
        Task {
            do {
                let outcome = try await LensRemover(store: store).remove(nodes)
                await app.refreshOperations()
                if let operation = outcome.operation {
                    // The store records canonical paths; map them back to the paths on the map.
                    let moved = Set(operation.items.map(\.originalPath))
                    let removedPaths = Set(nodes.map(\.path).filter {
                        moved.contains(LensRemovalPolicy.canonical(URL(fileURLWithPath: $0)))
                    })
                    rootBeforeRemoval = root
                    apply(root.removing(paths: removedPaths))
                    for path in removedPaths { selection.removeValue(forKey: path) }
                    var message = String(localized: "Moved \(operation.totalSize.bytesText) to the Restore Center")
                    if !outcome.skipped.isEmpty { message += " " + String(localized: "(\(outcome.skipped.count) skipped)") }
                    lastResult = (message, operation.id)
                } else if let first = outcome.skipped.first {
                    lastResult = (String(localized: "Nothing was removed: \(first.reason.text)"), nil)
                }
            } catch {
                app.show(String(localized: "Couldn't remove files"), error)
            }
            isRemoving = false
        }
    }

    func undoLast() {
        guard let id = lastResult?.operationID else { return }
        Task {
            if await app.restoreAll(id) {
                if let before = rootBeforeRemoval { apply(before) }
                rootBeforeRemoval = nil
                lastResult = (String(localized: "Restored. Everything is back."), nil)
            }
        }
    }

    func dismissResult() { lastResult = nil }

    /// Swaps in an updated tree and keeps the user in the same folder (or the nearest one that
    /// still exists).
    private func apply(_ newRoot: DiskNode) {
        var newPath: [DiskNode] = []
        var parent = newRoot
        for old in path {
            guard let match = parent.children.first(where: { $0.id == old.id }), match.isContainer else { break }
            newPath.append(match)
            parent = match
        }
        hoveredID = nil
        withAnimation(Easing.out(0.22)) {
            root = newRoot
            path = newPath
        }
    }
}
