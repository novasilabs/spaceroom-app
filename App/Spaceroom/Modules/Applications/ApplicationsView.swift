// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// Uninstaller: app list on the left, the selected app and its leftovers on the right.
struct ApplicationsView: View {
    @Bindable var model: ApplicationsModel
    @Environment(AppModel.self) private var app
    @State private var isConfirmingUninstall = false
    @State private var isConfirmingOrphans = false

    private let module = SidebarModule.applications

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 14)
            if let result = model.lastResult {
                resultBanner(result)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
            Group {
                switch model.tab {
                case .installed: installed
                case .leftovers: leftovers
                case .updates: UpdatesPane(model: model)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .animation(Motion.hover, value: model.lastResult?.message)
        .onAppear { model.loadIfNeeded() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.system(size: 22, weight: .bold))
                Text(model.isLoading
                     ? String(localized: "Looking for apps…")
                     : String(localized: "\(model.rows.count) apps · \(model.totalAppsSize.bytesText)"))
                    .font(.callout).foregroundStyle(.textSecondary).monospacedDigit()
            }
            Spacer()
            Picker("", selection: $model.tab) {
                Text("Installed").tag(ApplicationsModel.Tab.installed)
                Text(model.orphans.isEmpty ? "Leftovers" : "Leftovers · \(model.orphansSize.bytesText)")
                    .tag(ApplicationsModel.Tab.leftovers)
                Text(model.updateResult.map { $0.updates.isEmpty ? String(localized: "Updates") : String(localized: "Updates · \($0.updates.count)") }
                     ?? String(localized: "Updates"))
                    .tag(ApplicationsModel.Tab.updates)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
        }
    }

    private func resultBanner(_ result: (message: String, operationID: UUID?)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(result.message).font(.callout.weight(.medium)).lineLimit(2)
            Spacer()
            if result.operationID != nil {
                Button { model.undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(GhostButtonStyle())
            }
            Button { model.dismissResult() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.textSecondary)
                .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8)
        .glassSurface(cornerRadius: 18, wash: .hex(0x4FCB98))
    }

    // MARK: Installed

    private var installed: some View {
        HStack(alignment: .top, spacing: 16) {
            appList.frame(minWidth: 300, maxWidth: 380)
            Group {
                if let row = model.selectedRow, model.isSelf(row.app) {
                    SelfAppDetail(row: row)
                } else if let row = model.selectedRow {
                    AppDetail(model: model, row: row) { isConfirmingUninstall = true }
                } else if model.isLoading {
                    placeholder(ProgressView().controlSize(.large))
                } else {
                    placeholder(Text("No apps found").foregroundStyle(.textSecondary))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $isConfirmingUninstall) {
            if let row = model.selectedRow {
                ConfirmSheet(
                    symbol: "trash",
                    title: model.removesApp
                        ? String(localized: "Uninstall \(row.app.name)?")
                        : String(localized: "Remove \(row.app.name) data?"),
                    message: String(localized: "Everything moves to the Restore Center first, so you can put it back for \(app.retentionDays) days."),
                    details: confirmDetails(for: row),
                    confirmTitle: model.removesApp ? String(localized: "Uninstall") : String(localized: "Remove"),
                    onConfirm: {
                        isConfirmingUninstall = false
                        model.uninstallSelected()
                    },
                    onCancel: { isConfirmingUninstall = false })
            }
        }
    }

    private func confirmDetails(for row: ApplicationsModel.Row) -> [ConfirmSheet.Detail] {
        var details: [ConfirmSheet.Detail] = []
        if model.removesApp {
            details.append(.init(symbol: "app", text: String(localized: "\(row.app.name).app · \((row.size ?? 0).bytesText)")))
        }
        let chosen = model.selectedLeftovers
        if !chosen.isEmpty {
            details.append(.init(symbol: "folder", text: String(localized: "\(chosen.count) leftover items · \(chosen.reduce(0) { $0 + $1.size }.bytesText)")))
        }
        let kept = model.leftovers.count - chosen.count
        if kept > 0 {
            details.append(.init(symbol: "lock", text: String(localized: "\(kept) personal items kept")))
        }
        return details
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.textTertiary)
                TextField("Search apps", text: $model.search)
                    .textFieldStyle(.plain)
                Menu {
                    Picker("Sort by", selection: $model.sort) {
                        ForEach(ApplicationsModel.Sort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.sortedRows) { row in
                        AppRow(row: row, isSelected: model.selectedID == row.id) { model.selectedID = row.id }
                    }
                }
                .padding(6)
            }
        }
        .glassSurface(cornerRadius: 20)
    }

    private func placeholder(_ content: some View) -> some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity).glassSurface(cornerRadius: 20)
    }

    // MARK: Leftovers of removed apps

    private var leftovers: some View {
        VStack(spacing: 12) {
            if model.orphans.isEmpty {
                VStack(spacing: 8) {
                    GlassGlyph(symbol: "checkmark.seal", tint: module.palette.accent, size: 56)
                    Text(model.isLoading ? "Looking for leftovers…" : "No leftovers from removed apps")
                        .font(.title3.weight(.semibold))
                    Text("Spaceroom looks for data of apps that are no longer installed and haven't been touched for 30 days.")
                        .font(.callout).foregroundStyle(.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassSurface(cornerRadius: 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.orphans) { group in OrphanRow(model: model, group: group) }
                    }
                    .padding(8)
                }
                .glassSurface(cornerRadius: 20)
                HStack {
                    Text("Apps that are gone, untouched for 30+ days. Personal data stays unticked.")
                        .font(.caption).foregroundStyle(.textTertiary)
                    Spacer()
                    Button("Remove Selected · \(model.selectedOrphanSize.bytesText)") { isConfirmingOrphans = true }
                        .buttonStyle(FilledButtonStyle(tint: .hex(0xFF5A6E)))
                        .disabled(model.selectedOrphanItems.isEmpty || model.isWorking || app.cleaningBlockedReason != nil)
                }
            }
        }
        .sheet(isPresented: $isConfirmingOrphans) {
            ConfirmSheet(
                symbol: "trash",
                title: String(localized: "Remove \(model.selectedOrphanSize.bytesText) of leftovers?"),
                message: String(localized: "These belong to apps that are no longer installed. They move to the Restore Center first, so you can put them back."),
                details: [.init(symbol: "folder", text: String(localized: "\(model.selectedOrphanItems.count) items from \(Set(model.selectedOrphanItems.map { $0.url.lastPathComponent }).count) locations"))],
                confirmTitle: String(localized: "Remove"),
                onConfirm: {
                    isConfirmingOrphans = false
                    model.removeSelectedOrphans()
                },
                onCancel: { isConfirmingOrphans = false })
        }
    }
}

