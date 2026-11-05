// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// Timeline of clean operations with restore and delete actions, one at a time or in bulk.
struct RestoreCenterView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Set<UUID> = []
    @State private var bulkConfirm: BulkAction?
    @State private var isWorking = false

    enum BulkAction: Identifiable {
        case delete([OperationRecord])
        var id: Int { 0 }
    }

    private var active: [OperationRecord] { app.operations.filter(\.hasStoredItems) }
    private var history: [OperationRecord] { app.operations.filter { !$0.hasStoredItems } }

    /// The operations bulk buttons act on: the ticked ones, or all of them when none are ticked.
    private var targets: [OperationRecord] {
        let ticked = active.filter { selection.contains($0.id) }
        return ticked.isEmpty ? active : ticked
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.operations.isEmpty {
                emptyState
            } else {
                if !active.isEmpty {
                    bulkBar
                        .frame(maxWidth: 760)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(active) { operation in
                            OperationCard(operation: operation, isSelected: selection.contains(operation.id)) {
                                if selection.contains(operation.id) { selection.remove(operation.id) } else { selection.insert(operation.id) }
                            }
                        }
                        if !history.isEmpty {
                            Text("History")
                                .font(.headline)
                                .foregroundStyle(.textSecondary)
                                .padding(.top, 14)
                            ForEach(history.prefix(30)) { OperationCard(operation: $0, isSelected: false, toggle: nil) }
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task { await app.refreshOperations() }
        .onChange(of: app.operations.map(\.id)) {
            // Drop selections of operations that are gone or fully restored/deleted.
            selection.formIntersection(Set(active.map(\.id)))
        }
        .sheet(item: $bulkConfirm) { action in
            switch action {
            case .delete(let operations):
                let size = operations.reduce(0) { $0 + $1.storedSize }
                let items = operations.reduce(0) { $0 + $1.storedItems.count }
                ConfirmSheet(
                    symbol: "trash",
                    title: String(localized: "Delete \(size.bytesText) permanently?"),
                    message: String(localized: "These items leave the Restore Center for good and their space is freed right away."),
                    details: [
                        .init(symbol: "square.stack", text: operations.count == 1
                              ? String(localized: "1 cleanup") : String(localized: "\(operations.count) cleanups")),
                        .init(symbol: "doc.on.doc", text: items == 1 ? String(localized: "1 item") : String(localized: "\(items) items")),
                        .init(symbol: "exclamationmark.triangle", text: String(localized: "This can't be undone")),
                    ],
                    confirmTitle: String(localized: "Delete Permanently"),
                    onConfirm: {
                        bulkConfirm = nil
                        runBulk { await app.purge(operations.map(\.id)) }
                    },
                    onCancel: { bulkConfirm = nil })
            }
        }
    }

    private var header: some View {
        // Compact once there is a list to look at, so more cleanups fit on screen.
        let compact = !app.operations.isEmpty
        return VStack(spacing: 6) {
            ModuleHero(module: .restoreCenter, size: compact ? 64 : 110)
            Text("Restore Center").font(Typography.hero(compact ? 26 : 30))
            Group {
                if app.storedSize > 0 {
                    Text("\(app.storedSize.bytesText) can be restored. Items are kept for \(app.retentionDays) days, then deleted.")
                } else {
                    Text("Cleaned items are kept here for \(app.retentionDays) days, then deleted.")
                }
            }
            .font(.callout)
            .foregroundStyle(.textSecondary)
        }
        .padding(.top, compact ? 24 : 30)
        .padding(.bottom, 18)
    }

    /// Select All plus bulk actions. Without a selection the buttons act on everything.
    private var bulkBar: some View {
        let allSelected = !active.isEmpty && active.allSatisfy { selection.contains($0.id) }
        let size = targets.reduce(0) { $0 + $1.storedSize }
        let scope = selection.isEmpty ? String(localized: "All") : String(localized: "Selected")
        return HStack(spacing: 10) {
            Button {
                selection = allSelected ? [] : Set(active.map(\.id))
            } label: {
                HStack(spacing: 8) {
                    IconSwap(isOn: !selection.isEmpty,
                             on: allSelected ? "checkmark.square.fill" : "minus.square.fill", off: "square")
                        .font(.system(size: 15))
                        .foregroundStyle(selection.isEmpty ? .textTertiary : .white)
                    Text(selection.isEmpty
                         ? String(localized: "Select All")
                         : String(localized: "\(selection.count) of \(active.count) selected"))
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)

            Text(size.bytesText).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(.textSecondary)
            Spacer()
            Button("Restore \(scope)") { runBulk { await app.restoreAll(targets.map(\.id)) } }
                .buttonStyle(GhostButtonStyle())
            Button("Delete \(scope)") { bulkConfirm = .delete(targets) }
                .buttonStyle(FilledButtonStyle(tint: .hex(0xFF5A6E)))
        }
        .disabled(isWorking || active.isEmpty)
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
        // Concentric with the capsule buttons inside (≈ 15 pt + 8 pt inset).
        .glassSurface(cornerRadius: 23)
    }

    private func runBulk(_ action: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await action()
            selection = []
            isWorking = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Nothing here yet").font(.title3.weight(.semibold))
            Text("When you clean something, it lands here first so you can change your mind.")
                .foregroundStyle(.textSecondary)
            Spacer()
        }
    }
}

private struct OperationCard: View {
    let operation: OperationRecord
    let isSelected: Bool
    /// `nil` for history cards (nothing left to act on).
    let toggle: (() -> Void)?
    @Environment(AppModel.self) private var app
    @State private var isExpanded = false
    @State private var isConfirmingDelete = false
    @State private var isWorking = false

    private var module: SidebarModule {
        SidebarModule(rawValue: operation.module) ?? .cleanup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let toggle {
                    Button(action: toggle) {
                        IconSwap(isOn: isSelected, on: "checkmark.square.fill", off: "square")
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? .white : .textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(isSelected ? "Deselect" : "Select"))
                }
                ModuleIcon(module: module, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(title) · \(operation.totalSize.bytesText)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.textTertiary)
                }
                Spacer()
                if operation.hasStoredItems {
                    Button("Delete Now", role: .destructive) { isConfirmingDelete = true }
                        .buttonStyle(GhostButtonStyle())
                    Button("Restore") { run { await app.restoreAll(operation.id) } }
                        .buttonStyle(GhostButtonStyle())
                }
                Button { withAnimation(Easing.out(0.2)) { isExpanded.toggle() } } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isExpanded ? "Hide items" : "Show items"))
            }
            .padding(14)

            if isExpanded {
                Divider().overlay(.white.opacity(0.15))
                VStack(spacing: 0) {
                    ForEach(operation.items) { item in
                        ItemLine(item: item) { run { await app.restore(item.id, in: operation.id) } }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .glassSurface(cornerRadius: 18, wash: isSelected ? module.palette.accent : nil,
                      isHighlighted: operation.hasStoredItems)
        .animation(Motion.hover, value: isSelected)
        .opacity(isWorking ? 0.6 : 1)
        .disabled(isWorking)
        .sheet(isPresented: $isConfirmingDelete) {
            ConfirmSheet(
                symbol: "trash",
                title: String(localized: "Delete \(operation.storedSize.bytesText) permanently?"),
                message: String(localized: "These items leave the Restore Center for good and their space is freed right away."),
                details: [
                    .init(symbol: "doc.on.doc", text: "\(itemCountText(operation.storedItems.count)) · \(title)"),
                    .init(symbol: "calendar", text: String(localized: "Cleaned \(operation.date.formatted(date: .abbreviated, time: .shortened))")),
                    .init(symbol: "exclamationmark.triangle", text: String(localized: "This can't be undone")),
                ],
                confirmTitle: String(localized: "Delete Permanently"),
                onConfirm: {
                    isConfirmingDelete = false
                    run { await app.purge(operation.id) }
                },
                onCancel: { isConfirmingDelete = false })
        }
    }

    /// "Uninstalled Android Studio" for app removals, otherwise the module ("Smart Care").
    private var title: String {
        guard operation.module == "applications" else { return String(localized: module.title) }
        let apps = operation.items.filter { $0.ruleID.hasPrefix("app.") }
            .map { ($0.name as NSString).deletingPathExtension }
        switch apps.count {
        case 0: return String(localized: "App leftovers")
        case 1: return String(localized: "Uninstalled \(apps[0])")
        default: return String(localized: "Uninstalled \(apps.count) apps")
        }
    }

    private var subtitle: String {
        let date = operation.date.formatted(date: .abbreviated, time: .shortened)
        let count = itemCountText(operation.items.count)
        if operation.hasStoredItems {
            let expiry = operation.expiryDate(retentionDays: app.retentionDays)
            return String(localized: "\(date) · \(count) · deleted \(expiry.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "\(date) · \(count) · restored or deleted")
    }

    private func itemCountText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}

private struct ItemLine: View {
    let item: QuarantinedItem
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(item.originalPath.abbreviatingHome)
                    .font(.caption2).foregroundStyle(.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.size.bytesText).font(.caption).monospacedDigit().foregroundStyle(.textSecondary)
            switch item.state {
            case .stored:
                Button("Restore", action: restore).buttonStyle(GhostButtonStyle())
            case .restored:
                Pill(text: Text("Restored"), tint: .green)
            case .purged:
                Pill(text: Text("Deleted"), tint: .white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
