// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
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
        .frame(width: 480, height: 460)
        .onAppear { app.refreshFullDiskAccess() }
    }
}