// MARK: - Rows

private struct AppRow: View {
    let row: ApplicationsModel.Row
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                AppIcon(url: row.app.url, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(row.size.map(\.bytesText) ?? "…")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(row.size == nil ? .textTertiary : .white)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.15 : (isHovering ? 0.07 : 0))))
            .contentShape(Rectangle())
            .animation(Motion.hover, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        var parts: [String] = []
        if row.app.source == .appStore { parts.append(String(localized: "App Store")) }
        if let used = row.app.lastUsed {
            parts.append(String(localized: "opened \(used.formatted(.relative(presentation: .named)))"))
        } else {
            parts.append(String(localized: "never opened"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct AppDetail: View {
    @Bindable var model: ApplicationsModel
    let row: ApplicationsModel.Row
    let uninstall: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let running = model.isRunning(row.app)
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [SidebarModule.applications.palette.accent.opacity(0.45), .clear],
                                             center: .center, startRadius: 0, endRadius: 80))
                        .frame(width: 160, height: 160)
                    AppIcon(url: row.app.url, size: 84)
                }
                .frame(height: 120)
                Text(row.app.name).font(.system(size: 20, weight: .bold))
                Text([row.app.version.map { String(localized: "Version \($0)") }, row.app.bundleID]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.textTertiary)
                    .textSelection(.enabled)
            }
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 2) {
                    CheckRow(isOn: model.removesApp, symbol: "app", appIconURL: row.app.url,
                             title: String(localized: "Application"),
                             detail: row.app.url.path.abbreviatingHome, size: row.size, isPersonal: false) {
                        model.removesApp.toggle()
                    }
                    if model.isLoadingLeftovers {
                        ProgressView().controlSize(.small).padding(12)
                    }
                    if model.hasPersonalLeftovers {
                        Toggle(isOn: Binding(get: { model.includesPersonalData }, set: { model.setIncludesPersonalData($0) })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Remove everything, including personal data").font(.system(size: 12, weight: .medium))
                                Text("Settings, sign-ins and files the app keeps. Still restorable from the Restore Center.")
                                    .font(.caption).foregroundStyle(.textTertiary)
                            }
                        }
                        .toggleStyle(.switch).controlSize(.small)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    ForEach(model.leftovers) { item in
                        CheckRow(isOn: model.selectedLeftoverIDs.contains(item.id), symbol: item.category.symbol,
                                 title: item.category.title, detail: item.url.path.abbreviatingHome,
                                 size: item.size, isPersonal: item.isPersonal) {
                            model.toggle(item)
                        }
                        .contextMenu {
                            Button("Show in Finder") { Finder.reveal(item.url) }
                            Button("Always Ignore", systemImage: "eye.slash") { model.ignore(item) }
                        }
                    }
                }
                .padding(6)
            }

            if !model.otherCopies.isEmpty {
                OtherCopiesNote(copies: model.otherCopies).padding(.horizontal, 12).padding(.bottom, 8)
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 10) {
                if running {
                    Label("\(row.app.name) is open", systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.yellow)
                    Spacer()
                    Button("Quit \(row.app.name)") { model.quit(row.app) }.buttonStyle(GhostButtonStyle())
                } else {
                    Button { Finder.reveal(row.app.url) } label: { Label("Show in Finder", systemImage: "magnifyingglass") }
                        .buttonStyle(GhostButtonStyle())
                    Spacer()
                    Button(model.removesApp ? "Uninstall · \(model.uninstallSize.bytesText)"
                                            : "Remove Data · \(model.uninstallSize.bytesText)", action: uninstall)
                        .buttonStyle(FilledButtonStyle(tint: .hex(0xFF5A6E)))
                        .disabled(model.uninstallSize == 0 && model.selectedLeftovers.isEmpty && !model.removesApp
                                  || model.isWorking || app.cleaningBlockedReason != nil)
                }
            }
            .padding(12)
        }
        .glassSurface(cornerRadius: 20)
    }
}

