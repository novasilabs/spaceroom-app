// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// The window that opens from any Spaceroom menu bar item.
struct MenuBarPopover: View {
    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            header
            if let root = menuBar.rootVolume { StorageCard(volume: root) }
            ForEach(menuBar.externalVolumes) { ExternalVolumeRow(volume: $0) }
            QuickActionsCard()
            HealthCard()
            LastCleanupCard()
            footer
        }
        .padding(12)
        .frame(width: 340)
        .foregroundStyle(.white)
        .background(ModuleBackground(module: .smartCare))
        .environment(\.colorScheme, .dark)
        .onAppear {
            AppDelegate.openMainWindowAction = { openWindow(id: "main") }
            menuBar.popoverDidAppear()
        }
        .onDisappear { menuBar.popoverDidDisappear() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill").symbolRenderingMode(.hierarchical)
            Text("Spaceroom").font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            if app.fullDiskAccess == .denied {
                Button { app.isShowingOnboarding = true; menuBar.openMainWindow() } label: {
                    Label("Full Disk Access", systemImage: "lock.shield").font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.yellow)
                .help("Some locations can't be measured or cleaned without Full Disk Access")
            }
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                app.runSmartCare()
                menuBar.openMainWindow()
            } label: { Label("Smart Care", systemImage: "sparkles") }
                .buttonStyle(GhostButtonStyle())
                .help("Open Spaceroom and run Smart Care")
            Button { menuBar.openMainWindow() } label: { Image(systemName: "macwindow") }
                .buttonStyle(GhostButtonStyle())
                .help("Open Spaceroom")
                .accessibilityLabel(Text("Open Spaceroom"))
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(GhostButtonStyle())
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(GhostButtonStyle())
                .help("Quit Spaceroom")
        }
    }
}

// MARK: - Storage

private struct StorageCard: View {
    let volume: VolumeInfo
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "internaldrive")
                Text(volume.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(volume.availableBytes.bytesText) free")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(levelColor)
            }
            StorageBar(volume: volume)
            HStack(spacing: 10) {
                legend(.white, String(localized: "Used \(volume.usedBytes.bytesText)"))
                if volume.purgeableBytes > 0 {
                    legend(.white.opacity(0.45), String(localized: "Purgeable \(volume.purgeableBytes.bytesText)"))
                }
                Spacer(minLength: 4)
                Text("of \(volume.totalBytes.bytesText)").foregroundStyle(.white.opacity(0.55))
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if app.storedSize > 0 {
                Label("Restore Center holds \(app.storedSize.bytesText) until items expire",
                      systemImage: "arrow.uturn.backward.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(12)
        .glassSurface(cornerRadius: 12)
    }

    private var levelColor: Color {
        switch volume.level {
        case .ok: .white
        case .low: .orange
        case .critical: .red
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

private struct StorageBar: View {
    let volume: VolumeInfo

    var body: some View {
        GeometryReader { proxy in
            let total = max(Double(volume.totalBytes), 1)
            let usedWidth = proxy.size.width * Double(volume.usedBytes) / total
            let purgeableWidth = proxy.size.width * Double(volume.purgeableBytes) / total
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                HStack(spacing: 0) {
                    Rectangle().fill(barColor).frame(width: usedWidth)
                    Rectangle().fill(.white.opacity(0.45)).frame(width: purgeableWidth)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(Text("\(Int((volume.usedFraction * 100).rounded())) percent used"))
    }

    private var barColor: Color {
        switch volume.level {
        case .ok: .white
        case .low: .orange
        case .critical: .red
        }
    }
}

private struct ExternalVolumeRow: View {
    let volume: VolumeInfo
    @Environment(MenuBarModel.self) private var menuBar

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
            Text(volume.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer()
            Text("\(volume.availableBytes.bytesText) free").font(.caption).monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
            if volume.isEjectable {
                Button { menuBar.eject(volume) } label: { Image(systemName: "eject.fill") }
                    .buttonStyle(.plain)
                    .help("Eject \(volume.name)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassSurface(cornerRadius: 10)
    }
}

// MARK: - Quick actions

private struct QuickActionsCard: View {
    @Environment(MenuBarModel.self) private var menuBar
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(MenuBarModel.QuickAction.allCases) { action in
                    QuickActionButton(action: action, state: menuBar.actionStates[action] ?? .unknown,
                                      isBlocked: app.cleaningBlockedReason != nil) {
                        menuBar.run(action)
                    }
                }
            }
            if let last = menuBar.lastAction {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(last.message).font(.caption.weight(.medium))
                    Spacer()
                    if last.operationID != nil {
                        Button("Undo") { menuBar.undoLastAction() }.buttonStyle(GhostButtonStyle())
                    }
                }
            }
            Text("Everything goes to the Restore Center first.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .glassSurface(cornerRadius: 12)
    }
}

private struct QuickActionButton: View {
    let action: MenuBarModel.QuickAction
    let state: MenuBarModel.ActionState
    let isBlocked: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 8) {
                Image(systemName: action.symbol).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    detail.font(.caption2).foregroundStyle(.white.opacity(0.65)).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(isEnabled ? 0.12 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }

    private var isEnabled: Bool {
        guard !isBlocked else { return false }
        switch state {
        case .ready(let cleanable, _): return cleanable > 0
        case .needsAccess: return true
        case .unknown, .measuring, .running: return false
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state {
        case .unknown: Text("–")
        case .measuring: Text("Measuring…")
        case .running: Text("Cleaning…")
        case .needsAccess: Text("Needs access").foregroundStyle(.yellow)
        case .ready(let cleanable, let skipped):
            if cleanable > 0 {
                Text(cleanable.bytesText)
            } else if skipped > 0 {
                Text("In use (\(skipped.bytesText))")
            } else {
                Text("Already clean")
            }
        }
    }
}

// MARK: - Health

private struct HealthCard: View {
    @Environment(MenuBarModel.self) private var menuBar

    var body: some View {
        HStack(spacing: 10) {
            metric(title: "CPU", value: menuBar.cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "–",
                   history: menuBar.cpuHistory, color: .white)
            metric(title: "Memory",
                   value: menuBar.memory.map { "\($0.usedBytes.bytesText) / \($0.totalBytes.bytesText)" } ?? "–",
                   history: menuBar.memoryHistory, color: pressureColor)
        }
    }

    private var pressureColor: Color {
        switch menuBar.memory?.pressure {
        case .critical: .red
        case .warning: .orange
        default: .white
        }
    }

    private func metric(title: LocalizedStringResource, value: String, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.8)
            Sparkline(values: history, color: color).frame(height: 22)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 12)
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = .white
    /// Number of samples the full width represents.
    var capacity = 60

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(capacity - 1)
            let start = size.width - step * CGFloat(values.count - 1)
            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: start + step * CGFloat(index), y: size.height * (1 - CGFloat(min(1, max(0, value)))))
                index == 0 ? line.move(to: point) : line.addLine(to: point)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: start, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(color.opacity(0.18)))
            context.stroke(line, with: .color(color.opacity(0.9)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Last cleanup

private struct LastCleanupCard: View {
    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar

    var body: some View {
        if let last = app.operations.first(where: \.hasStoredItems) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cleaned \(last.storedSize.bytesText)").font(.system(size: 12, weight: .semibold))
                    Text(last.date, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button("Undo") { menuBar.undo(last.id) }.buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .glassSurface(cornerRadius: 12)
        }
    }
}
