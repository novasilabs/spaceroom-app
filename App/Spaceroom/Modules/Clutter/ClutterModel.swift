// SPDX-License-Identifier: GPL-3.0-or-later

import CoreServices
import Observation
import SpaceroomCore
import SwiftUI

/// My Clutter: large & old files, duplicates and installer downloads in the user's own files.
@MainActor
@Observable
final class ClutterModel {
    enum Phase: Equatable { case intro, scanning, results }
    enum Tab: Hashable { case large, duplicates, similar, installers }

    enum MinimumSize: Int64, CaseIterable, Identifiable {
        case mb50 = 50_000_000, mb100 = 100_000_000, mb500 = 500_000_000, gb1 = 1_000_000_000
        var id: Int64 { rawValue }
        var title: String { "≥ " + rawValue.bytesText }
    }

    enum Age: Int, CaseIterable, Identifiable {
        case any = 0, months6 = 182, year1 = 365, years2 = 730
        var id: Int { rawValue }
        var title: LocalizedStringResource {
            switch self {
            case .any: "Any age"
            case .months6: "Untouched 6+ months"
            case .year1: "Untouched 1+ year"
            case .years2: "Untouched 2+ years"
            }
        }
    }

    private unowned let app: AppModel

    private(set) var phase: Phase = .intro
    private(set) var scannedItems = 0
    private(set) var report: ClutterReport?
    private(set) var duplicates: [DuplicateGroup] = []
    private(set) var isFindingDuplicates = false
    private(set) var similarIndex: SimilarPhotoIndex?
    private(set) var similarGroups: [SimilarPhotoGroup] = []
    private(set) var isFindingSimilar = false
    private(set) var similarProgress: (done: Int, total: Int) = (0, 0)
    var strictness: SimilarPhotoFinder.Strictness = .similar {
        didSet { if let similarIndex { similarGroups = similarIndex.groups(threshold: strictness.threshold) } }
    }
    var tab: Tab = .large
    var minimumSize: MinimumSize = .mb100
    var age: Age = .any
    /// Ticks per tab: what's ticked for you in Installers or Duplicates never shows up (or gets
    /// removed) in Large & Old, where nothing is ticked for you.
    private var selections: [Tab: Set<String>] = [:]
    var selection: Set<String> {
        get { selections[tab] ?? [] }
        set { selections[tab] = newValue }
    }
    private(set) var isWorking = false
    private(set) var lastResult: (message: String, operationID: UUID?)?
    /// Files removed this session (hidden from the lists without rescanning).
    private var removedIDs: Set<String> = []

    /// Snapshot tour only: scan a fixture folder instead of the home folder.
    @ObservationIgnored var debugRoot: URL?
    @ObservationIgnored private var pendingItems = 0
    @ObservationIgnored private var lastPublish = Date.distantPast
    private var scanTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Scan