/// Other copies of the same app stay launchable after this one is uninstalled.
private struct OtherCopiesNote: View {
    let copies: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(copies.count == 1 ? String(localized: "Another copy of this app is on your Mac")
                                    : String(localized: "\(copies.count) other copies of this app are on your Mac"),
                  systemImage: "square.on.square")
                .font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            ForEach(copies.prefix(4), id: \.self) { url in
                HStack(spacing: 6) {
                    Text(url.path.abbreviatingHome).font(.caption).foregroundStyle(.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    if url.path.hasPrefix("/Volumes/") {
                        Text("disk image or drive: eject it").font(.caption2).foregroundStyle(.textTertiary)
                    }
                    Spacer(minLength: 4)
                    Button("Show") { Finder.reveal(url) }.buttonStyle(.plain).font(.caption).foregroundStyle(.textSecondary)
                }
            }
            Text("Uninstalling this one leaves those, so the app can still be opened.")
                .font(.caption2).foregroundStyle(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.yellow.opacity(0.08)))
    }
}

/// Spaceroom itself: it can't move its own data while running, so it points to Settings.
private struct SelfAppDetail: View {
    let row: ApplicationsModel.Row
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            AppIcon(url: row.app.url, size: 84)
            Text(row.app.name).font(.system(size: 20, weight: .bold))
            Text("This is the Spaceroom you're using. To remove it with its settings and the Restore Center, use Uninstall Spaceroom in Settings.")
                .font(.callout).foregroundStyle(.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Button("Open Settings") { openSettings() }.buttonStyle(GhostButtonStyle())
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 20)
    }
}

