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
            DeviceCard()
            ProtectionTile()
            LastCleanupCard()
            footer
        }
        .padding(12)
        .frame(width: 340)
        .foregroundStyle(.white)
        .background(GrainyBackground(palette: SidebarModule.smartCare.palette))
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
                Label("Restore Center holds \(app.storedSize.bytesText) on this disk until items expire",
                      systemImage: "arrow.uturn.backward.circle")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 18)
    }

    private var levelColor: Color {
        switch volume.level {
        case .ok: .white
        case .low: .orange
        case .critical: .hex(0xFF7A7A)
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
        case .critical: .hex(0xFF7A7A)
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
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassSurface(cornerRadius: 16)
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
                .padding(.horizontal, 6)
            }
            Text("Everything goes to the Restore Center first.")
                .font(.caption2)
                .foregroundStyle(.textTertiary)
                .padding(.horizontal, 6)
        }
        // Concentric: 8 pt inset around 12 pt buttons → 20 pt outer radius.
        .padding(8)
        .glassSurface(cornerRadius: 20)
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
                    Text(action.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    detail.font(.caption2).foregroundStyle(.white.opacity(0.65)).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isEnabled ? 0.11 : 0.04)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 16)
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

// MARK: - Battery & network

private struct DeviceCard: View {
    @Environment(MenuBarModel.self) private var menuBar

    var body: some View {
        HStack(spacing: 10) {
            if let battery = menuBar.battery { batteryTile(battery) }
            networkTile
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func batteryTile(_ battery: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: batterySymbol(battery)).foregroundStyle(battery.percent <= 20 && !battery.isPluggedIn ? .orange : .white)
                Text("Battery").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Text("\(battery.percent)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Text(battery.isCharging ? String(localized: "Charging")
                 : battery.isPluggedIn ? String(localized: "Plugged in")
                 : String(localized: "On battery"))
                .font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text("Health \(Int((battery.health * 100).rounded()))%")
                .font(.caption2).monospacedDigit()
                .foregroundStyle(battery.needsService ? .orange : .white.opacity(0.6))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassSurface(cornerRadius: 16)
    }

    private var networkTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "network")
                Text("Network").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 10) {
                Label(rate(menuBar.network?.up), systemImage: "arrow.up").foregroundStyle(Color.hex(0x7FB6FF))
                Label(rate(menuBar.network?.down), systemImage: "arrow.down").foregroundStyle(Color.hex(0x4FCB98))
            }
            .font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Sparkline(values: normalized(menuBar.networkHistory), color: .white).frame(height: 18)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassSurface(cornerRadius: 16)
    }

    private func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "–" }
        // Short, fixed-style rates so both fit side by side: "0 KB/s", "840 KB/s", "2.4 MB/s".
        let kilobytes = bytesPerSecond / 1000
        if kilobytes < 1000 { return "\(Int(kilobytes.rounded())) KB/s" }
        return "\((kilobytes / 1000).formatted(.number.precision(.fractionLength(1)))) MB/s"
    }

    private func normalized(_ values: [Double]) -> [Double] {
        let peak = max(values.max() ?? 0, 1)
        return values.map { $0 / peak }
    }

    private func batterySymbol(_ battery: BatteryInfo) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        return switch battery.percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

// MARK: - Protection

private struct ProtectionTile: View {
    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar

    var body: some View {
        let protection = app.protection
        let count = protection.lastScanCount
        HStack(spacing: 10) {
            Image(systemName: count > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(count > 0 ? Color.hex(0xFF8A7A) : Color.hex(0x6FD67A))
            VStack(alignment: .leading, spacing: 1) {
                Text("Protection").font(.system(size: 12, weight: .semibold))
                Group {
                    if protection.phase == .scanning {
                        Text("Checking \(protection.scannedFiles) files…")
                    } else if let date = protection.lastScanDate {
                        Text(count > 0 ? String(localized: "\(count) items need a look")
                             : String(localized: "Nothing suspicious · \(date.formatted(.relative(presentation: .named)))"))
                    } else {
                        Text("Not checked yet")
                    }
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.65)).monospacedDigit()
            }
            Spacer()
            Button(count > 0 ? "Review" : "Scan") {
                app.selection = .protection
                if count == 0 { protection.startScan() }
                menuBar.openMainWindow()
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(protection.phase == .scanning)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassSurface(cornerRadius: 16)
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
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassSurface(cornerRadius: 16)
        }
    }
}
