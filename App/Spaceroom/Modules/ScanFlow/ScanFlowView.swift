// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// The CleanMyMac-style module page: one illustrated screen per phase, one big button.
struct ScanFlowView: View {
    let module: SidebarModule
    @Bindable var flow: ScanFlowModel
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            switch flow.phase {
            case .intro: intro.transition(.phase)
            case .scanning: scanning.transition(.phase)
            case .results:
                if flow.isReviewing {
                    ReviewView(module: module, flow: flow).transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    results.transition(.phase)
                }
            case .cleaning: cleaning.transition(.phase)
            case .done: done.transition(.phase)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.45), value: flow.isReviewing)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            ModuleHero(module: module, size: 190)
            Text(module.title)
                .font(Typography.hero())
                .padding(.top, 8)
            Text(module.tagline)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(module.highlights.enumerated()), id: \.offset) { _, item in
                    Label { Text(item.text) } icon: { Image(systemName: item.symbol).frame(width: 20) }
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.top, 22)

            if let notice = flow.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassSurface(cornerRadius: 10)
                    .padding(.top, 18)
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
            PrimaryCircleButton(title: "Scan", isEnabled: !flow.rules.isEmpty) { flow.startScan() }
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
    }

    // MARK: Scanning

    private var scanning: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(flow.foundSize.bytesText)
                .font(Typography.bigNumber())
                .contentTransition(.numericText())
                .monospacedDigit()
            Text("found so far")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
            Text("Checked \(flow.completedRules) of \(flow.totalRules) locations")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 10)
                .monospacedDigit()
            if flow.kind == .smartCare {
                HStack(spacing: 14) {
                    ForEach(flow.groupProgress, id: \.key) { group in
                        TileProgress(info: group.info, done: group.done, total: group.total)
                    }
                }
                .padding(.top, 26)
            } else {
            VStack(spacing: 8) {
                ForEach(flow.results.suffix(4)) { result in
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(result.rule.title)
                        Spacer()
                        Text(result.cleanableSize.bytesText).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.callout)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: 360)
            .padding(.top, 26)
            }
            Spacer()
            PrimaryCircleButton(title: "Stop", progress: flow.scanProgress) { flow.cancelScan() }
                .padding(.bottom, 40)
        }
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            if flow.foundSize == 0 && !flow.groups.contains(where: \.needsAccess) {
                ModuleHero(module: module, size: 150, symbolOverride: "checkmark.seal")
                Text("Nothing to clean")
                    .font(Typography.hero(30))
                Text("This part of your Mac is already tidy.")
                    .font(.title3).foregroundStyle(.white.opacity(0.75)).padding(.top, 4)
            } else {
                Text(flow.selectedSize.bytesText)
                    .font(Typography.bigNumber(64))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text("can be cleaned safely")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Everything goes to the Restore Center and is kept for \(app.retentionDays) days.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 6)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)], spacing: 14) {
                    ForEach(flow.groups) { group in
                        GroupCard(group: group) {
                            if group.needsAccess { app.isShowingOnboarding = true } else { flow.toggleGroup(group) }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(.top, 28)

                if flow.kind == .smartCare, let volume = flow.volumeAtResults {
                    DiskTile(volume: volume, cleanSize: flow.selectedSize)
                        .frame(maxWidth: 760)
                        .padding(.top, 14)
                }

                HStack(spacing: 10) {
                    Button("Review Details") { flow.isReviewing = true }
                        .buttonStyle(GhostButtonStyle())
                    if flow.skippedItemCount > 0 {
                        Text("\(flow.skippedItemCount) items skipped (in use or too recent)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.top, 22)
            }
            Spacer(minLength: 16)
            HStack(spacing: 28) {
                Button("Rescan") { flow.startScan() }.buttonStyle(GhostButtonStyle())
                PrimaryCircleButton(title: "Clean",
                                    isEnabled: flow.selectedSize > 0 && app.cleaningBlockedReason == nil) {
                    flow.clean()
                }
                Button("Cancel") { flow.finish() }.buttonStyle(GhostButtonStyle())
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
    }

    // MARK: Cleaning

    private var cleaning: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Moving \(flow.selectedSize.bytesText) to the Restore Center…")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            PrimaryCircleButton(title: "Cleaning", progress: 0.25, isIndeterminate: true, isEnabled: false) {}
                .padding(.bottom, 40)
        }
    }

    // MARK: Done

    private var done: some View {
        let outcome = flow.lastOutcome
        return VStack(spacing: 0) {
            Spacer(minLength: 16)
            ModuleHero(module: module, size: 160, symbolOverride: "checkmark.seal.fill")
            Text("\((outcome?.freedSize ?? 0).bytesText) cleaned")
                .font(Typography.bigNumber(48))
            Text("Moved to the Restore Center. You can restore it for \(app.retentionDays) days.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            HStack(spacing: 10) {
                if outcome?.operation != nil {
                    Button { flow.undoLastClean() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(GhostButtonStyle())
                }
                Button { app.selection = .restoreCenter } label: {
                    Label("Open Restore Center", systemImage: "arrow.uturn.backward.circle")
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.top, 22)

            if let skipped = outcome?.skipped, !skipped.isEmpty {
                SkippedSummary(items: skipped)
                    .frame(maxWidth: 520)
                    .padding(.top, 22)
            }
            Spacer(minLength: 16)
            PrimaryCircleButton(title: "Done") { flow.finish() }
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
    }
}

private struct GroupCard: View {
    let group: ScanFlowModel.GroupSummary
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: group.info.symbol)
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.14)))
                    Spacer()
                    Image(systemName: group.needsAccess ? "lock.fill"
                          : group.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(group.isSelected ? .white : .white.opacity(0.5))
                }
                Text(group.info.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if group.needsAccess {
                    Text("Needs Full Disk Access")
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow.opacity(0.9))
                } else {
                    Text(group.isSelected ? group.selectedSize.bytesText : group.cleanableSize.bytesText)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(group.isSelected ? 0.85 : 0.5))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 16, tint: group.isSelected ? 0.12 : 0.03)
            .opacity(group.isSelected ? 1 : 0.75)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(group.isSelected ? .isSelected : [])
    }
}

