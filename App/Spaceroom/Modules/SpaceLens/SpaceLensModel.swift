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

    func drill(into node: DiskNode) {
        guard node.kind == .folder, !node.children.isEmpty else { return }
        hoveredID = nil
        path.append(node)
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
}
