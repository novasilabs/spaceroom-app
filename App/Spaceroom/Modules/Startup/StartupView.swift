// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// Startup & Background: security overview, items that need attention, then everything else by owner.
struct StartupView: View {
    @Bindable var model: StartupModel
    @Environment(AppModel.self) private var app
    @State private var confirming: StartupModel.Entry?

    private let module = SidebarModule.startup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let result = model.lastResult { resultBanner(result).transition(.opacity) }
                PostureStrip(posture: model.posture, open: model.openSettings)
                if model.isLoading && !model.hasLoaded {
                    HStack { Spacer(); ProgressView().controlSize(.large); Spacer() }.padding(40)
                } else {
                    if !model.attention.isEmpty {
                        section(String(localized: "Needs attention"), entries: model.attention,
                                note: String(localized: "Leftovers of removed apps, empty jobs, and anything unsigned or running from an unusual place."))
                    }
                    section(String(localized: "Your launch agents"), entries: model.entries(in: [.user]),
                            note: String(localized: "Run when you log in. You can remove these."))
                    section(String(localized: "For all users"), entries: model.entries(in: [.allUsers, .system]),
                            note: String(localized: "Installed system-wide. Changing them needs admin rights (coming with Spaceroom's helper)."))
                    section(String(localized: "Inside apps"), entries: model.entries(in: [.insideApp]),
                            note: String(localized: "Helpers shipped inside apps. macOS manages these under Login Items."))
                    loginItemsCard
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .animation(Motion.hover, value: model.lastResult?.message)
        .onAppear { model.loadIfNeeded() }
        .sheet(item: $confirming) { entry in
            ConfirmSheet(
                symbol: "power",
                title: String(localized: "Remove \(entry.displayName)?"),
                message: String(localized: "Spaceroom stops it now and moves its launch file to the Restore Center. Restoring it brings it back at your next login."),
                details: [
                    .init(symbol: "doc", text: entry.item.url.path.abbreviatingHome),
                    .init(symbol: "info.circle", text: entry.findings.first.map(Self.findingText) ?? String(localized: "Runs at login")),
                ],
                confirmTitle: String(localized: "Remove"),
                onConfirm: {
                    confirming = nil
                    model.remove(entry)
                },
                onCancel: { confirming = nil })
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.system(size: 22, weight: .bold))
                Text(model.hasLoaded
                     ? String(localized: "\(model.entries.count) items · \(model.attention.count) need attention")
                     : String(localized: "Looking at what runs in the background…"))
                    .font(.callout).foregroundStyle(.textSecondary)
            }
            Spacer()
            Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(GhostButtonStyle())
                .help("Check again")
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
                .buttonStyle(.plain).foregroundStyle(.textSecondary)
                .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8)
        .glassSurface(cornerRadius: 18, wash: .hex(0x4FCB98))
    }

    @ViewBuilder
    private func section(_ title: String, entries: [StartupModel.Entry], note: String) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline)
                    Text("\(entries.count)").font(.caption.weight(.semibold)).foregroundStyle(.textTertiary)
                    Spacer()
                }
                Text(note).font(.caption).foregroundStyle(.textTertiary)
                VStack(spacing: 2) {
                    ForEach(entries) { entry in
                        LaunchRow(entry: entry, isWorking: model.isWorking) { confirming = entry }
                    }
                }
                .padding(6)
                .glassSurface()
            }
        }
    }

    private var loginItemsCard: some View {
        HStack(spacing: 12) {
            GlassGlyph(symbol: "person.crop.circle.badge.checkmark", tint: module.palette.accent, size: 34, isCompact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apps that open at login").font(.system(size: 13, weight: .semibold))
                Text("macOS keeps this list private, so it's managed in System Settings.")
                    .font(.caption).foregroundStyle(.textTertiary)
            }
            Spacer()
            Button("Open Login Items") { model.openSettings("com.apple.LoginItems-Settings.extension") }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 10)
        .glassSurface(cornerRadius: 22)
    }

    static func findingText(_ finding: LaunchFinding) -> String {
        switch finding {
        case .programMissing: String(localized: "The program it starts no longer exists")
        case .appRemoved(let app): String(localized: "Belongs to \(app), which is no longer installed")
        case .emptyJob: String(localized: "Empty: does nothing, safe to remove")
        case .unsigned: String(localized: "The program isn't signed by a known developer")
        case .unusualLocation(let place): String(localized: "Runs from an unusual place: \(place)")
        }
    }
}

