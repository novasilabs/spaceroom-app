// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SpaceroomCore
import SwiftUI

/// Performance: maintenance tasks, when they last ran, and running a chosen set one after another.
@MainActor
@Observable
final class PerformanceModel {
    enum State: Equatable {
        case idle
        case waiting
        case running
        case finished(MaintenanceOutcome)
    }

    let tasks = MaintenanceCatalog.all
    var selection: Set<String>
    private(set) var states: [String: State] = [:]
    private(set) var lastRun: [String: Date]
    private(set) var isRunning = false

    private static let lastRunKey = "performance.lastRun"
    /// Quick, harmless tasks worth suggesting when they haven't run for a month.
    private static let suggested: Set<String> = ["quicklook", "launchservices", "fonts"]

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.lastRunKey) as? [String: Date] ?? [:]
        lastRun = stored
        let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
        selection = Set(MaintenanceCatalog.all.filter { task in
            Self.suggested.contains(task.id) && (stored[task.id] ?? .distantPast) < monthAgo
        }.map(\.id))
    }

    var userTasks: [MaintenanceTask] { tasks.filter { !$0.requiresAdmin } }
    var adminTasks: [MaintenanceTask] { tasks.filter(\.requiresAdmin) }
    var selectedTasks: [MaintenanceTask] { userTasks.filter { selection.contains($0.id) } }

    var lastMaintenance: Date? { lastRun.values.max() }

    func state(of task: MaintenanceTask) -> State { states[task.id] ?? .idle }

    func toggle(_ task: MaintenanceTask) {
        guard !task.requiresAdmin, !isRunning else { return }
        if selection.contains(task.id) { selection.remove(task.id) } else { selection.insert(task.id) }
    }

    /// Runs the selected tasks one after another, off the main thread.
    func runSelected() {
        let queue = selectedTasks
        guard !queue.isEmpty, !isRunning else { return }
        isRunning = true
        for task in queue { states[task.id] = .waiting }
        let running = AppNames.runningBundleIDs()
        Task {
            for task in queue {
                states[task.id] = .running
                let outcome = await Task.detached(priority: .userInitiated) {
                    MaintenanceRunner().run(task, runningBundleIDs: running)
                }.value
                states[task.id] = .finished(outcome)
                if case .done = outcome {
                    lastRun[task.id] = .now
                    UserDefaults.standard.set(lastRun, forKey: Self.lastRunKey)
                    selection.remove(task.id)
                }
            }
            isRunning = false
        }
    }
}
