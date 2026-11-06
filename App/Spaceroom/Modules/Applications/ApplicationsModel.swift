// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import SwiftUI

/// Applications: installed apps with their leftovers, and leftovers of apps that are gone.
@MainActor
@Observable
final class ApplicationsModel {
    enum Tab: Hashable { case installed, leftovers, updates }
    enum Sort: String, CaseIterable, Identifiable {
        case size, name, lastUsed
        var id: String { rawValue }
        var title: LocalizedStringResource {
            switch self {
            case .size: "Size"
            case .name: "Name"
            case .lastUsed: "Last Opened"
            }
        }
    }

    struct Row: Identifiable {
        var id: String { app.id }
        let app: InstalledApp
        var size: Int64?
    }

    private unowned let app: AppModel

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var rows: [Row] = []
    var tab: Tab = .installed
    var sort: Sort = .size
    var search = ""
    var selectedID: String? { didSet { if selectedID != oldValue { loadLeftoversForSelection() } } }

    /// Leftovers of the selected app, and which of them are ticked.
    private(set) var leftovers: [Leftover] = []
    private(set) var isLoadingLeftovers = false
    var selectedLeftoverIDs: Set<String> = []
    var removesApp = true

    private var foundOrphans: [OrphanGroup] = []
    /// Leftover groups, minus apps and items on the ignore list.
    var orphans: [OrphanGroup] {
        foundOrphans.filter { group in
            !app.ignoreList.ignoresApp(group.bundleID) && group.items.contains { !app.ignoreList.ignoresItem(at: $0.url) }
        }
    }
    var selectedOrphanItemIDs: Set<String> = []

    private(set) var isWorking = false
    /// Banner after an uninstall: message plus the operation to undo.
    private(set) var lastResult: (message: String, operationID: UUID?)?

    /// Update check results. Only filled when the user asks; nothing is checked in the background.
    private(set) var updateResult: UpdateCheckResult?
    private(set) var isCheckingUpdates = false
    private(set) var lastUpdateCheck: Date?
    #if DEBUG
    /// Snapshot tour: show sample updates without contacting anything.
    func showUpdatesForSnapshot(_ result: UpdateCheckResult) {
        updateResult = result
        lastUpdateCheck = .now
    }
    #endif

