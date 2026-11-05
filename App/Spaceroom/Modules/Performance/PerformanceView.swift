// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// Performance: maintenance tasks with plain explanations, honest skip reasons and live status.
struct PerformanceView: View {
    @Bindable var model: PerformanceModel
    @Environment(AppModel.self) private var app

    private let module = SidebarModule.performance

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VStack(spacing: 2) {
                        ForEach(model.userTasks) { task in
                            TaskRow(task: task, isSelected: model.selection.contains(task.id),
                                    state: model.state(of: task), lastRun: model.lastRun[task.id],
                                    isLocked: model.isRunning) { model.toggle(task) }
                        }
                    }
                    .padding(6)
                    .glassSurface()
                    .entrance(0)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill").font(.caption)
                            Text("Needs admin rights").font(.headline)
                        }
                        Text("These change system-wide settings. They'll run once Spaceroom's privileged helper is installed; until then, nothing is done behind your back.")
                            .font(.caption).foregroundStyle(.textTertiary)
                        VStack(spacing: 2) {
                            ForEach(model.adminTasks) { task in
                                TaskRow(task: task, isSelected: false, state: .idle, lastRun: nil, isLocked: true) {}
                            }
                        }
                        .padding(6)
                        .glassSurface()
                    }
                    .entrance(1)

                    if app.status.uptime > 14 * 86_400 || ProcessInfo.processInfo.systemUptime > 14 * 86_400 {
                        restartHint.entrance(2)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.system(size: 22, weight: .bold))
                Text(model.lastMaintenance.map { String(localized: "Last maintenance \($0.formatted(.relative(presentation: .named)))") }
                     ?? String(localized: "No maintenance run yet"))
                    .font(.callout).foregroundStyle(.textSecondary)
            }
            Spacer()
        }
    }

    private var restartHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Mac hasn't restarted in over two weeks").font(.system(size: 13, weight: .semibold))
                Text("A restart applies updates and clears memory better than any task here.")
                    .font(.caption).foregroundStyle(.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(wash: .orange)
    }

    private var footer: some View {
        HStack {
            Text(model.isRunning ? String(localized: "Running maintenance…")
                 : model.selectedTasks.isEmpty ? String(localized: "Tick the tasks you want to run")
                 : String(localized: "\(model.selectedTasks.count) tasks selected"))
                .font(.callout).foregroundStyle(.textSecondary)
            Spacer()
            Button(model.isRunning ? "Running…" : "Run Selected") { model.runSelected() }
                .buttonStyle(FilledButtonStyle(tint: module.palette.accent))
                .disabled(model.selectedTasks.isEmpty || model.isRunning)
        }
    }
}

private struct TaskRow: View {
    let task: MaintenanceTask
    let isSelected: Bool
    let state: PerformanceModel.State
    let lastRun: Date?
    let isLocked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                IconSwap(isOn: isSelected, on: "checkmark.square.fill", off: task.requiresAdmin ? "lock.square" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? .white : .textTertiary)
                    .padding(.top, 2)
                GlassGlyph(symbol: task.symbol, tint: SidebarModule.performance.palette.accent, size: 30, isCompact: true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(task.title).font(.system(size: 13, weight: .semibold))
                        Pill(text: Text(estimateText), tint: .white)
                    }
                    Text(task.summary).font(.caption).foregroundStyle(.textSecondary)
                    Text("Helps when: \(task.helpsWhen)").font(.caption).foregroundStyle(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    statusLine
                }
                Spacer(minLength: 8)
                if !task.requiresAdmin {
                    Text(lastRun.map { String(localized: "Ran \($0.formatted(.relative(presentation: .named)))") }
                         ?? String(localized: "Never run"))
                        .font(.caption).foregroundStyle(.textTertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .contentShape(Rectangle())
            .opacity(task.requiresAdmin ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked || task.requiresAdmin)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var estimateText: String {
        switch task.estimate {
        case .seconds: String(localized: "~10 sec")
        case .minute: String(localized: "~1 min")
        case .minutes: String(localized: "a few min")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .idle:
            EmptyView()
        case .waiting:
            Label("Waiting", systemImage: "clock").font(.caption.weight(.medium)).foregroundStyle(.textSecondary)
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Running…").font(.caption.weight(.medium))
            }
        case .finished(.done(let note)):
            Label(note ?? String(localized: "Done"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(Color.hex(0x4FCB98))
        case .finished(.failed(let message)):
            Label(message, systemImage: "xmark.octagon.fill").font(.caption.weight(.medium)).foregroundStyle(.orange)
        case .finished(.skipped(let reason)):
            Label(skipText(reason), systemImage: "forward.fill").font(.caption.weight(.medium)).foregroundStyle(.textSecondary)
        }
    }

    private func skipText(_ reason: MaintenanceSkip) -> String {
        switch reason {
        case .needsAdmin: String(localized: "Skipped: needs admin rights")
        case .appRunning(let bundleID): String(localized: "Skipped: quit \(bundleID) first")
        case .unavailable: String(localized: "Skipped: not available on this macOS")
        }
    }
}
