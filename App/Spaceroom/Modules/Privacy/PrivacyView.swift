// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// Privacy: clear browsing traces and recent items (undoable), and review which apps hold sensitive permissions.
struct PrivacyView: View {
    @Bindable var model: PrivacyModel
    @Environment(AppModel.self) private var app
    @State private var isConfirming = false

    private let module = SidebarModule.privacy

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let result = model.lastResult { resultBanner(result).transition(.opacity) }
                    if model.isLoading && !model.hasLoaded {
                        HStack { Spacer(); ProgressView().controlSize(.large); Spacer() }.padding(40)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Browsing traces").font(.headline)
                            Text("Saved passwords and bookmarks are never touched. Everything you clear can be restored for \(app.retentionDays) days.")
                                .font(.caption).foregroundStyle(.textTertiary)
                        }
                        ForEach(model.owners) { owner in OwnerCard(model: model, owner: owner).entrance(0) }
                        if !model.lockedOwners.isEmpty { lockedCard.entrance(1) }
                        permissions.entrance(2)
                    }
                }
                .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 16)
            }
            .scrollIndicators(.never)
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .animation(Motion.hover, value: model.lastResult?.message)
        .onAppear {
            model.loadIfNeeded()
            model.refreshRunning()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshRunning()
        }
        .sheet(isPresented: $isConfirming) {
            let chosen = model.selectedItems
            ConfirmSheet(
                symbol: "hand.raised",
                title: String(localized: "Clear \(chosen.count) items?"),
                message: String(localized: "They move to the Restore Center, so you can bring them back for \(app.retentionDays) days."),
                details: Self.details(for: chosen),
                confirmTitle: String(localized: "Clear"),
                onConfirm: {
                    isConfirming = false
                    model.clearSelected()
                },
                onCancel: { isConfirming = false })
        }
    }

    static func details(for items: [PrivacyItem]) -> [ConfirmSheet.Detail] {
        var details = Dictionary(grouping: items, by: \.ownerName).sorted { $0.key < $1.key }.map { name, items in
            ConfirmSheet.Detail(symbol: "globe", text: "\(name): \(items.map { $0.kind.title }.joined(separator: ", "))")
        }
        if items.contains(where: { $0.kind.signsYouOut }) {
            details.append(.init(symbol: "person.crop.circle.badge.xmark", text: String(localized: "You'll be signed out of websites")))
        }
        return details
    }

    private var header: some View {
        HStack(spacing: 16) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.system(size: 22, weight: .bold))
                Text(model.hasLoaded
                     ? String(localized: "\(model.owners.count) sources · \(model.items.reduce(0) { $0 + $1.size }.bytesText) of traces")
                     : String(localized: "Looking for browsing traces…"))
                    .font(.callout).foregroundStyle(.textSecondary)
            }
            Spacer()
            Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(GhostButtonStyle()).help("Check again")
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

    private var lockedCard: some View {
        HStack(spacing: 12) {
            GlassGlyph(symbol: "lock.shield", tint: .hex(0xE0A93A), size: 34, isCompact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.lockedOwners.formatted(.list(type: .and))) need Full Disk Access").font(.system(size: 13, weight: .semibold))
                Text("macOS protects this data until you allow it.").font(.caption).foregroundStyle(.textTertiary)
            }
            Spacer()
            Button("Grant Access") { app.isShowingOnboarding = true }.buttonStyle(GhostButtonStyle())
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 10)
        .glassSurface(cornerRadius: 22, wash: .hex(0xE0A93A))
    }

    // MARK: Permissions

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("App permissions").font(.headline)
                Text("Which apps can use sensitive features. Spaceroom only shows them; change them in System Settings.")
                    .font(.caption).foregroundStyle(.textTertiary)
            }
            .padding(.top, 8)
            if model.grants == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Allow Full Disk Access to see which apps have each permission here. Meanwhile, open each list directly:")
                        .font(.callout).foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Equal tiles in an even grid: 9 services → 3 × 3.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(PermissionService.allCases, id: \.self) { service in
                            PermissionShortcut(service: service) { model.openSettings(service) }
                        }
                    }
                }
                .padding(16)
                .glassSurface()
            } else {
                VStack(spacing: 2) {
                    ForEach(PermissionService.allCases, id: \.self) { service in
                        PermissionRow(service: service, grants: model.grants(for: service)) { model.openSettings(service) }
                    }
                }
                .padding(6)
                .glassSurface()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.selectedItems.isEmpty ? String(localized: "Tick what you want to clear")
                 : String(localized: "\(model.selectedItems.count) selected · \(model.selectedSize.bytesText)"))
                .font(.callout).foregroundStyle(.textSecondary)
            Spacer()
            Button("Clear Selected") { isConfirming = true }
                .buttonStyle(FilledButtonStyle(tint: .hex(0xFF5A6E)))
                .disabled(model.selectedItems.isEmpty || model.isWorking || app.cleaningBlockedReason != nil)
        }
    }
}

private struct OwnerCard: View {
    let model: PrivacyModel
    let owner: PrivacyModel.Owner