    func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        let apps = rows.map(\.app)
        Task {
            let result = await AppUpdateChecker().check(apps)
            updateResult = result
            lastUpdateCheck = .now
            isCheckingUpdates = false
        }
    }

    func openForUpdate(_ update: AppUpdate) {
        switch update.channel {
        case .sparkle:
            NSWorkspace.shared.openApplication(at: update.app.url, configuration: NSWorkspace.OpenConfiguration())
        case .appStore(let page):
            NSWorkspace.shared.open(page)
        }
    }

    private var loadTask: Task<Void, Never>?
    private var leftoverTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Loading

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        reload()
    }

    func reload() {
        loadTask?.cancel()
        isLoading = true
        hasLoadedOrphans = false
        let home = FileManager.default.homeDirectoryForCurrentUser
        loadTask = Task { [weak self] in
            let infos = await Self.inventory(home: home)
            guard let self, !Task.isCancelled else { return }
            self.rows = infos.map { Row(app: $0, size: nil) }
            if self.selectedID == nil || !self.rows.contains(where: { $0.id == self.selectedID }) {
                self.selectedID = self.sortedRows.first?.id
            }
            self.hasLoaded = true
            self.isLoading = false
            // The selection may be the same app, so its leftovers are reloaded explicitly
            // (after Remove Data, the removed items must disappear).
            self.loadLeftoversForSelection()
            self.isLoadingOrphans = true
            await self.measureSizes()
            guard !Task.isCancelled else { return }
            await self.loadOrphans(home: home, installed: Set(infos.map(\.bundleID)))
        }
    }

    /// Leftovers of removed apps are still being looked for.
    private(set) var isLoadingOrphans = false
    /// Whether the leftover list reflects the current state (Smart Care waits for this).
    private(set) var hasLoadedOrphans = false

    /// `nonisolated async` runs off the main actor in Swift 6.0 (there is no `@concurrent` yet).
    nonisolated private static func inventory(home: URL) async -> [InstalledApp] {
        AppInventory.discover(in: AppInventory.appFolders(home: home)).compactMap(AppInventory.info(for:))
            .filter { !$0.isProtected }
    }

    private func measureSizes() async {
        let urls = rows.map(\.app.url)
        await withTaskGroup(of: (String, Int64).self) { group in
            var pending = urls[...]
            for _ in 0..<4 {
                guard let url = pending.popFirst() else { break }
                group.addTask { (url.path, DiskUsage.size(of: url)) }
            }
            for await (path, size) in group {
                if let index = rows.firstIndex(where: { $0.id == path }) { rows[index].size = size }
                if let url = pending.popFirst() { group.addTask { (url.path, DiskUsage.size(of: url)) } }
            }
        }
    }

    private func loadOrphans(home: URL, installed: Set<String>) async {
        let found = await Task.detached(priority: .utility) {
            OrphanFinder(home: home).find(installedBundleIDs: installed) { id in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
            }
        }.value
        // A newer reload (say, after Undo) owns the results now.
        guard !Task.isCancelled else { return }
        foundOrphans = found
        selectedOrphanItemIDs = Set(found.flatMap(\.items).filter { !$0.isPersonal }.map(\.id))
        isLoadingOrphans = false
        hasLoadedOrphans = true
    }

    /// Spaceroom's own live data (the Restore Center, its settings). Uninstalling an old copy of
    /// Spaceroom must not take the running one's data with it; Settings › Uninstall Spaceroom does that.
    static func isSpaceroomData(_ url: URL) -> Bool {
        let own = RestoreStore.defaultDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == own || path.hasPrefix(own + "/") { return true }
        guard let current = Bundle.main.bundleIdentifier else { return false }
        return url.lastPathComponent.hasPrefix(current)
    }

    /// This very app (uninstalling it from itself needs its own flow).
    func isSelf(_ installed: InstalledApp) -> Bool {
        installed.url.resolvingSymlinksInPath().standardizedFileURL == Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Other copies of the selected app that macOS knows about (another folder, a disk image, a
    /// build folder). They stay launchable after this copy is uninstalled.
    private(set) var otherCopies: [URL] = []

    static func otherCopies(of installed: InstalledApp) -> [URL] {
        let this = installed.url.resolvingSymlinksInPath().standardizedFileURL
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: installed.bundleID)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { $0 != this && !$0.path.contains("/Spaceroom/Quarantine/") && !$0.path.contains("/.Trash/")
                && FileManager.default.fileExists(atPath: $0.path) }
            .reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Personal leftovers (settings, app data) are left unticked; this ticks or unticks all of them.
    var includesPersonalData: Bool {
        let personal = leftovers.filter(\.isPersonal)
        return !personal.isEmpty && personal.allSatisfy { selectedLeftoverIDs.contains($0.id) }
    }
    var hasPersonalLeftovers: Bool { leftovers.contains(where: \.isPersonal) }

    func setIncludesPersonalData(_ on: Bool) {
        let ids = Set(leftovers.filter(\.isPersonal).map(\.id))
        if on { selectedLeftoverIDs.formUnion(ids) } else { selectedLeftoverIDs.subtract(ids) }
    }

    private func loadLeftoversForSelection() {
        leftoverTask?.cancel()
        leftovers = []
        otherCopies = selectedRow.map { Self.otherCopies(of: $0.app) } ?? []
        selectedLeftoverIDs = []
        removesApp = true
        guard let row = selectedRow else { return }
        isLoadingLeftovers = true
        let bundleID = row.app.bundleID, name = row.app.name
        let installed = Set(rows.map(\.app.bundleID))
        let home = FileManager.default.homeDirectoryForCurrentUser
        leftoverTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                LeftoverFinder(home: home).leftovers(bundleID: bundleID, appName: name, installedBundleIDs: installed)
            }.value
            guard let self, !Task.isCancelled, self.selectedRow?.app.bundleID == bundleID else { return }
            self.leftovers = found.filter { !self.app.ignoreList.ignoresItem(at: $0.url) && !Self.isSpaceroomData($0.url) }
            // Mole's rule: keep personal data (settings, documents an app keeps) unless asked.
            self.selectedLeftoverIDs = Set(found.filter { !$0.isPersonal }.map(\.id))
            self.isLoadingLeftovers = false
        }
    }

    // MARK: Derived

    // MARK: Ignore

    func ignore(_ leftover: Leftover) {
        app.ignore(.path(leftover.url))
        leftovers.removeAll { $0.id == leftover.id }
        selectedLeftoverIDs.remove(leftover.id)
        selectedOrphanItemIDs.remove(leftover.id)
    }

    func ignoreApp(_ bundleID: String) {
        app.ignore(.app(bundleID))
        let ids = Set(foundOrphans.first { $0.bundleID == bundleID }?.items.map(\.id) ?? [])
        selectedOrphanItemIDs.subtract(ids)
    }

    var sortedRows: [Row] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? rows : rows.filter {
            $0.app.name.lowercased().contains(query) || $0.app.bundleID.lowercased().contains(query)
        }
        switch sort {
        case .size: return filtered.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        case .name: return filtered.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        case .lastUsed: return filtered.sorted { ($0.app.lastUsed ?? .distantPast) < ($1.app.lastUsed ?? .distantPast) }
        }
    }

    var selectedRow: Row? { rows.first { $0.id == selectedID } }

    var totalAppsSize: Int64 { rows.reduce(0) { $0 + ($1.size ?? 0) } }

    var selectedLeftovers: [Leftover] { leftovers.filter { selectedLeftoverIDs.contains($0.id) } }

    var uninstallSize: Int64 {
        (removesApp ? (selectedRow?.size ?? 0) : 0) + selectedLeftovers.reduce(0) { $0 + $1.size }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
            || RunningProcesses.current().program(inside: app.url) != nil
    }

    var selectedOrphanItems: [Leftover] {
        orphans.flatMap(\.items).filter { selectedOrphanItemIDs.contains($0.id) && !app.ignoreList.ignoresItem(at: $0.url) }
    }
    var selectedOrphanSize: Int64 { selectedOrphanItems.reduce(0) { $0 + $1.size } }
    var orphansSize: Int64 { orphans.reduce(0) { $0 + $1.size } }

    // MARK: Actions

    func toggle(_ leftover: Leftover) {
        if selectedLeftoverIDs.contains(leftover.id) { selectedLeftoverIDs.remove(leftover.id) } else { selectedLeftoverIDs.insert(leftover.id) }
    }

    func toggleOrphanGroup(_ group: OrphanGroup) {
        let ids = Set(group.items.map(\.id))
        if ids.isSubset(of: selectedOrphanItemIDs) { selectedOrphanItemIDs.subtract(ids) } else { selectedOrphanItemIDs.formUnion(ids) }
    }

    func quit(_ app: InstalledApp) {
        for running in NSWorkspace.shared.runningApplications where running.bundleIdentifier == app.bundleID {
            running.terminate()
        }
    }

    func uninstallSelected() {
        guard let row = selectedRow, let store = self.app.store else { return }
        let target = row.app
        let items = selectedLeftovers
        let includeApp = removesApp
        let copies = otherCopies
        run(store: store) { uninstaller, running in
            try await uninstaller.remove(app: includeApp ? target : nil, leftovers: items, runningBundleIDs: running)
        } message: { freed in
            var text = includeApp ? String(localized: "Uninstalled \(target.name) · \(freed.bytesText) moved to the Restore Center")
                                  : String(localized: "Removed \(freed.bytesText) of \(target.name) data")
            if includeApp, let first = copies.first {
                text += " " + (copies.count == 1
                    ? String(localized: "Another copy is still at \(first.path.abbreviatingHome), so it can still be opened.")
                    : String(localized: "\(copies.count) other copies are still on this Mac, so it can still be opened."))
            }
            return text
        }
    }

    func removeSelectedOrphans() {
        guard let store = app.store else { return }
        // An app may have been installed again since the scan: its data isn't a leftover any more.
        let items = selectedOrphanItems.filter { item in
            !orphans.contains { group in
                group.items.contains(item) && NSWorkspace.shared.urlForApplication(withBundleIdentifier: group.bundleID) != nil
            }
        }
        run(store: store) { uninstaller, running in
            try await uninstaller.remove(app: nil, leftovers: items, runningBundleIDs: running)
        } message: { [weak self] freed in
            // Gone now: don't keep them listed (and tickable) until the rescan finishes.
            if let self {
                let moved = Set(items.map(\.id))
                self.foundOrphans = self.foundOrphans.compactMap { group in
                    let rest = group.items.filter { !moved.contains($0.id) }
                    return rest.isEmpty ? nil : OrphanGroup(bundleID: group.bundleID, items: rest)
                }
                self.selectedOrphanItemIDs.subtract(moved)
            }
            return String(localized: "Removed \(freed.bytesText) of leftovers")
        }
    }

    private func run(store: RestoreStore,
                     _ action: @escaping @MainActor (Uninstaller, Set<String>) async throws -> CleanOutcome,
                     message: @escaping @MainActor (Int64) -> String) {
        isWorking = true
        let running = AppNames.runningBundleIDs()
        Task {
            do {
                let outcome = try await action(Uninstaller(store: store), running)
                await app.refreshOperations()
                if let operation = outcome.operation {
                    lastResult = (message(operation.totalSize), operation.id)
                } else if let first = outcome.skipped.first {
                    lastResult = (String(localized: "Nothing was removed: \(first.reason.text)"), nil)
                }
                if !outcome.skipped.isEmpty, let operation = outcome.operation {
                    lastResult = (message(operation.totalSize) + " " + String(localized: "(\(outcome.skipped.count) skipped)"),
                                  operation.id)
                }
            } catch {
                app.show(String(localized: "Couldn't uninstall"), error)
            }
            isWorking = false
            reload()
        }
    }

    func undoLast() {
        guard let id = lastResult?.operationID else { return }
        Task {
            if await app.restoreAll(id) { lastResult = (String(localized: "Restored. Everything is back."), nil) }
            reload()
        }
    }

    func dismissResult() { lastResult = nil }
}
