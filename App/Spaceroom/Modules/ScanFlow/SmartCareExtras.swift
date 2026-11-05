// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import SpaceroomCore
import SwiftUI

/// The Protection, Speed and Applications tiles of Smart Care. They are checked alongside the
/// junk scan and acted on together with Clean — only for what is safe in one click:
/// likely-harmful files and app leftovers move to the Restore Center, quick maintenance runs.
@MainActor
@Observable
final class SmartCareExtras {
    enum Area: String, CaseIterable, Identifiable {
        case protection, speed, applications
        var id: String { rawValue }

        var module: SidebarModule {
            switch self {
            case .protection: .protection
            case .speed: .performance
            case .applications: .applications
            }
        }
    }

    /// What the last Clean did beyond junk, for the done screen.
    struct Outcome {
        var movedThreats = 0
        var ranTasks = 0
        var removedLeftovers: Int64 = 0
        var isEmpty: Bool { movedThreats == 0 && ranTasks == 0 && removedLeftovers == 0 }
    }

    private unowned let app: AppModel

    var enabled: Set<Area> = Set(Area.allCases)
    private(set) var isCheckingProtection = false
    private(set) var threats: [ThreatFinding] = []
    private(set) var lastOutcome: Outcome?
    @ObservationIgnored private var protectionTask: Task<Void, Never>?
    /// Snapshot tour only: check a fixture folder instead of the real Downloads and Desktop.
    @ObservationIgnored var debugRoots: [URL]?

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Checking

    /// Starts every check. Called when a Smart Care scan starts.
    func check() {
        lastOutcome = nil
        app.startup.loadIfNeeded()
        app.applications.loadIfNeeded()
        protectionTask?.cancel()
        isCheckingProtection = true
        threats = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Where downloaded files land; Documents is left to the full Protection scan.
        let roots = ["Downloads", "Desktop", "Applications"].map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let scanRoots = debugRoots ?? roots
        protectionTask = Task {
            let report = await Task.detached(priority: .utility) { ProtectionScanner().scan(scanRoots) }.value
            guard !Task.isCancelled else { return }
            threats = report.findings
            isCheckingProtection = false
        }
    }

    func cancel() {
        protectionTask?.cancel()
        isCheckingProtection = false
    }

    // MARK: What each tile offers

    /// Findings not on the ignore list.
    var visibleThreats: [ThreatFinding] { threats.filter { !app.ignoreList.ignores($0.url) } }
    /// Only clear cases are handled in one click; the rest wait in Protection.
    var harmfulThreats: [ThreatFinding] { visibleThreats.filter { $0.severity == .high } }
    var dueTasks: [MaintenanceTask] { app.performance.dueTasks }
    var startupAttention: Int { app.startup.hasLoaded ? app.startup.attention.count : 0 }
    var leftovers: [Leftover] { app.applications.hasLoaded ? app.applications.selectedOrphanItems : [] }
    var leftoversSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }

    func isReady(_ area: Area) -> Bool {
        switch area {
        case .protection: !isCheckingProtection
        case .speed: true
        case .applications: app.applications.hasLoaded
        }
    }

    /// Whether Clean would do anything for this tile.
    func hasAction(_ area: Area) -> Bool {
        switch area {
        case .protection: !harmfulThreats.isEmpty
        case .speed: !dueTasks.isEmpty
        case .applications: !leftovers.isEmpty
        }
    }

    func isSelected(_ area: Area) -> Bool { enabled.contains(area) && hasAction(area) }

    var hasSelectedAction: Bool { Area.allCases.contains { isSelected($0) } }
    var hasAnyFinding: Bool { Area.allCases.contains { hasAction($0) } || startupAttention > 0 || !visibleThreats.isEmpty }

    func toggle(_ area: Area) {
        if enabled.contains(area) { enabled.remove(area) } else { enabled.insert(area) }
    }

    // MARK: Acting

    /// Runs the ticked tiles after the junk clean. Everything removed goes to the Restore Center.
    func run() async -> Outcome {
        var outcome = Outcome()
        guard let store = app.store, app.cleaningBlockedReason == nil else { return outcome }
        if isSelected(.protection) {
            if let result = try? await ThreatRemover(store: store).remove(harmfulThreats), let operation = result.operation {
                outcome.movedThreats = operation.items.count
                let moved = Set(operation.items.map(\.originalPath))
                threats.removeAll { moved.contains($0.url.path) }
            }
        }
        if isSelected(.applications) {
            let items = leftovers
            if let result = try? await Uninstaller(store: store).remove(app: nil, leftovers: items,
                                                                        runningBundleIDs: AppNames.runningBundleIDs()),
               let operation = result.operation {
                outcome.removedLeftovers = operation.totalSize
            }
            app.applications.reload()
        }
        if isSelected(.speed) {
            outcome.ranTasks = await app.performance.run(dueTasks)
        }
        await app.refreshOperations()
        lastOutcome = outcome
        return outcome
    }
}