/// Smart Care scan progress for one tile.
private struct TileProgress: View {
    let info: GroupInfo
    let done: Int
    let total: Int

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: total == 0 ? 1 : CGFloat(done) / CGFloat(total))
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: done)
                Image(systemName: done == total ? "checkmark" : info.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 56, height: 56)
            Text(info.title).font(.system(size: 12, weight: .medium))
        }
        .frame(width: 130)
        .padding(.vertical, 14)
        .glassSurface(cornerRadius: 14)
    }
}

/// "Macintosh HD: 4.8 GB free → 9.7 GB after Smart Care".
private struct DiskTile: View {
    let volume: VolumeInfo
    let cleanSize: Int64

    var body: some View {
        let after = min(volume.totalBytes, volume.availableBytes + cleanSize)
        HStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(volume.name).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(volume.availableBytes.bytesText).monospacedDigit().foregroundStyle(levelColor)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.white.opacity(0.6))
                    Text("\(after.bytesText) free after cleaning")
                        .monospacedDigit().fontWeight(.semibold)
                }
                .font(.system(size: 13))
                GeometryReader { proxy in
                    let total = max(Double(volume.totalBytes), 1)
                    let usedAfter = proxy.size.width * Double(volume.totalBytes - after) / total
                    let freed = proxy.size.width * Double(after - volume.availableBytes) / total
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        HStack(spacing: 0) {
                            Rectangle().fill(.white.opacity(0.85)).frame(width: usedAfter)
                            Rectangle().fill(.green.opacity(0.85)).frame(width: freed)
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 7)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 16, tint: 0.06)
        .accessibilityElement(children: .combine)
    }

    private var levelColor: Color {
        switch volume.level {
        case .ok: .white
        case .low: .orange
        case .critical: .red
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
                        Text(item.reason.text).foregroundStyle(.white.opacity(0.6))
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
        .glassSurface(cornerRadius: 12)
    }
}

/// Inline hint shown when Full Disk Access is missing.
struct FullDiskAccessHint: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
            Text("Some locations need Full Disk Access.")
            Button("Grant Access") { app.isShowingOnboarding = true }
                .buttonStyle(GhostButtonStyle())
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassSurface(cornerRadius: 12)
    }
}

extension AnyTransition {
    static var phase: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .opacity.combined(with: .scale(scale: 1.02)))
    }
}
