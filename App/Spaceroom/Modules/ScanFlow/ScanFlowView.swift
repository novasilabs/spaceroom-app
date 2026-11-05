// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// The module page: one illustrated screen per phase, one glowing primary button.
///
/// Motion follows the frequency rule: the intro (seen on every visit) appears without
/// ceremony; results and done (infrequent, a success moment) enter in staged chunks;
/// every phase leaves with a short 150 ms exit.
struct ScanFlowView: View {
    let module: SidebarModule
    @Bindable var flow: ScanFlowModel
    @Environment(AppModel.self) private var app

    private var accent: Color { module.palette.accent }

    var body: some View {
        ZStack {
            switch flow.phase {
            case .intro: intro.transition(.phaseSwap)
            case .scanning: scanning.transition(.phaseSwap)
            case .results:
                if flow.isReviewing {
                    ReviewView(module: module, flow: flow)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                } else {
                    results.transition(.phaseSwap)
                }
            case .cleaning: cleaning.transition(.phaseSwap)
            case .done: done.transition(.phaseSwap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Easing.out(0.25), value: flow.isReviewing)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            ModuleHero(module: module, size: 150)
            Text(module.title)
                .font(Typography.hero())
                .padding(.top, 6)
            Text(module.tagline)
                .font(.title3)
                .foregroundStyle(.textSecondary)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(module.highlights.enumerated()), id: \.offset) { _, item in
                    Label { Text(item.text) } icon: {
                        Image(systemName: item.symbol).foregroundStyle(.white).frame(width: 20)
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.textSecondary)
                }
            }
            .padding(.top, 22)

            if let notice = flow.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassSurface(cornerRadius: 12)
                    .padding(.top, 18)
                    .entrance(0)
            }
            if let blocked = app.cleaningBlockedReason {
                Label(blocked, systemImage: "exclamationmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.yellow)
                    .padding(.top, 18)
            } else if app.fullDiskAccess == .denied {
                FullDiskAccessHint().padding(.top, 18)
            }
            Spacer(minLength: 20)
            PrimaryCircleButton(title: "Scan", tint: accent, isEnabled: !flow.rules.isEmpty) { flow.startScan() }
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }

    // MARK: Scanning