    func start() {
        guard phase != .scanning else { return }
        // A previous scan's duplicate and photo passes may still be running: they'd land later
        // and overwrite this scan's results.
        scanTask?.cancel()
        scannedItems = 0
        pendingItems = 0
        report = nil
        duplicates = []
        similarIndex = nil
        similarGroups = []
        selections = [:]
        removedIDs = []
        lastResult = nil
        withAnimation(Motion.phaseChange) { phase = .scanning }

        let (stream, continuation) = AsyncStream<Int>.makeStream()
        var config = ClutterScanConfig()
        if let debugRoot { config.roots = [debugRoot] }
        let scanner = ClutterScanner(config: config)
        scanTask = Task { [weak self] in
            let scan = Task.detached(priority: .userInitiated) {
                await scanner.scan { continuation.yield($0) }
            }
            let consume = Task { [weak self] in
                for await items in stream {
                    guard let self else { return }
                    self.pendingItems += items
                    if Date.now.timeIntervalSince(self.lastPublish) >= 0.25 {
                        self.scannedItems += self.pendingItems
                        self.pendingItems = 0
                        self.lastPublish = .now
                    }
                }
            }
            let result = await withTaskCancellationHandler {
                await scan.value
            } onCancel: {
                scan.cancel()
            }
            continuation.finish()
            await consume.value
            guard let self, !Task.isCancelled else { return }
            self.scannedItems += self.pendingItems
            self.report = result
            // Only installers that were downloaded (Downloads, Desktop) are ticked for you; a disk
            // image kept in Documents may be an encrypted vault.
            self.selections[.installers] = Set(result.installers.filter { Self.isLikelyAccidental($0) }.map(\.id))
            withAnimation(Motion.phaseChange) { self.phase = .results }
            await self.findDuplicates(in: result.duplicateCandidates)
            await self.findSimilar(in: result.photos)
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        withAnimation(Motion.phaseChange) { phase = .intro }
    }

    func newScan() {
        scanTask?.cancel()
        scanTask = nil
        withAnimation(Motion.phaseChange) { phase = .intro }
    }

    private func findDuplicates(in candidates: [ClutterFile]) async {
        isFindingDuplicates = true
        let groups = await Task.detached(priority: .utility) { DuplicateFinder.groups(from: candidates) }.value
        guard !Task.isCancelled else { return }
        duplicates = groups
        // Only obviously accidental copies are ticked for you (Downloads, Desktop). Copies inside
        // projects are often intentional (each project has its own assets), so those wait for you.
        // The copy to keep is never ticked.
        selections[.duplicates, default: []].formUnion(groups.flatMap(\.extras).filter { Self.isLikelyAccidental($0) }.map(\.id))
        isFindingDuplicates = false
    }

    /// Vision compares photos after the duplicate check. Nothing here is ticked for you:
    /// similar isn't identical, so you choose which ones go.
    private func findSimilar(in photos: [ClutterFile]) async {
        guard !Task.isCancelled else { return }
        isFindingSimilar = true
        similarProgress = (0, photos.filter(SimilarPhotoFinder.isPhoto).count)
        let (stream, continuation) = AsyncStream<(Int, Int)>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let listen = Task { [weak self] in
            for await value in stream { self?.similarProgress = value }
        }
        let index = await Task.detached(priority: .utility) {
            await SimilarPhotoFinder.index(photos, progress: { continuation.yield(($0, $1)) },
                                           isCancelled: { Task.isCancelled })
        }.value
        continuation.finish()
        await listen.value
        guard !Task.isCancelled else { return }
        similarIndex = index
        similarGroups = index.groups(threshold: strictness.threshold)
        isFindingSimilar = false
    }

    /// Groups without removed or ignored photos. If the best one is gone, the next best is kept,
    /// so a group can never be emptied from this tab.
    var visibleSimilar: [SimilarPhotoGroup] {
        similarGroups.compactMap { group in
            let remaining = group.photos.filter { isVisible($0.file) }
            return remaining.count > 1 ? SimilarPhotoGroup(photos: remaining) : nil
        }
    }

    var similarReclaimable: Int64 { visibleSimilar.reduce(0) { $0 + $1.reclaimable } }

    /// Ticks every photo except the best of each group.
    func tickAllButBest() {
        selection.formUnion(visibleSimilar.flatMap(\.others).map(\.id))
    }

    // MARK: Lists

    var largeFiles: [ClutterFile] {
        let cutoff = Date.now.addingTimeInterval(-TimeInterval(age.rawValue) * 86_400)
        return (report?.largeFiles ?? []).filter {
            isVisible($0) && $0.size >= minimumSize.rawValue && (age == .any || $0.modified < cutoff)
        }
    }

    var installers: [ClutterFile] { (report?.installers ?? []).filter { isVisible($0) } }

    private func isVisible(_ file: ClutterFile) -> Bool {
        !removedIDs.contains(file.id) && !app.ignoreList.ignores(file.url)
    }

    func ignore(_ file: ClutterFile) {
        app.ignore(.path(file.url))
        for key in selections.keys { selections[key]?.remove(file.id) }
    }

    /// Groups without removed or ignored files, with the copy to keep picked again from what's
    /// left: if the original keeper was removed elsewhere, another copy is kept, never none.
    var visibleDuplicates: [DuplicateGroup] {
        duplicates.compactMap { group in
            let remaining = group.files.filter { isVisible($0) }
            return remaining.count > 1 ? group.restricted(to: remaining) : nil
        }
    }

    /// Files ticked in the current tab. In Duplicates, the copy to keep is never included, even
    /// if it is ticked from another tab — removing from Duplicates must always leave one copy.
    var selectedInTab: [ClutterFile] {
        let files: [ClutterFile] = switch tab {
        case .large: largeFiles
        case .installers: installers
        case .duplicates: visibleDuplicates.flatMap(\.extras)
        case .similar: visibleSimilar.flatMap(\.others).map(\.file)
        }
        var seen = Set<String>()
        return files.filter { selection.contains($0.id) && seen.insert($0.id).inserted }
    }

    var selectedSize: Int64 { selectedInTab.reduce(0) { $0 + $1.size } }
    var duplicatesWaste: Int64 { visibleDuplicates.reduce(0) { $0 + $1.wasted } }
    var installersSize: Int64 { installers.reduce(0) { $0 + $1.size } }

    nonisolated static func isLikelyAccidental(_ file: ClutterFile) -> Bool {
        let path = file.url.path
        return path.contains("/Downloads/") || path.contains("/Desktop/")
    }

    /// Ticks every extra copy in Duplicates (never the copy to keep).
    func tickAllExtras() {
        selections[.duplicates, default: []].formUnion(visibleDuplicates.flatMap(\.extras).map(\.id))
    }

    func toggle(_ file: ClutterFile) {
        if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
    }

    /// "dl.google.com" for a downloaded file (Spotlight's "Where from").
    func downloadSource(of file: ClutterFile) -> String? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, file.url as CFURL),
              let sources = MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String] else { return nil }
        return sources.lazy.compactMap { URL(string: $0)?.host }.first
    }

    // MARK: Remove

    func removeSelected() {
        guard let store = app.store else { return }
        let files = selectedInTab
        guard !files.isEmpty else { return }
        isWorking = true
        Task {
            do {
                let outcome = try await ClutterRemover(store: store).remove(files)
                await app.refreshOperations()
                if let operation = outcome.operation {
                    removedIDs.formUnion(operation.items.map(\.originalPath))
                    for key in selections.keys { selections[key]?.subtract(operation.items.map(\.originalPath)) }
                    var message = String(localized: "Moved \(operation.totalSize.bytesText) to the Restore Center")
                    if !outcome.skipped.isEmpty { message += " " + String(localized: "(\(outcome.skipped.count) skipped)") }
                    lastResult = (message, operation.id)
                } else if let first = outcome.skipped.first {
                    lastResult = (String(localized: "Nothing was removed: \(first.reason.text)"), nil)
                }
            } catch {
                app.show(String(localized: "Couldn't remove files"), error)
            }
            isWorking = false
        }
    }

    func undoLast() {
        guard let id = lastResult?.operationID, let operation = app.operations.first(where: { $0.id == id }) else { return }
        Task {
            if await app.restoreAll(id) {
                removedIDs.subtract(operation.items.map(\.originalPath))
                lastResult = (String(localized: "Restored. Everything is back."), nil)
            }
        }
    }

    func dismissResult() { lastResult = nil }
}
