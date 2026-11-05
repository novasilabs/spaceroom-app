// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// App updates, checked only when the user asks. Spaceroom never downloads or installs
/// updates itself: the app's own updater or the App Store does, and both verify the developer.
struct UpdatesPane: View {
    @Bindable var model: ApplicationsModel

    var body: some View {
        VStack(spacing: 0) {
            if let result = model.updateResult, !model.isCheckingUpdates {
                if result.updates.isEmpty {
                    empty(result)
                } else {
                    list(result)
                }
            } else {
                intro
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 20)
    }

    private var intro: some View {
        VStack(spacing: 12) {
            GlassGlyph(symbol: "arrow.down.app", tint: SidebarModule.applications.palette.accent, size: 60)
            Text("Check your apps for updates").font(.title3.weight(.semibold))
            Text("Spaceroom asks each app's own update server, and Apple for App Store apps. Only the request and the apps' bundle IDs are sent, and only when you click Check for Updates.")
                .font(.callout).foregroundStyle(.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            if model.isCheckingUpdates {
                ProgressView().controlSize(.small).padding(.top, 6)
            } else {
                Button("Check for Updates") { model.checkForUpdates() }
                    .buttonStyle(FilledButtonStyle(tint: SidebarModule.applications.palette.accent))
                    .disabled(!model.hasLoaded)
                    .padding(.top, 6)
            }
        }
        .padding(30)
    }

    private func empty(_ result: UpdateCheckResult) -> some View {
        VStack(spacing: 10) {
            GlassGlyph(symbol: "checkmark.seal", tint: SidebarModule.applications.palette.accent, size: 56)
            Text("Your apps are up to date").font(.title3.weight(.semibold))
            footnote(result)
            Button("Check Again") { model.checkForUpdates() }.buttonStyle(GhostButtonStyle())
        }
        .padding(30)
    }

    private func list(_ result: UpdateCheckResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(result.updates.count) updates available").font(.system(size: 14, weight: .semibold))
                Spacer()
                footnote(result)
                Button { model.checkForUpdates() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(GhostButtonStyle())
                    .help("Check Again")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(result.updates) { update in
                        UpdateRow(update: update) { model.openForUpdate(update) }
                    }
                }
                .padding(6)
            }
        }
    }

    private func footnote(_ result: UpdateCheckResult) -> some View {
        Group {
            if result.failed > 0 {
                Text("\(result.checked) apps checked · \(result.failed) couldn't be reached")
            } else {
                Text("\(result.checked) apps checked")
            }
        }
        .font(.caption).foregroundStyle(.textTertiary)
        .help("Apps that publish an update feed or come from the App Store can be checked. Others update themselves.")
    }
}

private struct UpdateRow: View {
    let update: AppUpdate
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: update.app.url.path))
                .resizable().frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(update.app.name).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Text("\(update.installedVersion) → \(update.availableVersion)").monospacedDigit()
                    Text("·")
                    Text(isAppStore ? "App Store" : "From the developer")
                }
                .font(.caption).foregroundStyle(.textSecondary)
            }
            Spacer()
            if case .sparkle(let notes?) = update.channel {
                Button("Release Notes") { NSWorkspace.shared.open(notes) }.buttonStyle(GhostButtonStyle())
            }
            Button(isAppStore ? String(localized: "Open App Store") : String(localized: "Open to Update"), action: open)
                .buttonStyle(GhostButtonStyle())
                .help(isAppStore ? String(localized: "Updates install from the App Store")
                                 : String(localized: "Opens the app; its own updater installs the update and checks the developer's signature"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var isAppStore: Bool {
        if case .appStore = update.channel { return true }
        return false
    }
}