private struct LaunchRow: View {
    let entry: StartupModel.Entry
    let isWorking: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    signatureBadge
                    if entry.isLoaded { Pill(text: Text("Running"), tint: .hex(0x4FCB98)) }
                    if entry.item.runsAtLoad { Pill(text: Text("At login"), tint: .white) }
                }
                Text(entry.item.program?.abbreviatingHome ?? entry.item.url.path.abbreviatingHome)
                    .font(.caption).foregroundStyle(.textTertiary).lineLimit(1).truncationMode(.middle)
                ForEach(entry.findings, id: \.self) { finding in
                    Label(StartupView.findingText(finding),
                          systemImage: finding.isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(finding.isWarning ? Color.orange : Color.hex(0xF2C94C))
                }
            }
            Spacer(minLength: 8)
            if entry.item.isRemovableByUser {
                Button("Remove", action: remove)
                    .buttonStyle(GhostButtonStyle())
                    .disabled(isWorking)
            } else {
                Button { Finder.reveal(entry.item.url) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(GhostButtonStyle())
                    .help("Show in Finder")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .contextMenu {
            Button("Show Launch File in Finder") { Finder.reveal(entry.item.url) }
            if let program = entry.item.program, FileManager.default.fileExists(atPath: program) {
                Button("Show Program in Finder") { Finder.reveal(URL(fileURLWithPath: program)) }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let app = entry.item.containingApp, FileManager.default.fileExists(atPath: app) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app)).resizable()
        } else {
            GlassGlyph(symbol: entry.item.scope == .system ? "gearshape.2" : "power",
                       tint: SidebarModule.startup.palette.accent, size: 26, isCompact: true)
        }
    }

    @ViewBuilder
    private var signatureBadge: some View {
        switch entry.signature {
        case .apple: Pill(text: Text("Apple"), tint: .white)
        case .developer(let team): Pill(text: Text("Signed · \(team)"), tint: .white).help("Developer ID team \(team)")
        case .adHoc: Pill(text: Text("Ad-hoc signed"), tint: .orange)
        case .unsigned: Pill(text: Text("Unsigned"), tint: .orange)
        case .invalid: Pill(text: Text("Broken signature"), tint: .orange)
        case nil: EmptyView()
        }
    }
}

/// SIP, Gatekeeper, FileVault, Firewall and XProtect at a glance, with a way to fix what's off.
struct PostureStrip: View {
    let posture: SecurityPosture?
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            chip("System Integrity Protection", short: "SIP", on: posture?.systemIntegrityProtection, fix: nil)
            chip("Gatekeeper", short: "Gatekeeper", on: posture?.gatekeeper, fix: nil)
            chip("FileVault disk encryption", short: "FileVault", on: posture?.fileVault,
                 fix: "com.apple.preference.security?FileVault")
            chip("Firewall", short: "Firewall", on: posture?.firewall, fix: "com.apple.Network-Settings.extension?Firewall")
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(.textSecondary)
                Text(posture?.xprotectVersion.map { "XProtect \($0)" } ?? "XProtect").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .glassSurface(cornerRadius: 15)
            .help("Apple's built-in malware signatures, updated automatically")
            Spacer(minLength: 0)
        }
    }

    private func chip(_ help: LocalizedStringResource, short: LocalizedStringResource, on: Bool?, fix: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: on == true ? "checkmark.circle.fill" : on == false ? "exclamationmark.circle.fill" : "circle.dotted")
                .foregroundStyle(on == true ? Color.hex(0x4FCB98) : on == false ? Color.orange : Color.white.opacity(0.4))
            Text(short).font(.system(size: 12, weight: .semibold))
            if on == false, let fix {
                Button("Turn On") { open(fix) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .glassSurface(cornerRadius: 15, wash: on == false ? .orange : nil)
        .help(Text(help))
    }
}