private struct CheckRow: View {
    let isOn: Bool
    let symbol: String
    var appIconURL: URL?
    let title: String
    let detail: String
    let size: Int64?
    let isPersonal: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                IconSwap(isOn: isOn, on: "checkmark.square.fill", off: "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isOn ? .white : .textTertiary)
                if let appIconURL {
                    AppIcon(url: appIconURL, size: 20)
                } else {
                    Image(systemName: symbol).frame(width: 20).foregroundStyle(.textSecondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 13, weight: .medium))
                        if isPersonal { Pill(text: Text("Personal"), tint: .yellow) }
                    }
                    Text(detail).font(.caption).foregroundStyle(.textTertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Text(size.map(\.bytesText) ?? "…").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct OrphanRow: View {
    @Bindable var model: ApplicationsModel
    let group: OrphanGroup
    @State private var isExpanded = false

    var body: some View {
        let ids = Set(group.items.map(\.id))
        let selected = ids.intersection(model.selectedOrphanItemIDs)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.toggleOrphanGroup(group) } label: {
                    IconSwap(isOn: !selected.isEmpty,
                             on: selected.count == ids.count ? "checkmark.square.fill" : "minus.square.fill", off: "square")
                        .font(.system(size: 15))
                        .foregroundStyle(selected.isEmpty ? .textTertiary : .white)
                }
                .buttonStyle(.plain)
                GlassGlyph(symbol: "shippingbox", tint: .hex(0x8A93EA), size: 30, isCompact: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.bundleID).font(.system(size: 13, weight: .medium)).lineLimit(1).textSelection(.enabled)
                    Text(group.items.count == 1
                         ? "1 item · last used \(group.lastModified.formatted(.relative(presentation: .named)))"
                         : "\(group.items.count) items · last used \(group.lastModified.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.textTertiary)
                }
                Spacer()
                Text(group.size.bytesText).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Button { withAnimation(Easing.out(0.2)) { isExpanded.toggle() } } label: {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isExpanded ? "Hide items" : "Show items"))
            }
            .padding(10)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Always Ignore This App's Data", systemImage: "eye.slash") { model.ignoreApp(group.bundleID) }
            }
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        CheckRow(isOn: model.selectedOrphanItemIDs.contains(item.id), symbol: item.category.symbol,
                                 title: item.category.title, detail: item.url.path.abbreviatingHome,
                                 size: item.size, isPersonal: item.isPersonal) {
                            if model.selectedOrphanItemIDs.contains(item.id) { model.selectedOrphanItemIDs.remove(item.id) }
                            else { model.selectedOrphanItemIDs.insert(item.id) }
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
        }
        .glassSurface(cornerRadius: 16)
    }
}

/// The app's own Finder icon.
struct AppIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension LeftoverCategory {
    var title: String {
        switch self {
        case .caches: String(localized: "Caches")
        case .logs: String(localized: "Logs")
        case .savedState: String(localized: "Saved window state")
        case .webData: String(localized: "Web data")
        case .launchAgents: String(localized: "Launch agent")
        case .preferences: String(localized: "Settings")
        case .cookies: String(localized: "Cookies")
        case .applicationSupport: String(localized: "App data")
        case .containers: String(localized: "App container")
        case .groupContainers: String(localized: "Shared container")
        }
    }

    var symbol: String {
        switch self {
        case .caches: "shippingbox"
        case .logs: "doc.text"
        case .savedState: "macwindow"
        case .webData: "globe"
        case .launchAgents: "power"
        case .preferences: "gearshape"
        case .cookies: "birthday.cake"
        case .applicationSupport: "folder"
        case .containers: "cube"
        case .groupContainers: "cube.transparent"
        }
    }
}
