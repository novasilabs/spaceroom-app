// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// Protection: Mac security at a glance, then a scan for disguised and tampered files.
struct ProtectionView: View {
    @Bindable var model: ProtectionModel
    @Environment(AppModel.self) private var app
    @State private var isConfirming = false

    private let module = SidebarModule.protection

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    PostureStrip(posture: app.startup.posture, open: app.startup.openSettings)
                    if let result = model.lastResult { resultBanner(result) }
                    switch model.phase {
                    case .intro: intro.entrance(0)
                    case .scanning: scanning
                    case .results: results
                    }
                }
                .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 16)
            }
            .scrollIndicators(.never)
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .animation(Motion.hover, value: model.lastResult?.message)
        .onAppear { app.startup.loadIfNeeded() }
        .sheet(isPresented: $isConfirming) {
            let chosen = model.selectedFindings
            ConfirmSheet(
                symbol: "checkmark.shield",
                title: String(localized: "Move \(chosen.count) items to the Restore Center?"),
                message: String(localized: "They leave your folders now and can be restored for \(app.retentionDays) days if one turns out to be fine."),
                details: Dictionary(grouping: chosen, by: \.kind).sorted { $0.value.count > $1.value.count }.map { kind, items in
                    ConfirmSheet.Detail(symbol: kind.symbol, text: "\(kind.title): \(items.count)")
                },
                confirmTitle: String(localized: "Move to Restore Center"),
                onConfirm: {
                    isConfirming = false
                    model.removeSelected()
                },
                onCancel: { isConfirming = false })
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
        if let date = model.lastScanDate {
            let checked = date.formatted(.relative(presentation: .named))
            return model.lastScanCount == 0 ? String(localized: "Nothing suspicious · checked \(checked)")
                : String(localized: "\(model.lastScanCount) items need a look · checked \(checked)")
        }
        return String(localized: "Not checked yet")
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the scan looks for").font(.headline)
            VStack(spacing: 2) {
                ForEach([ThreatKind.disguisedProgram, .deceptiveName, .hiddenPayload, .activePDF, .unsignedApp, .downloadedScript],
                        id: \.self) { kind in
                    HStack(alignment: .top, spacing: 12) {
                        GlassGlyph(symbol: kind.symbol, tint: module.palette.accent, size: 28, isCompact: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.system(size: 13, weight: .semibold))
                            Text(kind.explanation).font(.caption).foregroundStyle(.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 8)
                }
            }
            .padding(6)
            .glassSurface()
            Text("It checks Downloads, Desktop, Documents, iCloud Drive and your Applications folder by reading file headers. Nothing is opened or run. This isn't an antivirus: it spots common disguises, not every threat. macOS's own XProtect keeps running alongside it.")
                .font(.caption).foregroundStyle(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scanning: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Checked \(model.scannedFiles) files…").font(.callout).monospacedDigit().foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if let report = model.report {
            if !report.lockedRoots.isEmpty {
                notice(symbol: "lock.shield", tint: .hex(0xE0A93A),
                       title: String(localized: "Some folders couldn't be checked"),
                       detail: report.lockedRoots.map { $0.path.abbreviatingHome }.joined(separator: ", "),
                       action: (String(localized: "Grant Access"), { app.isShowingOnboarding = true }))
            }
            if model.findings.isEmpty {
                VStack(spacing: 12) {
                    GlassGlyph(symbol: "checkmark.shield.fill", tint: .hex(0x4FCB98), size: 56)
                    Text("Nothing suspicious found").font(.system(size: 17, weight: .semibold))
                    Text("Checked \(report.scannedFiles) files\(report.wasTruncated ? String(localized: " (stopped at the limit)") : "").")
                        .font(.callout).foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .glassSurface()
                .entrance(0)
            } else {
                ForEach(Array([ThreatSeverity.high, .medium, .low].enumerated()), id: \.element) { index, severity in
                    let items = model.findings(severity)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle().fill(severity.tint).frame(width: 8, height: 8)
                                Text(severity.title).font(.headline)
                                Text("\(items.count)").font(.headline).foregroundStyle(.textTertiary)
                            }
                            .padding(.top, 6)
                            VStack(spacing: 2) {
                                ForEach(items) { finding in
                                    FindingRow(finding: finding, isSelected: model.selection.contains(finding.id),
                                               toggle: { model.toggle(finding) }, reveal: { model.reveal(finding) },
                                               ignore: { model.ignore(finding) })
                                }
                            }
                            .padding(6)
                            .glassSurface(wash: severity == .high ? severity.tint : nil)
                        }
                        .entrance(index)
                    }
                }
                Text("Checked \(report.scannedFiles) files. Ticked items move to the Restore Center; nothing is deleted outright.")
                    .font(.caption).foregroundStyle(.textTertiary)
            }
            if model.ignoredCount > 0 {
                Button("Show \(model.ignoredCount) ignored items again") { model.clearIgnored() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.textSecondary)
            }
        }
    }

    private func resultBanner(_ result: (message: String, operationID: UUID?)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(result.message).font(.callout.weight(.medium))
            Spacer()
            if result.operationID != nil {
                Button { model.undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(GhostButtonStyle())
            }
            Button { model.dismissResult() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.textSecondary).accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8)
        .glassSurface(cornerRadius: 18, wash: .hex(0x4FCB98))
    }

    private func notice(symbol: String, tint: Color, title: String, detail: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 12) {
            GlassGlyph(symbol: symbol, tint: tint, size: 34, isCompact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.textTertiary).lineLimit(2)
            }
            Spacer()
            if let action { Button(action.0, action: action.1).buttonStyle(GhostButtonStyle()) }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 10)
        .glassSurface(cornerRadius: 22, wash: tint)
    }

    private var footer: some View {
        HStack {
            switch model.phase {
            case .scanning:
                Text("Reading file headers only. Nothing is opened.").font(.callout).foregroundStyle(.textSecondary)
                Spacer()
                Button("Stop") { model.cancelScan() }.buttonStyle(GhostButtonStyle())
            case .intro, .results:
                Text(model.selectedFindings.isEmpty
                     ? (model.phase == .intro ? String(localized: "Takes a minute or two") : String(localized: "Tick what you want to move"))
                     : String(localized: "\(model.selectedFindings.count) selected · \(model.selectedSize.bytesText)"))
                    .font(.callout).foregroundStyle(.textSecondary)
                Spacer()
                if model.phase == .results && !model.findings.isEmpty {
                    Button("Move to Restore Center") { isConfirming = true }
                        .buttonStyle(FilledButtonStyle(tint: .hex(0xFF5A6E)))
                        .disabled(model.selectedFindings.isEmpty || model.isWorking || app.cleaningBlockedReason != nil)
                }
                Button(model.phase == .intro ? "Scan" : "Scan Again") { model.startScan() }
                    .buttonStyle(model.phase == .intro ? AnyButtonStyle(FilledButtonStyle(tint: module.palette.accent))
                                 : AnyButtonStyle(GhostButtonStyle()))
            }
        }
    }
}

