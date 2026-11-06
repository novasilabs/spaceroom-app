// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ServiceManagement
import SpaceroomCore
import SwiftUI

/// Removes Spaceroom itself: the app, its settings, caches and its data folder (which holds the
/// Restore Center). Everything goes to the Trash rather than the Restore Center, since that is
/// being removed too, so it can still be put back from the Trash until it's emptied.
@MainActor
enum SelfUninstall {
    static let bundleIDs = ["com.novasilabs.spaceroom", "io.github.spaceroom-app.spaceroom"]

    struct Plan: Identifiable {
        let id = UUID()
        var app: URL?
        var files: [URL]
        /// Items still in the Restore Center (they go to the Trash with it).
        var restoreCenterItems: Int
        var restoreCenterSize: Int64
        var size: Int64
    }

    /// The app is only included when it's installed (not run from a disk image or a build folder).
    static func plan(operations: [OperationRecord]) -> Plan {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        var files: [URL] = [RestoreStore.defaultDirectory]
        for id in bundleIDs {
            files += [
                library.appendingPathComponent("Preferences/\(id).plist"),
                library.appendingPathComponent("Caches/\(id)"),
                library.appendingPathComponent("HTTPStorages/\(id)"),
                library.appendingPathComponent("WebKit/\(id)"),
                library.appendingPathComponent("Saved Application State/\(id).savedState"),
            ]
        }
        files = files.filter { fm.fileExists(atPath: $0.path) }
        let bundle = Bundle.main.bundleURL
        let installed = AppInventory.appFolders(home: home).contains { bundle.deletingLastPathComponent().standardizedFileURL == $0.standardizedFileURL }
        let stored = operations.flatMap(\.storedItems)
        let app = installed ? bundle : nil
        let size = ([app].compactMap { $0 } + files).reduce(Int64(0)) { $0 + DiskUsage.size(of: $1) }
        return Plan(app: app, files: files, restoreCenterItems: stored.count,
                    restoreCenterSize: stored.reduce(0) { $0 + $1.size }, size: size)
    }

    /// Moves everything to the Trash, then quits. Returns the paths that couldn't be moved.
    @discardableResult
    static func run(_ plan: Plan) -> [String] {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        // Forget the settings first, or the preferences daemon writes the file again on quit.
        for id in bundleIDs { UserDefaults.standard.removePersistentDomain(forName: id) }
        UserDefaults.standard.synchronize()
        var failed: [String] = []
        for url in plan.files + [plan.app].compactMap({ $0 }) {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed.append(url.path) }
        }
        return failed
    }
}

struct SelfUninstallSection: View {
    @Environment(AppModel.self) private var app
    @State private var plan: SelfUninstall.Plan?
    @State private var failures: [String] = []

    var body: some View {
        Section {
            Button("Uninstall Spaceroom…", role: .destructive) { plan = SelfUninstall.plan(operations: app.operations) }
            if !failures.isEmpty {
                Text("Couldn't move: \(failures.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
            }
        } footer: {
            Text("Moves Spaceroom, its settings and its data, including the Restore Center, to the Trash, then quits.")
        }
        .sheet(item: $plan) { current in
            ConfirmSheet(
                symbol: "trash",
                title: String(localized: "Uninstall Spaceroom?"),
                message: current.restoreCenterItems > 0
                    ? String(localized: "\(current.restoreCenterItems) cleaned items (\(current.restoreCenterSize.bytesText)) are still in the Restore Center. They go to the Trash too. Put back anything you need first.")
                    : String(localized: "Spaceroom, its settings and its data go to the Trash. Empty the Trash to free the space."),
                details: [
                    .init(symbol: "app", text: current.app.map { $0.path.abbreviatingHome }
                          ?? String(localized: "The app isn't in Applications, so only its data is removed")),
                    .init(symbol: "folder", text: String(localized: "\(current.files.count) settings and data items · \(current.size.bytesText)")),
                ],
                confirmTitle: String(localized: "Uninstall and Quit"),
                onConfirm: {
                    plan = nil
                    failures = SelfUninstall.run(current)
                    if failures.isEmpty { NSApp.terminate(nil) }
                },
                onCancel: { plan = nil })
        }
    }
}