    private var scanning: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                Text(flow.foundSize.bytesText)
                    .font(Typography.bigNumber())
                    .contentTransition(.numericText())
                Text("found so far")
                    .font(.title3)
                    .foregroundStyle(.textSecondary)
                Text("Checked \(flow.completedRules) of \(flow.totalRules) locations")
                    .font(.callout)
                    .foregroundStyle(.textTertiary)
                    .monospacedDigit()
                    .padding(.top, 6)
            }
            .entrance(0)

            Group {
                if flow.kind == .smartCare {
                    HStack(spacing: 12) {
                        ForEach(flow.groupProgress, id: \.key) { group in
                            TileProgress(info: group.info, done: group.done, total: group.total)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(flow.results.suffix(4)) { result in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(result.rule.localizedTitle)
                                Spacer()
                                Text(result.cleanableSize.bytesText).monospacedDigit().foregroundStyle(.textSecondary)
                            }
                            .font(.callout)
                            .transition(.opacity)
                        }
                    }
                    .frame(width: 360)
                }
            }
            .padding(.top, 28)
            .entrance(1)
            Spacer()
            PrimaryCircleButton(title: "Stop", tint: accent, progress: flow.scanProgress) { flow.cancelScan() }
                .padding(.bottom, 36)
        }
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            if flow.foundSize == 0 && !flow.groups.contains(where: \.needsAccess) && !extrasHaveNews {
                ModuleHero(module: module, size: 130, symbolOverride: "checkmark.seal").entrance(0)
                Text("Nothing to clean").font(Typography.hero(30)).entrance(1)
                Text("This part of your Mac is already tidy.")
                    .font(.title3).foregroundStyle(.textSecondary).padding(.top, 4)
                    .entrance(2)
            } else {
                VStack(spacing: 4) {
                    Text(flow.selectedSize.bytesText)
                        .font(Typography.bigNumber(flow.kind == .smartCare ? 56 : 64))
                        .contentTransition(.numericText())
                    Text("can be cleaned safely")
                        .font(.title3)
                        .foregroundStyle(.textSecondary)
                }
                .entrance(0)
                Text("Everything goes to the Restore Center for \(app.retentionDays) days. Disk space is freed when it leaves.")
                    .font(.callout)
                    .foregroundStyle(.textTertiary)
                    .padding(.top, 6)
                    .entrance(1)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12)], spacing: 12) {
                    ForEach(flow.groups) { group in
                        ResultTile(group: group) {
                            if group.needsAccess { app.isShowingOnboarding = true } else { flow.toggleGroup(group) }
                        }
                    }
                }
                .frame(maxWidth: 800)
                .padding(.top, flow.kind == .smartCare ? 16 : 26)
                .entrance(2)

                if flow.kind == .smartCare {
                    HStack(spacing: 12) {
                        ForEach(SmartCareExtras.Area.allCases) { area in
                            ExtraTile(extras: app.smartCareExtras, area: area) { app.selection = area.module }
                        }
                    }
                    .frame(maxWidth: 800)
                    .padding(.top, 10)
                    .entrance(3)
                }

                if flow.kind == .smartCare, let volume = flow.volumeAtResults {
                    DiskTile(volume: volume, cleanSize: flow.selectedSize)
                        .frame(maxWidth: 800)
                        .padding(.top, 10)
                        .entrance(3)
                }

                HStack(spacing: 10) {
                    Button("Review Details") { flow.isReviewing = true }
                        .buttonStyle(GhostButtonStyle())
                    if flow.skippedItemCount > 0 {
                        Text("\(flow.skippedItemCount) items skipped (in use or too recent)")
                            .font(.caption)
                            .foregroundStyle(.textTertiary)
                    }
                }
                .padding(.top, flow.kind == .smartCare ? 12 : 20)
                .entrance(4)
            }
            Spacer(minLength: 16)
            HStack(spacing: 24) {
                Button("Rescan") { flow.startScan() }.buttonStyle(GhostButtonStyle())
                PrimaryCircleButton(title: "Clean", tint: accent,
                                    isEnabled: (flow.selectedSize > 0 || (flow.kind == .smartCare && app.smartCareExtras.hasSelectedAction))
                                        && app.cleaningBlockedReason == nil) {
                    flow.clean()
                }
                Button("Cancel") { flow.finish() }.buttonStyle(GhostButtonStyle())
            }
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }

    /// Smart Care shows results (not "Nothing to clean") while its other tiles have something to say.
    private var extrasHaveNews: Bool {
        flow.kind == .smartCare && (app.smartCareExtras.hasAnyFinding || app.smartCareExtras.isCheckingProtection)
    }

    // MARK: Cleaning

    private var cleaning: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Moving \(flow.selectedSize.bytesText) to the Restore Center…")
                .font(.title3)
                .foregroundStyle(.textSecondary)
                .entrance(0)
            Spacer()
            PrimaryCircleButton(title: "Cleaning", tint: accent, progress: 0.25, isIndeterminate: true,
                                isEnabled: false) {}
                .padding(.bottom, 36)
        }
    }

    // MARK: Done

    private var done: some View {
        let outcome = flow.lastOutcome
        return VStack(spacing: 0) {
            Spacer(minLength: 16)
            ModuleHero(module: module, size: 140, symbolOverride: "checkmark.seal.fill").entrance(0)
            Text("\((outcome?.freedSize ?? 0).bytesText) cleaned")
                .font(Typography.bigNumber(48))
                .entrance(1)
            Text(flow.isReleased
                 ? "Released. The space is free now."
                 : "Moved to the Restore Center. You can restore it for \(app.retentionDays) days.")
                .font(.title3)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .padding(.top, 6)
                .entrance(2)

            if flow.kind == .smartCare, let extras = app.smartCareExtras.lastOutcome, !extras.isEmpty {
                ExtrasSummary(outcome: extras)
                    .frame(maxWidth: 520)
                    .padding(.top, 14)
                    .entrance(3)
            }

            if let operation = outcome?.operation, !flow.isReleased {
                ReleaseCard(size: operation.totalSize, retentionDays: app.retentionDays) { flow.freeUpNow() }
                    .frame(maxWidth: 520)
                    .padding(.top, 20)
                    .entrance(3)
            }

            HStack(spacing: 10) {
                if outcome?.operation != nil && !flow.isReleased {
                    Button { flow.undoLastClean() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(GhostButtonStyle())
                }
                Button { app.selection = .restoreCenter } label: {
                    Label("Open Restore Center", systemImage: "arrow.uturn.backward.circle")
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.top, 18)
            .entrance(4)

            if let skipped = outcome?.skipped, !skipped.isEmpty {
                SkippedSummary(items: skipped)
                    .frame(maxWidth: 520)
                    .padding(.top, 18)
                    .entrance(5)
            }
            Spacer(minLength: 16)
            PrimaryCircleButton(title: "Done", tint: accent) { flow.finish() }
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }
}

/// CleanMyMac-style result tile: small label, big number, short subtitle, a glass object in the
/// corner and a colour wash. Tapping toggles the whole category.
private struct ResultTile: View {
    let group: ScanFlowModel.GroupSummary
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        let radius = DesignTokens.shared.cardRadius
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(group.info.title)
                        .font(Typography.eyebrow)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if group.needsAccess {
                        Image(systemName: "lock.fill").foregroundStyle(.yellow.opacity(0.9))
                    } else {
                        IconSwap(isOn: group.isSelected, on: "checkmark.circle.fill", off: "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(group.isSelected ? .white : .textTertiary)
                    }
                }
                Spacer(minLength: 14)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        if group.needsAccess {
                            Text("Locked").font(Typography.tileNumber).lineLimit(1)
                            Text("Needs Full Disk Access").font(.caption).foregroundStyle(.yellow.opacity(0.9))
                        } else {
                            Text(group.isSelected ? group.selectedSize.bytesText : group.cleanableSize.bytesText)
                                .font(Typography.tileNumber)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText())
                            Text(group.isSelected ? "to clean" : "not selected")
                                .font(.caption)
                                .foregroundStyle(.textTertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    GlassGlyph(symbol: group.info.symbol, tint: group.info.tint, size: 46)
                        .opacity(group.isSelected || group.needsAccess ? 1 : 0.6)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
            .glassSurface(cornerRadius: radius,
                          wash: group.isSelected ? group.info.tint : nil,
                          isHighlighted: isHovering)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovering = $0 }
        .animation(Motion.hover, value: isHovering)
        .animation(Motion.hover, value: group.isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(group.isSelected ? .isSelected : [])
    }
}

/// Smart Care scan progress for one tile.
private struct TileProgress: View {
    let info: GroupInfo
    let done: Int
    let total: Int

    var body: some View {
        let finished = total > 0 && done >= total
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: total == 0 ? 1 : CGFloat(done) / CGFloat(total))
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Easing.out(0.3), value: done)
                IconSwap(isOn: finished, on: "checkmark", off: info.symbol)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(width: 52, height: 52)
            Text(info.title).font(.system(size: 12, weight: .medium))
        }
        .frame(width: 136)
        .padding(.vertical, 16)
        .glassSurface(wash: finished ? info.tint : nil)
        .animation(Motion.hover, value: finished)
    }
}