private struct FindingRow: View {
    let finding: ThreatFinding
    let isSelected: Bool
    let toggle: () -> Void
    let reveal: () -> Void
    let ignore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggle) {
                IconSwap(isOn: isSelected, on: "checkmark.square.fill", off: "square")
                    .font(.system(size: 15)).foregroundStyle(isSelected ? .white : .textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityLabel(Text(finding.url.lastPathComponent))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Image(nsImage: NSWorkspace.shared.icon(forFile: finding.url.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(finding.url.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        .truncationMode(.middle)
                    if finding.isFromInternet { Pill(text: Text("Downloaded"), tint: .white) }
                }
                Label(finding.kind.title, systemImage: finding.kind.symbol)
                    .font(.caption.weight(.medium)).foregroundStyle(finding.severity.tint)
                Text(finding.evidence).font(.caption).foregroundStyle(.textSecondary)
                Text(finding.kind.explanation).font(.caption).foregroundStyle(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.url.deletingLastPathComponent().path.abbreviatingHome)
                    .font(.caption2).foregroundStyle(.textTertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(finding.size.bytesText).font(.system(size: 12, weight: .semibold)).monospacedDigit().padding(.top, 6)
            Menu {
                Button("Show in Finder", systemImage: "folder", action: reveal)
                Button("Ignore", systemImage: "eye.slash", action: ignore)
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(.textSecondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.top, 5)
            .accessibilityLabel(Text("More"))
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// Lets one button switch between two styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
