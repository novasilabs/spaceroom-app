// SPDX-License-Identifier: GPL-3.0-or-later

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
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                LabeledContent("License", value: "GPL-3.0-or-later")
                Text("Free and open source. Inspired by Mole (tw93/mole). Not affiliated with Apple or MacPaw.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
        .onAppear {
            app.refreshFullDiskAccess()
            menuBar.refreshLoginItemStatus()
        }
    }
}