/// "Macintosh HD: 4.8 GB free → 9.7 GB after cleaning".
private struct DiskTile: View {
    let volume: VolumeInfo
    let cleanSize: Int64

    var body: some View {
        let after = min(volume.totalBytes, volume.availableBytes + cleanSize)
        HStack(spacing: 14) {
            GlassGlyph(symbol: "internaldrive", tint: .hex(0x8A9AB8), size: 40)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(volume.name).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(volume.availableBytes.bytesText) free").monospacedDigit().foregroundStyle(levelColor)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.textTertiary)
                    Text("\(after.bytesText) once released")
                        .monospacedDigit().fontWeight(.semibold)
                }
                .font(.system(size: 13))
                GeometryReader { proxy in
                    let total = max(Double(volume.totalBytes), 1)
                    let usedAfter = proxy.size.width * Double(volume.totalBytes - after) / total
                    let freed = proxy.size.width * Double(after - volume.availableBytes) / total
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        HStack(spacing: 0) {
                            Rectangle().fill(.white.opacity(0.85)).frame(width: usedAfter)
                            Rectangle().fill(Color.hex(0x4FCB98)).frame(width: freed)
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 6)
                Text("Cleaned items wait in the Restore Center on this disk. Their space frees up when they expire, or right away with Free Up Now.")
                    .font(.caption)
                    .foregroundStyle(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }

    private var levelColor: Color {
        switch volume.level {
        case .ok: .white
        case .low: .orange
        case .critical: .hex(0xFF6B6B)
        }
    }
}

/// Done-screen card: the cleaned items still occupy the disk until released.
private struct ReleaseCard: View {
    let size: Int64
    let retentionDays: Int
    let release: () -> Void
    @State private var isConfirming = false

    var body: some View {
        HStack(spacing: 14) {
            GlassGlyph(symbol: "externaldrive.badge.checkmark", tint: .hex(0x4FCB98), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(size.bytesText) is still on your disk").font(.system(size: 13, weight: .semibold))
                Text("It frees up in \(retentionDays) days, or now if you're sure.")
                    .font(.caption).foregroundStyle(.textSecondary)
            }
            Spacer(minLength: 8)
            Button("Free Up Now") { isConfirming = true }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 12)
        .glassSurface(cornerRadius: 22, wash: .hex(0x4FCB98))
        .sheet(isPresented: $isConfirming) {
            ConfirmSheet(
                symbol: "externaldrive.badge.minus",
                title: String(localized: "Free up \(size.bytesText) now?"),
                message: String(localized: "This deletes the cleaned items permanently so their space is free right away."),
                details: [
                    .init(symbol: "clock", text: String(localized: "Otherwise they free up by themselves in \(retentionDays) days")),
                    .init(symbol: "exclamationmark.triangle", text: String(localized: "You won't be able to restore them")),
                ],
                confirmTitle: String(localized: "Delete Permanently"),
                onConfirm: {
                    isConfirming = false
                    release()
                },
                onCancel: { isConfirming = false })
        }
    }
}

private struct SkippedSummary: View {
    let items: [SkippedItem]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.prefix(20)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.reason.symbol).frame(width: 16)
                        Text(item.path.abbreviatingHome).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(item.reason.text).foregroundStyle(.textTertiary)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("\(items.count) items were skipped")
                .font(.callout.weight(.medium))
        }
        .padding(12)
        .glassSurface(cornerRadius: 14)
    }
}

