// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// System Status: a health score with what to do about it, live gauges and the busiest processes.
struct StatusView: View {
    @Bindable var model: StatusModel
    @Environment(AppModel.self) private var app

    private let module = SidebarModule.status

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                HStack(alignment: .top, spacing: 14) {
                    HealthCard(report: model.health) { app.runSmartCare() }
                        .frame(width: 300)
                    CPUCard(model: model)
                }
                .entrance(0)
                HStack(alignment: .top, spacing: 14) {
                    MemoryCard(model: model)
                    NetworkCard(model: model)
                    DiskCard(volume: model.volume)
                    if let battery = model.battery { BatteryCard(battery: battery) }
                }
                .entrance(1)
                ProcessesCard(model: model).entrance(2)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.system(size: 22, weight: .bold))
                Text(subtitle).font(.callout).foregroundStyle(.textSecondary)
            }
            Spacer()
            ThermalBadge(state: model.thermal)
        }
    }

    private var subtitle: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let up = Duration.seconds(model.uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
        return String(localized: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) · up \(up)")
    }
}

// MARK: - Cards

/// Shared card chrome: title row and content on a glass surface.
private struct Card<Content: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .font(Typography.eyebrow)
                .foregroundStyle(.textSecondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassSurface()
    }
}

private struct HealthCard: View {
    let report: HealthReport
    let runSmartCare: () -> Void

    private var color: Color {
        switch report.grade {
        case .good: .hex(0x4FCB98)
        case .fair: .hex(0xF2C94C)
        case .poor: .hex(0xFF7A7A)
        }
    }

    private var label: LocalizedStringResource {
        switch report.grade {
        case .good: "Healthy"
        case .fair: "Could be better"
        case .poor: "Needs attention"
        }
    }

