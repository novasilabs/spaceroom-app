// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// Automations: "when → do" rules that keep the Mac tidy unattended, with suggestions and a run history.
struct AutomationsView: View {
    @Bindable var model: AutomationsModel
    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar
    @State private var editing: Automation?
    @State private var deleting: Automation?

    private let module = SidebarModule.automations

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let error = model.storeError {
                        notice(symbol: "exclamationmark.triangle", tint: .orange,
                               title: String(localized: "Automations can't be loaded"),
                               detail: String(localized: "The saved file couldn't be read, so nothing runs and nothing is overwritten. \(error)"))
                    } else {
                        if !menuBar.opensAtLogin || !AppDelegate.keepsRunningInMenuBar { runsWhileOpenCard.entrance(0) }
                        if !model.automations.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(model.automations) { automation in
                                    AutomationRow(model: model, automation: automation,
                                                  onEdit: { editing = automation }, onDelete: { deleting = automation })
                                }
                            }
                            .padding(6)
                            .glassSurface()
                            .entrance(1)
                        }
                        if !model.suggestions.isEmpty { suggestions.entrance(2) }
                        if !model.history.isEmpty { history.entrance(3) }
                    }
                }
                .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 16)
            }
            .scrollIndicators(.never)
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .onAppear { menuBar.refreshLoginItemStatus() }
        .sheet(item: $editing) { automation in
            AutomationEditor(original: automation, isNew: !model.automations.contains { $0.id == automation.id },
                             retentionDays: app.retentionDays,
                             onSave: { saved in
                                 model.save(saved)
                                 editing = nil
                             },
                             onCancel: { editing = nil })
        }
        .sheet(item: $deleting) { automation in
            ConfirmSheet(symbol: "trash", title: String(localized: "Delete this automation?"),
                         message: "\(automation.trigger.summary): \(automation.action.title.lowercasedFirst)",
                         details: [.init(symbol: "clock.arrow.circlepath", text: String(localized: "Its run history stays in the list below"))],
                         confirmTitle: String(localized: "Delete"),
                         onConfirm: {
                             model.delete(automation)
                             deleting = nil
                         },
                         onCancel: { deleting = nil })
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.system(size: 22, weight: .bold))
                Text(subtitle).font(.callout).foregroundStyle(.textSecondary)
            }
            Spacer()
        }
    }

    private var subtitle: String {
        let active = model.automations.filter(\.isEnabled).count
        if model.automations.isEmpty { return String(localized: "Pick a suggestion or make your own") }
        return active == 0 ? String(localized: "All automations are off") : String(localized: "\(active) active")
    }

    private var runsWhileOpenCard: some View {
        HStack(spacing: 12) {
            GlassGlyph(symbol: "menubar.rectangle", tint: module.palette.accent, size: 34, isCompact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Automations run while Spaceroom is open").font(.system(size: 13, weight: .semibold))
                Text(AppDelegate.keepsRunningInMenuBar
                     ? String(localized: "It keeps running in the menu bar after you close the window. Open it at login so nothing is missed.")
                     : String(localized: "Turn on \"Keep running in the menu bar\" in Settings, or automations stop when the window closes."))
                    .font(.caption).foregroundStyle(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !menuBar.opensAtLogin {
                Button("Open at Login") { menuBar.setOpensAtLogin(true) }.buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 10)
        .glassSurface(cornerRadius: 22, wash: module.palette.accent)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Suggestions").font(.headline)
                Text("Each one only touches data that's safe to remove without review, and cleans into the Restore Center.")
                    .font(.caption).foregroundStyle(.textTertiary)
            }
            .padding(.top, model.automations.isEmpty ? 0 : 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
                ForEach(model.suggestions) { template in
                    SuggestionCard(automation: template) { editing = template }
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent runs").font(.headline).padding(.top, 8)
            VStack(spacing: 2) {
                ForEach(model.history.prefix(8)) { run in
                    RunRow(run: run, canUndo: model.canUndo(run)) { model.undo(run) }
                }
            }
            .padding(6)
            .glassSurface()
        }
    }

    private var footer: some View {
        HStack {
            Text(model.isBusy ? String(localized: "Running an automation…")
                 : String(localized: "Cleaned items stay in the Restore Center for \(app.retentionDays) days."))
                .font(.callout).foregroundStyle(.textSecondary)
            Spacer()
            Button {
                editing = Automation(trigger: .weekly(weekday: 7, hour: 10, minute: 0), action: .scanAndNotify)
            } label: {
                Label("New Automation", systemImage: "plus")
            }
            .buttonStyle(FilledButtonStyle(tint: module.palette.accent))
            .disabled(model.storeError != nil)
        }
    }

    private func notice(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .glassSurface(wash: tint)
    }
}

private struct AutomationRow: View {
    let model: AutomationsModel
    let automation: Automation
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let isRunning = model.runningID == automation.id
        HStack(spacing: 12) {
            GlassGlyph(symbol: automation.action.symbol, tint: SidebarModule.automations.palette.accent, size: 30, isCompact: true)
                .opacity(automation.isEnabled ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(automation.action.title).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Label(automation.trigger.summary, systemImage: automation.trigger.symbol)
                    if automation.freesSpaceNow && automation.action.removesFiles {
                        Pill(text: Text("Frees space right away"), tint: .yellow)
                    }
                }
                .font(.caption).foregroundStyle(.textSecondary)
                if isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Running…").font(.caption.weight(.medium))
                    }
                } else {
                    Text(statusText).font(.caption).foregroundStyle(.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button("Run Now", systemImage: "play") { model.runNow(automation) }
                    .disabled(model.isBusy)
                Button("Edit…", systemImage: "pencil", action: onEdit)
                Divider()
                Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(.textSecondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(Text("More"))
            Toggle("", isOn: Binding(get: { automation.isEnabled }, set: { model.setEnabled(automation, $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .accessibilityLabel(Text(automation.action.title))
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    private var statusText: String {
        let next = model.nextRunText(automation)
        guard let last = automation.lastRun else { return next }
        return String(localized: "Last ran \(last.formatted(.relative(presentation: .named))) · \(next)")
    }
}

private struct SuggestionCard: View {
    let automation: Automation
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(alignment: .top, spacing: 12) {
                GlassGlyph(symbol: automation.action.symbol, tint: SidebarModule.automations.palette.accent, size: 30, isCompact: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(automation.action.title).font(.system(size: 13, weight: .semibold))
                    Text(automation.trigger.summary).font(.caption.weight(.medium)).foregroundStyle(.textSecondary)
                    if automation.freesSpaceNow { Pill(text: Text("Frees space right away"), tint: .yellow) }
                    Text(automation.action.detail).font(.caption).foregroundStyle(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .glassSurface()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(Text("Opens it so you can adjust it before saving"))
    }
}

private struct RunRow: View {
    let run: AutomationRun
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(run.action.title).font(.system(size: 13, weight: .medium))
                Text(resultText).font(.caption).foregroundStyle(.textTertiary).lineLimit(2)
            }
            Spacer()
            Text(run.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.textTertiary)
            if canUndo {
                Button { onUndo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
    }

    private var icon: String {
        if run.error != nil { return "xmark.octagon.fill" }
        return run.cleanedBytes > 0 || run.action == .scanAndNotify ? "checkmark.circle.fill" : "minus.circle"
    }

    private var tint: Color {
        run.error != nil ? .orange : run.cleanedBytes > 0 || run.action == .scanAndNotify ? .hex(0x4FCB98) : .textTertiary
    }

    private var resultText: String {
        if let error = run.error { return error }
        if run.action == .scanAndNotify {
            return run.foundBytes > 0 ? String(localized: "Found \(run.foundBytes.bytesText) that can be cleaned. Nothing was removed.")
                : String(localized: "Nothing to clean")
        }
        guard run.cleanedBytes > 0 else { return String(localized: "Nothing to clean") }
        return run.freedNow ? String(localized: "Freed \(run.cleanedBytes.bytesText)")
            : String(localized: "Moved \(run.cleanedBytes.bytesText) to the Restore Center")
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