/// Inline hint shown when Full Disk Access is missing.
struct FullDiskAccessHint: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Concentric: 6 px inset around a capsule button → outer radius = 15 + 6.
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
            Text("Some locations need Full Disk Access.")
            Button("Grant Access") { app.isShowingOnboarding = true }
                .buttonStyle(GhostButtonStyle())
        }
        .font(.callout)
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .glassSurface(cornerRadius: 21)
    }
}

/// A compact Smart Care tile for Protection, Speed or Applications: what was found, whether Clean
/// will act on it (tick), and a way to review it in its module.
private struct ExtraTile: View {
    let extras: SmartCareExtras
    let area: SmartCareExtras.Area
    let review: () -> Void
    @State private var isHovering = false

    var body: some View {
        let module = area.module
        let hasAction = extras.hasAction(area)
        let isSelected = extras.isSelected(area)
        Button { if hasAction { extras.toggle(area) } } label: {
            HStack(alignment: .top, spacing: 10) {
                GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 30, isCompact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title).font(Typography.eyebrow).foregroundStyle(.textSecondary).lineLimit(1)
                    if extras.isReady(area) {
                        Text(headline).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Checking…").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(.textTertiary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 8) {
                    if hasAction {
                        IconSwap(isOn: isSelected, on: "checkmark.circle.fill", off: "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? .white : .textTertiary)
                    }
                    Button(action: review) { Image(systemName: "arrow.up.right") }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.textTertiary)
                        .opacity(isHovering ? 1 : 0.7)
                        .help(Text("Review in \(String(localized: module.title))"))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .glassSurface(cornerRadius: 18, wash: isSelected ? module.palette.accent : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var headline: String {
        switch area {
        case .protection:
            let harmful = extras.harmfulThreats.count, all = extras.visibleThreats.count
            if harmful > 0 { return String(localized: "\(harmful) likely harmful files") }
            if all > 0 { return String(localized: "\(all) files to look at") }
            return String(localized: "No threats found")
        case .speed:
            let due = extras.dueTasks.count
            return due > 0 ? String(localized: "\(due) tasks due") : String(localized: "Maintenance is up to date")
        case .applications:
            return extras.leftovers.isEmpty ? String(localized: "No app leftovers")
                : String(localized: "\(extras.leftoversSize.bytesText) of app leftovers")
        }
    }

    private var detail: String {
        switch area {
        case .protection:
            if !extras.isReady(area) { return String(localized: "Downloads, Desktop and Applications") }
            if !extras.harmfulThreats.isEmpty { return String(localized: "Clean moves them to the Restore Center") }
            if !extras.visibleThreats.isEmpty { return String(localized: "Nothing is moved without your review") }
            return String(localized: "Downloads, Desktop and Applications checked")
        case .speed:
            let startup = extras.startupAttention
            if startup > 0 { return String(localized: "\(startup) startup items need a look") }
            return extras.dueTasks.isEmpty ? String(localized: "Ran in the last 30 days")
                : String(localized: "Quick tasks that keep macOS snappy")
        case .applications:
            return extras.leftovers.isEmpty ? String(localized: "Removed apps left nothing behind")
                : String(localized: "From apps you removed · personal data kept")
        }
    }
}

/// What Smart Care's other tiles did, under the "cleaned" headline.
private struct ExtrasSummary: View {
    let outcome: SmartCareExtras.Outcome

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if outcome.movedThreats > 0 {
                line(SidebarModule.protection, String(localized: "Moved \(outcome.movedThreats) likely harmful files to the Restore Center"))
            }
            if outcome.ranTasks > 0 {
                line(SidebarModule.performance, String(localized: "Ran \(outcome.ranTasks) maintenance tasks"))
            }
            if outcome.removedLeftovers > 0 {
                line(SidebarModule.applications, String(localized: "Moved \(outcome.removedLeftovers.bytesText) of app leftovers to the Restore Center"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 18)
    }

    private func line(_ module: SidebarModule, _ text: String) -> some View {
        HStack(spacing: 8) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 20, isCompact: true)
            Text(text).font(.callout)
        }
    }
}
