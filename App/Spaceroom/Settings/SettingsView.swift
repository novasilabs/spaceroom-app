// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar

    var body: some View {
        @Bindable var app = app
        @Bindable var menuBar = menuBar
        Form {
            Section {
                Toggle("Show storage", isOn: $menuBar.isStorageItemShown)
                Picker("Display", selection: $menuBar.storageStyle) {
                    ForEach(MenuBarModel.StorageStyle.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!menuBar.isStorageItemShown)
                Toggle("Show CPU usage", isOn: $menuBar.isCPUItemShown)
                Toggle("Show memory usage", isOn: $menuBar.isMemoryItemShown)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Everything you turn on shares one Spaceroom item in the menu bar.")
            }
            Section {
                Toggle("Keep running in the menu bar when the window is closed", isOn: $menuBar.keepsRunningInMenuBar)
                Toggle("Open at login", isOn: Binding(get: { menuBar.opensAtLogin },
                                                       set: { menuBar.setOpensAtLogin($0) }))
                if menuBar.loginItemNeedsApproval {
                    Text("Approve Spaceroom in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Restore Center") {
                Picker("Keep cleaned items for", selection: $app.retentionDays) {
                    ForEach(AppModel.retentionChoices, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                Text("After this period, cleaned items are deleted permanently. You can also delete them sooner from the Restore Center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            IgnoreListSection()

            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    HStack {
                        switch app.fullDiskAccess {
                        case .granted: Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .denied: Label("Off", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                        case .unknown: Label("Unknown", systemImage: "questionmark.circle")
                        }
                        Button("Open System Settings") { app.openFullDiskAccessSettings() }
                    }
                }
            }

            Section("Cleaning rules") {
                if let catalog = app.catalog {
                    LabeledContent("Loaded rules", value: "\(catalog.rules.count)")
                } else {
                    Label(app.catalogError ?? "Unavailable", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                Button("Show Welcome Tour Again") {
                    app.hasCompletedOnboarding = false
                    app.isShowingOnboarding = true
                    AppDelegate.showMainWindow()
                }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                LabeledContent("License", value: "GPL-3.0-or-later")
                Text("Free and open source. Inspired by Mole (tw93/mole). Not affiliated with Apple or MacPaw.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 700)
        .onAppear {
            app.refreshFullDiskAccess()
            menuBar.refreshLoginItemStatus()
        }
    }
}

/// Everything Spaceroom must never clean, uninstall or move, with add and remove.
private struct IgnoreListSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            if let error = app.ignoreError {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The ignore list can't be read, so cleaning is off.")
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                }
                Button("Show the File in Finder") { Finder.reveal(IgnoreListFile.url(in: RestoreStore.defaultDirectory)) }
            } else {
                if app.ignoreList.isEmpty {
                    Text("Nothing ignored yet. Right-click an item anywhere in Spaceroom and choose Always Ignore, or add folders here.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(app.ignoreList.entries.sorted { $0.addedAt > $1.addedAt }) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: symbol(entry)).frame(width: 20).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title(entry)).lineLimit(1).truncationMode(.middle)
                            Text(detail(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { app.unignore(entry.id) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Stop ignoring")
                            .accessibilityLabel(Text("Stop ignoring \(title(entry))"))
                    }
                }
                Button("Add Files or Folders…", action: addPaths)
            }
        } header: {
            Text("Ignore List")
        } footer: {
            Text("Spaceroom never cleans, uninstalls or moves anything here, and scans show it as Ignored. A folder protects everything inside it.")
        }
    }

    private func symbol(_ entry: IgnoreEntry) -> String {
        switch entry.kind {
        case .path: FileManager.default.isDirectory(atPath: entry.value) ? "folder" : "doc"
        case .app: "app.dashed"
        case .rule: "square.stack.3d.up"
        }
    }

    private func title(_ entry: IgnoreEntry) -> String {
        switch entry.kind {
        case .path: (entry.value as NSString).lastPathComponent
        case .app: AppNames.name(for: entry.value)
        case .rule: app.catalog?.rule(entry.value)?.localizedTitle ?? entry.value
        }
    }

    private func detail(_ entry: IgnoreEntry) -> String {
        switch entry.kind {
        case .path:
            let parent = (entry.value as NSString).deletingLastPathComponent.abbreviatingHome
            return FileManager.default.fileExists(atPath: entry.value) ? parent : String(localized: "\(parent) · no longer exists")
        case .app: return String(localized: "This app's data · \(entry.value)")
        case .rule: return String(localized: "Cleaning category")
        }
    }

    private func addPaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Ignore")
        panel.message = String(localized: "Spaceroom will never clean, uninstall or move what you choose.")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { app.ignore(.path(url)) }
    }
}

private extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
