// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// Timeline of clean operations with restore and delete actions.
struct RestoreCenterView: View {
    @Environment(AppModel.self) private var app

    private var active: [OperationRecord] { app.operations.filter(\.hasStoredItems) }
    private var history: [OperationRecord] { app.operations.filter { !$0.hasStoredItems } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.operations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(active) { OperationCard(operation: $0) }
                        if !history.isEmpty {
                            Text("History")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.top, 14)
                            ForEach(history.prefix(30)) { OperationCard(operation: $0) }
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
    }

    private var header: some View {
        VStack(spacing: 6) {
            ModuleHero(module: .restoreCenter, size: 110)
            Text("Restore Center").font(Typography.hero(30))
            Group {
                if app.storedSize > 0 {
                    Text("\(app.storedSize.bytesText) can be restored. Items are kept for \(app.retentionDays) days, then deleted.")
                } else {
                    Text("Cleaned items are kept here for \(app.retentionDays) days, then deleted.")
                }
            }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 30)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Nothing here yet").font(.title3.weight(.semibold))
            Text("When you clean something, it lands here first so you can change your mind.")
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
    }
}

private struct OperationCard: View {
    let operation: OperationRecord
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
                ModuleIcon(module: module, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Text(module.title)) · \(operation.totalSize.bytesText)")
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if operation.hasStoredItems {
                    Button("Delete Now", role: .destructive) { isConfirmingDelete = true }
                        .buttonStyle(GhostButtonStyle())
                    Button("Restore All") { run { await app.restoreAll(operation.id) } }
                        .buttonStyle(GhostButtonStyle())
                }
                Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
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
        .glassSurface(cornerRadius: 14, tint: operation.hasStoredItems ? 0.08 : 0.02)
        .opacity(isWorking ? 0.6 : 1)
        .disabled(isWorking)
        .confirmationDialog("Delete these items permanently?", isPresented: $isConfirmingDelete) {
            Button("Delete \(operation.storedSize.bytesText) Permanently", role: .destructive) {
                run { await app.purge(operation.id) }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var subtitle: String {
        let date = operation.date.formatted(date: .abbreviated, time: .shortened)
        let count = operation.items.count
        if operation.hasStoredItems {
            let expiry = operation.expiryDate(retentionDays: app.retentionDays)
            return String(localized: "\(date) · \(count) items · deleted \(expiry.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "\(date) · \(count) items · restored or deleted")
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
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(item.originalPath.abbreviatingHome)
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.size.bytesText).font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.7))
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
