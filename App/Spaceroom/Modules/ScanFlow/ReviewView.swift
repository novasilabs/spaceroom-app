// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// "Review Details": rules on the left, the focused rule's items on the right.
struct ReviewView: View {
    let module: SidebarModule
    @Bindable var flow: ScanFlowModel
    @Environment(AppModel.self) private var app

    private var visibleResults: [RuleScanResult] { flow.results.filter { !$0.items.isEmpty } }

    private var focused: RuleScanResult? {
        visibleResults.first { $0.rule.id == flow.focusedRuleID } ?? visibleResults.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 14) {
                ruleList.frame(width: 290)
                if let focused { ItemPane(result: focused, flow: flow) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            footer
        }
    }

    private var header: some View {
        HStack {
            Button { flow.isReviewing = false } label: { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(GhostButtonStyle())
            Spacer()
            Text("Review Details").font(.title2.weight(.semibold))
            Spacer()
            Color.clear.frame(width: 80, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 44)
        .padding(.bottom, 14)
    }

    private var ruleList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(visibleResults) { result in
                    let isFocused = result.rule.id == focused?.rule.id
                    let isSelected = flow.selectedRuleIDs.contains(result.rule.id)
                    HStack(spacing: 10) {
                        Button { flow.toggleRule(result.rule.id) } label: {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 15))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(isSelected ? "Deselect \(result.rule.localizedTitle)" : "Select \(result.rule.localizedTitle)"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.rule.localizedTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(GroupInfo.forGroup(result.rule.group).title)
                                .font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Text(flow.selectedSize(of: result).bytesText)
                            .font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(.white.opacity(isSelected ? 0.85 : 0.45))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isFocused ? 0.14 : 0)))
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Always Ignore This Category", systemImage: "eye.slash") { flow.ignoreRule(result.rule.id) }
                    }
                    .onTapGesture { flow.focusedRuleID = result.rule.id }
                }
            }
            .padding(8)
        }
        .glassSurface(cornerRadius: 14)
    }

    private var footer: some View {
        HStack {
            Text("Selected: \(flow.selectedSize.bytesText)")
                .font(.headline).monospacedDigit()
            Spacer()
            Button("Clean") { flow.clean() }
                .buttonStyle(FilledButtonStyle(tint: module.palette.accent))
                .disabled(flow.selectedSize == 0 || app.cleaningBlockedReason != nil)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }
}

private struct ItemPane: View {
    let result: RuleScanResult
    @Bindable var flow: ScanFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.rule.localizedTitle).font(.title3.weight(.semibold))
                Label {
                    Text(result.rule.localizedWhySafe)
                } icon: {
                    Image(systemName: "lightbulb").foregroundStyle(.yellow)
                }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                if let hint = result.rule.localizedRebuildHint {
                    Label(hint, systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 14)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(result.items) { item in
                        ItemRow(item: item,
                                isSelected: item.isCleanable && flow.selectedRuleIDs.contains(item.ruleID)
                                    && !flow.deselectedItemIDs.contains(item.id)) {
                            flow.toggleItem(item)
                        }
                        .contextMenu {
                            Button("Show in Finder", systemImage: "folder") { Finder.reveal(item.url) }
                            if item.skipReason != .ignored {
                                Button("Always Ignore", systemImage: "eye.slash") { flow.ignore(item) }
                            }
                        }
                    }
                }
                .padding(6)
            }
            .glassSurface(cornerRadius: 12)
        }
    }
}

private struct ItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square").font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(!item.isCleanable)
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                Text(item.url.path.abbreviatingHome)
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let reason = item.skipReason {
                Pill(text: Text(reason.text), tint: .yellow)
            } else {
                Text(item.lastModified, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Text(item.size.bytesText)
                .font(.system(size: 12)).monospacedDigit()
                .frame(width: 72, alignment: .trailing)
            Button { Finder.reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain)
                .help("Show in Finder")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .opacity(item.isCleanable ? 1 : 0.6)
    }
}