    var body: some View {
        Card(title: "Health", symbol: "heart.text.square") {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(report.score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(Easing.out(0.5), value: report.score)
                    Text("\(report.score)")
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                    Text(report.factors.isEmpty ? "Nothing needs your attention."
                         : report.factors.count == 1 ? "1 thing to look at" : "\(report.factors.count) things to look at")
                        .font(.caption).foregroundStyle(.textSecondary)
                }
            }
            if !report.factors.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.factors) { factor in
                        HStack(alignment: .top, spacing: 8) {
                            Text("−\(factor.penalty)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(color)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(factor.summary).font(.system(size: 12, weight: .semibold))
                                Text(factor.advice).font(.caption).foregroundStyle(.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 4)
                if report.factors.contains(where: { $0.area == .disk }) {
                    Button { runSmartCare() } label: { Label("Run Smart Care", systemImage: "sparkles") }
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }
}

private struct CPUCard: View {
    let model: StatusModel

    var body: some View {
        Card(title: "CPU", symbol: "cpu") {
            HStack(alignment: .firstTextBaseline) {
                Text(model.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                if let load = model.load {
                    Text("Load \(load.one, format: .number.precision(.fractionLength(2))) · \(load.five, format: .number.precision(.fractionLength(2))) · \(load.fifteen, format: .number.precision(.fractionLength(2)))")
                        .font(.caption).foregroundStyle(.textTertiary).monospacedDigit()
                        .help("Load average over 1, 5 and 15 minutes")
                }
            }
            Sparkline(values: model.cpuHistory, color: .hex(0x5AAAF2), capacity: StatusModel.historyLength)
                .frame(height: 54)
            // Thin bars with a small corner radius: capsules turn short bars into blobs.
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(model.cores.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 3) {
                        GeometryReader { proxy in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.1))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.hex(0x5AAAF2).opacity(0.55 + value * 0.45))
                                    .frame(height: max(2, proxy.size.height * value))
                            }
                        }
                        .frame(width: 14, height: 40)
                        Text("\(index + 1)").font(.system(size: 9)).foregroundStyle(.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(Easing.out(0.3), value: model.cores)
            .accessibilityLabel(Text("\(model.cores.count) cores"))
        }
    }
}

private struct MemoryCard: View {
    let model: StatusModel

    var body: some View {
        Card(title: "Memory", symbol: "memorychip") {
            if let memory = model.memory {
                Text(memory.usedBytes.bytesText).font(.system(size: 22, weight: .bold).monospacedDigit())
                Text("of \(memory.totalBytes.bytesText) · \(pressureText(memory.pressure))")
                    .font(.caption).foregroundStyle(pressureColor(memory.pressure))
                Sparkline(values: model.memoryHistory, color: pressureColor(memory.pressure), capacity: StatusModel.historyLength)
                    .frame(height: 28)
                if let swap = model.swap, swap.used > 0 {
                    Text("Swap \(swap.used.bytesText)").font(.caption).foregroundStyle(.textTertiary)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func pressureText(_ pressure: MemorySnapshot.Pressure) -> String {
        switch pressure {
        case .normal: String(localized: "normal pressure")
        case .warning: String(localized: "under pressure")
        case .critical: String(localized: "critical pressure")
        }
    }

    private func pressureColor(_ pressure: MemorySnapshot.Pressure) -> Color {
        switch pressure {
        case .normal: .textSecondary
        case .warning: .orange
        case .critical: .hex(0xFF7A7A)
        }
    }
}

private struct NetworkCard: View {
    let model: StatusModel

    var body: some View {
        Card(title: "Network", symbol: "network") {
            HStack(spacing: 14) {
                rate("arrow.down", model.network?.down)
                rate("arrow.up", model.network?.up)
            }
            ZStack {
                Sparkline(values: normalized(model.downHistory), color: .hex(0x4FCB98), capacity: StatusModel.historyLength)
                Sparkline(values: normalized(model.upHistory), color: .hex(0xB86AE6), capacity: StatusModel.historyLength)
            }
            .frame(height: 28)
        }
    }

    private func rate(_ symbol: String, _ value: Double?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(.textTertiary)
            Text(value.map(Self.rateText) ?? "–")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// "990 B/s", "4.2 kB/s", "12 MB/s" — short enough for a small card.
    static func rateText(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1_000 { return "\(Int(bytesPerSecond)) B/s" }
        return Int64(bytesPerSecond).formatted(.byteCount(style: .decimal, spellsOutZero: false)) + "/s"
    }

    /// Both lines share one scale so their heights compare.
    private func normalized(_ values: [Double]) -> [Double] {
        let peak = max(1, (model.downHistory + model.upHistory).max() ?? 1)
        return values.map { $0 / peak }
    }
}

private struct DiskCard: View {
    let volume: VolumeInfo?

    var body: some View {
        Card(title: "Disk", symbol: "internaldrive") {
            if let volume {
                Text(volume.availableBytes.bytesText).font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(volume.level == .ok ? .white : (volume.level == .low ? .orange : .hex(0xFF7A7A)))
                Text("free of \(volume.totalBytes.bytesText)").font(.caption).foregroundStyle(.textSecondary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(.white.opacity(0.85)).frame(width: proxy.size.width * volume.usedFraction)
                    }
                }
                .frame(height: 6)
                Text("\(Int((volume.usedFraction * 100).rounded()))% used").font(.caption).foregroundStyle(.textTertiary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct BatteryCard: View {
    let battery: BatteryInfo

    var body: some View {
        Card(title: "Battery", symbol: battery.isCharging ? "battery.100.bolt" : "battery.75") {
            Text("\(battery.percent)%").font(.system(size: 22, weight: .bold).monospacedDigit())
            Text(stateText).font(.caption).foregroundStyle(.textSecondary)
            Text("Health \(Int((battery.health * 100).rounded()))% · \(battery.cycleCount) cycles")
                .font(.caption)
                .foregroundStyle(battery.needsService ? .orange : .textTertiary)
            if let temperature = battery.temperatureCelsius {
                Text("\(temperature, format: .number.precision(.fractionLength(0)))°C")
                    .font(.caption).foregroundStyle(.textTertiary)
            }
        }
    }

    private var stateText: String {
        let watts = battery.watts.map { String(format: "%.1f W", abs($0)) }
        if battery.isCharging { return [String(localized: "Charging"), watts].compactMap { $0 }.joined(separator: " · ") }
        if battery.isPluggedIn { return String(localized: "Plugged in") }
        return [String(localized: "On battery"), watts].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ProcessesCard: View {
    let model: StatusModel

    var body: some View {
        Card(title: "Busiest processes", symbol: "list.bullet.rectangle") {
            if model.processes.isEmpty {
                Text("Measuring…").font(.callout).foregroundStyle(.textTertiary)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.processes) { process in
                        let app = model.runningApp(for: process.pid)
                        let busy = model.busySeconds[process.pid] ?? 0
                        HStack(spacing: 10) {
                            Group {
                                if let icon = app?.icon {
                                    Image(nsImage: icon).resizable()
                                } else {
                                    Image(systemName: "gearshape.2").foregroundStyle(.textTertiary)
                                }
                            }
                            .frame(width: 22, height: 22)
                            Text(app?.localizedName ?? process.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            if busy >= 60 {
                                Pill(text: Text("busy for \(Duration.seconds(busy).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)))"),
                                     tint: .orange)
                            }
                            Spacer()
                            Text(process.memoryBytes.bytesText).font(.caption).monospacedDigit().foregroundStyle(.textTertiary)
                                .frame(width: 80, alignment: .trailing)
                            Text("\(Int(process.cpuPercent.rounded()))%")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                            if app != nil {
                                Button("Quit") { model.quit(process.pid) }.buttonStyle(GhostButtonStyle())
                            } else {
                                Color.clear.frame(width: 58, height: 1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("Only apps can be quit here. System processes are shown for information.")
                    .font(.caption2).foregroundStyle(.textTertiary)
            }
        }
    }
}

private struct ThermalBadge: View {
    let state: ProcessInfo.ThermalState

    var body: some View {
        let (text, color): (LocalizedStringResource, Color) = switch state {
        case .nominal: ("Cool", .hex(0x4FCB98))
        case .fair: ("Warm", .hex(0xF2C94C))
        case .serious: ("Hot", .orange)
        case .critical: ("Very hot", .hex(0xFF7A7A))
        @unknown default: ("Unknown", .white)
        }
        return Label { Text(text) } icon: { Image(systemName: "thermometer.medium") }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassSurface(cornerRadius: 14)
            .help("Thermal state reported by macOS")
    }
}