    var body: some View {
        let running = model.isRunning(owner)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                icon.frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(owner.name).font(.system(size: 14, weight: .semibold))
                    Text(owner.size.bytesText).font(.caption).foregroundStyle(.textTertiary).monospacedDigit()
                }
                Spacer()
                if running {
                    Label("Still open", systemImage: "exclamationmark.circle").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    Button("Quit \(owner.name)") { model.quit(owner) }.buttonStyle(GhostButtonStyle())
                }
            }
            .padding(.horizontal, 8).padding(.top, 6)
            if running {
                Text("Quit it first: clearing a browser's data while it's open can damage it.")
                    .font(.caption).foregroundStyle(.textTertiary).padding(.horizontal, 8)
            }
            ForEach(owner.items) { item in
                ItemRow(item: item, isSelected: model.selection.contains(item.id) && !running,
                        showsProfile: Set(owner.items.map(\.profile)).count > 1) {
                    model.toggle(item)
                }
                .disabled(running)
                .opacity(running ? 0.5 : 1)
            }
        }
        .padding(6)
        .glassSurface()
    }

    @ViewBuilder
    private var icon: some View {
        if let bundleID = owner.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            GlassGlyph(symbol: "clock.arrow.circlepath", tint: SidebarModule.privacy.palette.accent, size: 28, isCompact: true)
        }
    }
}

private struct ItemRow: View {
    let item: PrivacyItem
    let isSelected: Bool
    let showsProfile: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                IconSwap(isOn: isSelected, on: "checkmark.square.fill", off: "square")
                    .font(.system(size: 15)).foregroundStyle(isSelected ? .white : .textTertiary)
                Image(systemName: item.kind.symbol).frame(width: 18).foregroundStyle(.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.kind.title).font(.system(size: 13, weight: .medium))
                        if showsProfile { Pill(text: Text(item.profile), tint: .white) }
                        if item.kind.signsYouOut { Pill(text: Text("Signs you out"), tint: .yellow) }
                    }
                    Text(item.kind.detail).font(.caption).foregroundStyle(.textTertiary)
                }
                Spacer()
                Text(item.size.bytesText).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One "open this list in System Settings" tile. Fills its grid cell so every tile lines up.
private struct PermissionShortcut: View {
    let service: PermissionService
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: service.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(.textSecondary)
                Text(service.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.textTertiary)
                    .opacity(isHovering ? 1 : 0.6)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            // Concentric with the card: 16 pt inset inside a ~28 pt radius → 12 pt.
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(isHovering ? 0.13 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovering = $0 }
        .animation(Motion.hover, value: isHovering)
        .help(Text("Open \(service.title) in System Settings"))
    }
}

private struct PermissionRow: View {
    let service: PermissionService
    let grants: [PermissionGrant]
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: service.symbol).frame(width: 22).foregroundStyle(.textSecondary)
            Text(service.title).font(.system(size: 13, weight: .medium)).frame(width: 150, alignment: .leading)
            if grants.isEmpty {
                Text("No apps").font(.caption).foregroundStyle(.textTertiary)
            } else {
                HStack(spacing: -4) {
                    ForEach(grants.prefix(8)) { grant in
                        Group {
                            if let icon = PrivacyModel.clientIcon(grant.client) { Image(nsImage: icon).resizable() }
                            else { Image(systemName: "app").resizable().foregroundStyle(.textTertiary) }
                        }
                        .frame(width: 22, height: 22)
                        .help(PrivacyModel.clientName(grant.client))
                    }
                }
                Text(grants.count == 1 ? PrivacyModel.clientName(grants[0].client) : String(localized: "\(grants.count) apps"))
                    .font(.caption).foregroundStyle(.textSecondary).lineLimit(1)
            }
            Spacer()
            Button("Review") { open() }.buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

extension PrivacyKind {
    var title: String {
        switch self {
        case .history: String(localized: "History")
        case .cookies: String(localized: "Cookies")
        case .autofill: String(localized: "Form autofill")
        case .downloads: String(localized: "Download history")
        case .recentItems: String(localized: "Recent items")
        }
    }

    var detail: String {
        switch self {
        case .history: String(localized: "Visited pages, suggestions and most-visited sites")
        case .cookies: String(localized: "Logins and site settings stored by websites")
        case .autofill: String(localized: "Things you typed into web forms")
        case .downloads: String(localized: "The list of files you downloaded (not the files)")
        case .recentItems: String(localized: "Recent documents, apps and servers in menus")
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .cookies: "birthday.cake"
        case .autofill: "character.cursor.ibeam"
        case .downloads: "arrow.down.circle"
        case .recentItems: "list.bullet.rectangle"
        }
    }
}

extension PermissionService {
    var title: String {
        switch self {
        case .camera: String(localized: "Camera")
        case .microphone: String(localized: "Microphone")
        case .screenRecording: String(localized: "Screen Recording")
        case .fullDiskAccess: String(localized: "Full Disk Access")
        case .accessibility: String(localized: "Accessibility")
        case .inputMonitoring: String(localized: "Input Monitoring")
        case .contacts: String(localized: "Contacts")
        case .calendars: String(localized: "Calendars")
        case .photos: String(localized: "Photos")
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .microphone: "mic"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .fullDiskAccess: "externaldrive"
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        case .contacts: "person.crop.circle"
        case .calendars: "calendar"
        case .photos: "photo"
        }
    }
}
