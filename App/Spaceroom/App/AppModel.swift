// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import SwiftUI

/// App-wide state: selection, the rule catalog, the Restore Center and permissions.
@MainActor
@Observable
final class AppModel {
    var selection: SidebarModule = .smartCare
    var isShowingOnboarding = false
    var alert: AlertMessage?

    /// `nil` when the rule files failed to load or validate — cleaning is then disabled (fail-closed).
    let catalog: RuleCatalog?
    let catalogError: String?

    /// `nil` when the Restore Center index can't be read — cleaning is then disabled too.
    let store: RestoreStore?
    let storeError: String?

    /// Things the user never wants cleaned. Enforced by every scan and by the Restore Center.
    private(set) var ignoreList = IgnoreList()
    /// Set when `ignore.json` exists but can't be read: nothing may be moved (fail-closed).
    let ignoreError: String?

    private(set) var operations: [OperationRecord] = []
    private(set) var fullDiskAccess: FullDiskAccess.Status = .unknown

    var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: Keys.retentionDays) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    private(set) var flows: [FlowKind: ScanFlowModel] = [:]
    @ObservationIgnored private(set) lazy var spaceLens = SpaceLensModel(app: self)
    @ObservationIgnored private(set) lazy var applications = ApplicationsModel(app: self)
    @ObservationIgnored private(set) lazy var clutter = ClutterModel(app: self)
    @ObservationIgnored private(set) lazy var status = StatusModel()
    @ObservationIgnored private(set) lazy var startup = StartupModel(app: self)
    @ObservationIgnored private(set) lazy var performance = PerformanceModel()
    @ObservationIgnored private(set) lazy var privacy = PrivacyModel(app: self)
    @ObservationIgnored private(set) lazy var automations = AutomationsModel(app: self)
    @ObservationIgnored private(set) lazy var palette = CommandPaletteModel(app: self)
    @ObservationIgnored private(set) lazy var protection = ProtectionModel(app: self)

    static let retentionChoices = [1, 3, 7, 14, 30]

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum Keys {
        static let retentionDays = "retentionDays"
        static let onboarding = "hasCompletedOnboarding"
    }

    init() {
        let defaults = UserDefaults.standard
        let storedRetention = defaults.integer(forKey: Keys.retentionDays)
        retentionDays = Self.retentionChoices.contains(storedRetention) ? storedRetention : 7
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)

        do {
            catalog = try RuleCatalog.bundled()
            catalogError = nil
        } catch {
            catalog = nil
            catalogError = error.description
        }
        let gate: RestoreStore.IgnoreGate
        do {
            let list = try IgnoreListFile.load()
            ignoreList = list
            ignoreError = nil
            gate = .list(list)
        } catch {
            ignoreError = String(describing: error)
            gate = .unavailable(String(describing: error))
        }
        do {
            store = try RestoreStore(ignore: gate)
            storeError = nil
        } catch {
            store = nil
            storeError = String(describing: error)
        }

        flows[.smartCare] = ScanFlowModel(kind: .smartCare, app: self)
        for module in CleanModule.allCases {
            flows[.module(module)] = ScanFlowModel(kind: .module(module), app: self)
        }
        refreshFullDiskAccess()
        isShowingOnboarding = !hasCompletedOnboarding
        // Debug tooling (snapshot tour, icon export) must never run automations on the real Mac.
        let environment = ProcessInfo.processInfo.environment
        let isTooling = environment["SPACEROOM_SNAPSHOT_DIR"] != nil || environment["SPACEROOM_EXPORT_ICON"] != nil
        automations.start(schedules: !isTooling)
    }

    /// Why cleaning is disabled, if it is.
    var cleaningBlockedReason: String? {
        if let catalogError { return String(localized: "Cleaning rules failed to load: \(catalogError)") }
        if let storeError { return String(localized: "Restore Center is unavailable: \(storeError)") }
        if let ignoreError { return String(localized: "The ignore list can't be read, so cleaning is off until it's fixed: \(ignoreError)") }
        return nil
    }

    func flow(for kind: FlowKind) -> ScanFlowModel? { flows[kind] }

    /// Shows Smart Care and starts a scan unless one is already under way or showing results.
    func runSmartCare() {
        selection = .smartCare
        if let flow = flows[.smartCare], flow.phase == .intro || flow.phase == .done {
            if flow.phase == .done { flow.finish() }
            flow.startScan()
        }
    }

    func scanContext() -> ScanContext {
        ScanContext(home: FileManager.default.homeDirectoryForCurrentUser,
                    runningBundleIDs: AppNames.runningBundleIDs(),
                    runningAppNames: AppNames.runningAppNames(),
                    now: .now,
                    ignore: ignoreList)
    }

    // MARK: Lifecycle

    func onLaunch() async {
        if let store {
            do {
                try await store.purgeExpired(retentionDays: retentionDays)
            } catch {
                show("Couldn't clear expired items", error)
            }
            reportTrashFallback(await store.removeOrphanedFolders())
        }
        await refreshOperations()
    }

    func refreshFullDiskAccess() {
        fullDiskAccess = FullDiskAccess.status()
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    // MARK: Restore Center

    var storedSize: Int64 { operations.reduce(0) { $0 + $1.storedSize } }

    func refreshOperations() async {
        guard let store else { return }
        operations = await store.operations
    }

    @discardableResult
    func restoreAll(_ operationID: UUID) async -> Bool {
        await perform("Couldn't restore") { try await $0.restoreAll(in: operationID) }
    }

    @discardableResult
    func restore(_ itemID: UUID, in operationID: UUID) async -> Bool {
        await perform("Couldn't restore") { try await $0.restore([itemID], in: operationID) }
    }

    @discardableResult
    func purge(_ operationID: UUID) async -> Bool {
        await perform("Couldn't delete") { try await $0.purge(operationID) }
    }

    /// Permanently deletes several operations; one combined report instead of an alert each.
    @discardableResult
    func purge(_ operationIDs: [UUID]) async -> Bool {
        guard let store else { return false }
        var total = PurgeResult()
        var failed = 0
        for id in operationIDs {
            do {
                let result = try await store.purge(id)
                total.freed += result.freed
                total.movedToTrash += result.movedToTrash
                total.movedToTrashSize += result.movedToTrashSize
            } catch {
                failed += 1
            }
        }
        reportTrashFallback(total)
        if failed > 0 {
            alert = AlertMessage(title: String(localized: "Some items couldn't be deleted"),
                                 message: String(localized: "\(failed) of \(operationIDs.count) operations still have items in the Restore Center."))
        }
        await refreshOperations()
        return failed == 0
    }

    /// Restores several operations; one combined report for anything that couldn't come back.
    @discardableResult
    func restoreAll(_ operationIDs: [UUID]) async -> Bool {
        guard let store else { return false }
        var problems = 0
        for id in operationIDs {
            do {
                let outcomes = try await store.restoreAll(in: id)
                problems += outcomes.filter {
                    if case .restored = $0 { false } else if case .restoredRenamed = $0 { false } else { true }
                }.count
            } catch {
                problems += 1
            }
        }
        if problems > 0 {
            alert = AlertMessage(title: String(localized: "Some items couldn't be restored"),
                                 message: String(localized: "\(problems) items are no longer in the Restore Center or couldn't be moved back."))
        }
        await refreshOperations()
        return problems == 0
    }

    /// Runs a store action, reports failures (including per-item restore failures), refreshes.
    @discardableResult
    private func perform<T: Sendable>(_ failureTitle: String, _ action: (RestoreStore) async throws -> T) async -> Bool {
        guard let store else { return false }
        var succeeded = true
        do {
            let result = try await action(store)
            if let purge = result as? PurgeResult { reportTrashFallback(purge) }
            if let outcomes = result as? [RestoreOutcome] {
                let problems = outcomes.compactMap { outcome -> String? in
                    switch outcome {
                    case .missing: String(localized: "An item was no longer in the Restore Center.")
                    case .failed(_, let message): message
                    case .restored, .restoredRenamed: nil
                    }
                }
                if !problems.isEmpty {
                    succeeded = false
                    alert = AlertMessage(title: failureTitle, message: problems.joined(separator: "\n"))
                }
            }
        } catch {
            succeeded = false
            show(failureTitle, error)
        }
        await refreshOperations()
        return succeeded
    }

    /// macOS protects some items (app bundles from other developers) from being deleted in place;
    /// those went to the Trash instead. Say so, because the space only frees when the Trash is emptied.
    private func reportTrashFallback(_ result: PurgeResult) {
        guard !result.movedToTrash.isEmpty else { return }
        alert = AlertMessage(
            title: String(localized: "Moved \(result.movedToTrashSize.bytesText) to the Trash"),
            message: String(localized: "macOS doesn't let apps delete some protected items in place, such as apps inside caches. Spaceroom moved them to the Trash instead. Empty the Trash in Finder to free the space."))
    }

    // MARK: Ignore list

    func ignore(_ entry: IgnoreEntry) {
        var list = ignoreList
        list.add(entry)
        setIgnoreList(list)
    }

    func unignore(_ id: String) {
        var list = ignoreList
        list.remove(id: id)
        setIgnoreList(list)
    }

    #if DEBUG
    /// Snapshot tour only: show a sample list without saving it or changing what may be cleaned.
    func showIgnoreListForSnapshot(_ list: IgnoreList) { ignoreList = list }
    #endif

    private func setIgnoreList(_ list: IgnoreList) {
        // An unreadable list is never overwritten: the user may want to repair it.
        guard ignoreError == nil, list != ignoreList else { return }
        do {
            try IgnoreListFile.save(list)
        } catch {
            show(String(localized: "Couldn't save the ignore list"), error)
            return
        }
        ignoreList = list
        if let store { Task { await store.setIgnore(.list(list)) } }
        for flow in flows.values { flow.applyIgnore(list) }
    }

    func show(_ title: String, _ error: any Error) {
        alert = AlertMessage(title: title, message: error.localizedDescription)
    }
}
