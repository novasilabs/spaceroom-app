// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import SwiftUI

/// Startup & Background: what launches at login or runs in the background, and whether it's healthy.
@MainActor
@Observable
final class StartupModel {
    struct Entry: Identifiable, Hashable {
        var id: String { item.id }
        let item: LaunchItem
        let findings: [LaunchFinding]
        let signature: CodeSignature.Status?
        let isLoaded: Bool

        var needsAttention: Bool { !findings.isEmpty }
        var hasWarning: Bool { findings.contains(where: \.isWarning) }

        /// "Zoom", "Google Updater" — the app it belongs to when known, else its label.
        var displayName: String {
            if let app = item.containingApp {
                return (app as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            }
            return item.label
        }
    }

    private unowned let app: AppModel

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var entries: [Entry] = []
    private(set) var posture: SecurityPosture?
    private(set) var isWorking = false
    private(set) var lastResult: (message: String, operationID: UUID?)?

    init(app: AppModel) {
        self.app = app
    }

    var attention: [Entry] { entries.filter(\.needsAttention).sorted { $0.hasWarning && !$1.hasWarning } }
    func entries(in scopes: Set<LaunchItem.Scope>) -> [Entry] {
        entries.filter { scopes.contains($0.item.scope) && !$0.needsAttention }
    }

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        reload()
    }

    func reload() {
        isLoading = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            async let found = Task.detached(priority: .userInitiated) { Self.collect(home: home) }.value
            async let security = Task.detached(priority: .utility) { SecurityPosture.current() }.value
            let (items, postureResult) = await (found, security)
            entries = items
            posture = postureResult
            isLoading = false
            hasLoaded = true
        }
    }

    nonisolated private static func collect(home: URL) -> [Entry] {
        let apps = AppInventory.discover(in: AppInventory.appFolders(home: home))
        let items = LaunchItemScanner.scan(LaunchItemScanner.folders(home: home)) + LaunchItemScanner.insideApps(apps)
        let loaded = Launchctl.loadedLabels()
        return items.map { item in
            let signature = item.program.flatMap { program in
                program.hasPrefix("/") && FileManager.default.fileExists(atPath: program) ? CodeSignature.status(of: program) : nil
            }
            let findings = LaunchAuditor.findings(
                for: item, home: home,
                isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
                signature: signature)
            return Entry(item: item, findings: findings, signature: signature, isLoaded: loaded.contains(item.label))
        }
    }

    // MARK: Actions

    func remove(_ entry: Entry) {
        guard let store = app.store else { return }
        isWorking = true
        Task {
            do {
                let outcome = try await LaunchItemRemover(store: store).remove([entry.item])
                await app.refreshOperations()
                if let operation = outcome.operation {
                    lastResult = (String(localized: "Removed \(entry.displayName). It's in the Restore Center if you need it back."), operation.id)
                } else if let first = outcome.skipped.first {
                    lastResult = (String(localized: "Nothing was removed: \(first.reason.text)"), nil)
                }
            } catch {
                app.show(String(localized: "Couldn't remove the item"), error)
            }
            isWorking = false
            reload()
        }
    }

    func undoLast() {
        guard let id = lastResult?.operationID else { return }
        Task {
            if await app.restoreAll(id) {
                lastResult = (String(localized: "Restored. It starts again at your next login."), nil)
            }
            reload()
        }
    }

    func dismissResult() { lastResult = nil }

    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) }
    }
}
