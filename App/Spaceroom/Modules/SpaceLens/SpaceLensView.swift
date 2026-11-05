// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// Space Lens: pick a disk or folder, watch its map grow, then explore it.
struct SpaceLensView: View {
    @Bindable var model: SpaceLensModel
    @Environment(AppModel.self) private var app

    private let module = SidebarModule.spaceLens

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro: intro.transition(.phaseSwap)
            case .scanning, .results: explorer.transition(.phaseSwap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            ModuleHero(module: module, size: 130)
            Text(module.title).font(Typography.hero()).padding(.top, 4)
            Text(module.tagline).font(.title3).foregroundStyle(.textSecondary).padding(.top, 6)

            HStack(spacing: 12) {
                ForEach(model.targets) { target in
                    TargetCard(target: target, isSelected: model.selectedTargetID == target.id) {
                        model.selectedTargetID = target.id
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.top, 26)

            Text("Large disks can take a few minutes. Folders appear on the map as soon as they're measured, so you can start exploring right away.")
                .font(.callout)
                .foregroundStyle(.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.top, 18)
            if app.fullDiskAccess == .denied {
                FullDiskAccessHint().padding(.top, 14)
            }
            Spacer(minLength: 20)
            PrimaryCircleButton(title: "Scan", tint: module.palette.accent) { model.start() }
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .onAppear { model.refreshTargets() }
    }

    // MARK: Explorer (scanning + results)

    private var explorer: some View {
        VStack(spacing: 0) {
            keyboardShortcuts
            header
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 14)
            if let current = model.current {
                HStack(alignment: .top, spacing: 20) {
                    SunburstChart(node: current, title: model.path.isEmpty ? model.displayName : nil,
                                  canGoUp: !model.path.isEmpty,
                                  hoveredID: $model.hoveredID,
                                  onDrill: { node in withAnimation(Easing.out(0.22)) { model.drill(into: node) } },
                                  onUp: { withAnimation(Easing.out(0.22)) { model.goUp() } })
                        .frame(minWidth: 340, maxWidth: 520, maxHeight: 520)
                    FolderList(model: model, folder: current)
                        .frame(minWidth: 320, maxWidth: 420)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            } else {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Measuring the first folders…").foregroundStyle(.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            if !model.path.isEmpty {
                // Mouse: a short spatial transition. Keyboard (⌘↑ / ⌘[): instant, like Finder.
                Button { withAnimation(Easing.out(0.22)) { model.goUp() } } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(GhostButtonStyle())
                .help("Back to \(model.breadcrumb.dropLast().last.map { SpaceLensFormat.name(of: $0) } ?? model.displayName) (⌘↑)")
                .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.path.last.map { SpaceLensFormat.name(of: $0) } ?? model.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                Group {
                    if model.phase == .scanning {
                        ScanProgressLabel(model: model)
                    } else if let folder = model.path.last, let root = model.breadcrumb.first {
                        Text("\(folder.size.bytesText) · \(Int((Double(folder.size) / Double(max(root.size, 1)) * 100).rounded()))% of \(model.displayName)")
                    } else if let root = model.breadcrumb.first {
                        Text(summary(root))
                    }
                }
                .font(.callout)
                .foregroundStyle(.textSecondary)
                .monospacedDigit()
            }
            Spacer()
            if let hidden = model.hiddenBytes {
                Label("\(hidden.bytesText) system & hidden", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassSurface(cornerRadius: 14)
                    .help("Used space the scan can't see: macOS system files, local snapshots, other users and protected folders.")
            }
            if model.phase == .scanning {
                ProgressView().controlSize(.small)
                Button("Stop") { model.stop() }.buttonStyle(GhostButtonStyle())
            } else {
                Button { model.newScan() } label: { Label("New Scan", systemImage: "arrow.clockwise") }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }

    /// Keyboard navigation without animation (keyboard actions repeat; they must feel instant).
    private var keyboardShortcuts: some View {
        Group {
            Button("Back") { model.goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("Back") { model.goUp() }.keyboardShortcut("[", modifiers: .command)
        }
        .disabled(model.path.isEmpty)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func summary(_ root: DiskNode) -> String {
        var parts = [root.size.bytesText, String(localized: "\(root.itemCount.formatted()) items")]
        if let duration = model.scanDuration {
            parts.append(String(localized: "scanned in \(Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))"))
        }
        if model.isPartial { parts.append(String(localized: "some folders unreadable")) }
        return parts.joined(separator: " · ")
    }
}

/// Reads the fast-changing counters in its own view so only this label re-renders, not the map.
private struct ScanProgressLabel: View {
    let model: SpaceLensModel
    var body: some View {
        Text("Scanning… \(model.scannedItems.formatted()) items · \(model.scannedBytes.bytesText)")
    }
}

// MARK: - Target card

private struct TargetCard: View {
    let target: SpaceLensModel.Target
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                GlassGlyph(symbol: target.symbol, tint: SidebarModule.spaceLens.palette.accent, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(target.detail).font(.caption).foregroundStyle(.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                IconSwap(isOn: isSelected, on: "checkmark.circle.fill", off: "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : .textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .glassSurface(cornerRadius: 20, wash: isSelected ? SidebarModule.spaceLens.palette.accent : nil,
                          isHighlighted: isHovering)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovering = $0 }
        .animation(Motion.hover, value: isHovering)
        .animation(Motion.hover, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Folder list

private struct FolderList: View {
    @Bindable var model: SpaceLensModel
    let folder: DiskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumb
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(folder.children.enumerated()), id: \.element.id) { index, child in
                        Row(node: child, parentSize: folder.size, family: index,
                            isHovered: model.hoveredID == child.id) {
                            withAnimation(Easing.out(0.22)) { model.drill(into: child) }
                        }
                        .onHover { inside in
                            if inside { model.hoveredID = child.id } else if model.hoveredID == child.id { model.hoveredID = nil }
                        }
                        .contextMenu {
                            if case .other = child.kind {} else {
                                Button("Show in Finder") { model.reveal(child) }
                                Button("Copy Path") { model.copyPath(child) }
                            }
                        }
                    }
                }
                .padding(6)
            }
        }
        .glassSurface(cornerRadius: 20)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(model.breadcrumb.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.textTertiary)
                    }
                    let isLast = index == model.breadcrumb.count - 1
                    Button(index == 0 ? model.displayName : node.name) {
                        withAnimation(Easing.out(0.22)) { model.go(toBreadcrumb: index) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                    .foregroundStyle(isLast ? .white : .textSecondary)
                    .disabled(isLast)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private struct Row: View {
        let node: DiskNode
        let parentSize: Int64
        let family: Int
        let isHovered: Bool
        let open: () -> Void

        var body: some View {
            let fraction = parentSize > 0 ? Double(node.size) / Double(parentSize) : 0
            let canOpen = node.kind == .folder && !node.children.isEmpty
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: SpaceLensFormat.symbol(for: node))
                        .foregroundStyle(swatch)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(SpaceLensFormat.name(of: node)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            if node.isPartial {
                                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.yellow.opacity(0.8))
                                    .help("Some items inside couldn't be read, so this size may be larger.")
                            }
                            Spacer(minLength: 6)
                            Text((node.isPartial ? "≈ " : "") + node.size.bytesText)
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.08))
                                Capsule().fill(swatch.opacity(0.9)).frame(width: max(2, proxy.size.width * fraction))
                            }
                        }
                        .frame(height: 3)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.textTertiary)
                        .opacity(canOpen ? 1 : 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.09 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .accessibilityElement(children: .combine)
            .accessibilityHint(canOpen ? Text("Opens this folder") : Text(""))
        }

        private var swatch: Color {
            if case .other = node.kind { return .white.opacity(0.5) }
            return SunburstChart.palette[family % SunburstChart.palette.count]
        }
    }
}
