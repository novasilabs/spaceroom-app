// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import ServiceManagement
import SpaceroomCore
import SwiftUI

/// Live data and preferences for the menu bar items and popover.
///
/// Sampling budget (PRD §6.12.6): storage every 60 s plus on mount/unmount; CPU and memory
/// every 2 s only while a CPU/memory item is shown or the popover is open (1 s then).
@MainActor
@Observable
final class MenuBarModel {
    enum StorageStyle: String, CaseIterable, Identifiable {
        case ringAndFree, ringOnly, freeOnly, percentUsed
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .ringAndFree: "Ring and free space"
            case .ringOnly: "Ring only"
            case .freeOnly: "Free space only"
            case .percentUsed: "Percent used"
            }
        }
    }

    /// One-click actions in the popover. Each runs one bundled rule through the normal
    /// scan → verify → Restore Center path, so every action is undoable.
    enum QuickAction: String, CaseIterable, Identifiable {
        case emptyTrash, appCaches, derivedData, simulatorCaches
        var id: String { rawValue }

        var ruleID: String {
            switch self {
            case .emptyTrash: "trash.user"
            case .appCaches: "system.user-caches"
            case .derivedData: "dev.xcode.derived-data"
            case .simulatorCaches: "dev.simulator.caches"
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .emptyTrash: "Empty Trash"
            case .appCaches: "App Caches"
            case .derivedData: "DerivedData"
            case .simulatorCaches: "Simulators"
            }
        }

        var symbol: String {
            switch self {
            case .emptyTrash: "trash"
            case .appCaches: "shippingbox"
            case .derivedData: "hammer"
            case .simulatorCaches: "iphone"
            }
        }
    }

    enum ActionState: Equatable {
        case unknown
        case measuring
        /// `skipped` > 0 with nothing cleanable means the data exists but is in use or too recent.
        case ready(cleanable: Int64, skipped: Int64)
        case needsAccess
        case running
    }

    private unowned let app: AppModel

    // MARK: Preferences

    var isStorageItemShown: Bool { didSet { save(isStorageItemShown, .storageItem) } }
    var isCPUItemShown: Bool { didSet { save(isCPUItemShown, .cpuItem); updateSampling() } }
    var isMemoryItemShown: Bool { didSet { save(isMemoryItemShown, .memoryItem); updateSampling() } }
    var storageStyle: StorageStyle { didSet { UserDefaults.standard.set(storageStyle.rawValue, forKey: Key.style.rawValue) } }
    /// Keep running in the menu bar when the main window closes.
    var keepsRunningInMenuBar: Bool { didSet { save(keepsRunningInMenuBar, .keepRunning) } }

    // MARK: Live data

    private(set) var volumes: [VolumeInfo] = []
    private(set) var cpuUsage: Double?
    private(set) var cpuHistory: [Double] = []
    private(set) var memory: MemorySnapshot?
    private(set) var memoryHistory: [Double] = []
    private(set) var actionStates: [QuickAction: ActionState] = [:]
    /// Confirmation after a quick action: "Freed 2.1 GB" plus the operation to undo.
    private(set) var lastAction: (message: String, operationID: UUID?)?

    var isPopoverVisible = false { didSet { updateSampling() } }

    var rootVolume: VolumeInfo? { volumes.first(where: \.isRoot) ?? volumes.first }
    var externalVolumes: [VolumeInfo] { volumes.filter { !$0.isRoot } }

    private var cpuSampler = CPUSampler()
    private var storageTask: Task<Void, Never>?
    private var sampleTask: Task<Void, Never>?
    private var sampleInterval: Duration?
    private var lastMeasured: Date?
    private var observers: [NSObjectProtocol] = []

    private enum Key: String {
        case storageItem = "menuBar.storageItem"
        case cpuItem = "menuBar.cpuItem"
        case memoryItem = "menuBar.memoryItem"
        case style = "menuBar.storageStyle"
        case keepRunning = "menuBar.keepRunning"
    }

    init(app: AppModel) {
        self.app = app
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Key.storageItem.rawValue: true, Key.keepRunning.rawValue: true])
        isStorageItemShown = defaults.bool(forKey: Key.storageItem.rawValue)
        isCPUItemShown = defaults.bool(forKey: Key.cpuItem.rawValue)
        isMemoryItemShown = defaults.bool(forKey: Key.memoryItem.rawValue)
        storageStyle = StorageStyle(rawValue: defaults.string(forKey: Key.style.rawValue) ?? "") ?? .ringAndFree
        keepsRunningInMenuBar = defaults.bool(forKey: Key.keepRunning.rawValue)
        start()
    }

    private func save(_ value: Bool, _ key: Key) { UserDefaults.standard.set(value, forKey: key.rawValue) }

    // MARK: Sampling

    private func start() {
        refreshVolumes()
        storageTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshVolumes()
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVolumes() }
            })
        }
        updateSampling()
    }

    func refreshVolumes() {
        volumes = Volumes.mounted()
    }

    /// Runs CPU/memory sampling only when something on screen shows it.
    private func updateSampling() {
        let interval: Duration? = isPopoverVisible ? .seconds(1)
            : (isCPUItemShown || isMemoryItemShown) ? .seconds(2) : nil
        guard interval != sampleInterval else { return }
        sampleInterval = interval
        sampleTask?.cancel()
        sampleTask = nil
        guard let interval else { return }
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleNow()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func sampleNow() {
        if let usage = cpuSampler.sample() {
            cpuUsage = usage
            cpuHistory = Array((cpuHistory + [usage]).suffix(60))
        }
        if let snapshot = MemorySnapshot.current() {
            memory = snapshot
            memoryHistory = Array((memoryHistory + [snapshot.usedFraction]).suffix(60))
        }
    }

    // MARK: Popover lifecycle

    func popoverDidAppear() {
        isPopoverVisible = true
        refreshVolumes()
        app.refreshFullDiskAccess()
        Task { await app.refreshOperations() }
        // Re-measure quick actions at most once a minute.
        if let lastMeasured, Date.now.timeIntervalSince(lastMeasured) < 60 { return }
        measureQuickActions()
    }

    func popoverDidDisappear() {
        isPopoverVisible = false
    }

    // MARK: Quick actions

    private func rule(for action: QuickAction) -> Rule? { app.catalog?.rule(action.ruleID) }

    func measureQuickActions() {
        guard let catalog = app.catalog else { return }
        lastMeasured = .now
        let context = app.scanContext()
        for action in QuickAction.allCases {
            guard let rule = rule(for: action), actionStates[action] != .running else { continue }
            actionStates[action] = .measuring
            Task {
                let result = await Scanner().scan([rule], claimRules: catalog.rules, context: context).results.first
                guard actionStates[action] != .running else { return }
                if let result, result.items.isEmpty, result.accessDenied {
                    actionStates[action] = .needsAccess
                } else {
                    actionStates[action] = .ready(cleanable: result?.cleanableSize ?? 0,
                                                  skipped: result?.skippedSize ?? 0)
                }
            }
        }
    }

    func run(_ action: QuickAction) {
        guard let store = app.store, let catalog = app.catalog, let rule = rule(for: action) else { return }
        if actionStates[action] == .needsAccess {
            app.isShowingOnboarding = true
            openMainWindow()
            return
        }
        actionStates[action] = .running
        let context = app.scanContext()
        Task {
            let report = await Scanner().scan([rule], claimRules: catalog.rules, context: context)
            let items = report.results.flatMap(\.cleanableItems)
            do {
                let outcome = try await CleanupEngine(store: store)
                    .clean(items, rules: catalog.rules, module: rule.module, context: context)
                if outcome.freedSize > 0 {
                    lastAction = (String(localized: "Freed \(outcome.freedSize.bytesText)"), outcome.operation?.id)
                } else {
                    lastAction = (String(localized: "Nothing to clean right now"), nil)
                }
            } catch {
                lastAction = (String(localized: "Couldn't clean: \(error.localizedDescription)"), nil)
            }
            await app.refreshOperations()
            refreshVolumes()
            actionStates[action] = .unknown
            lastMeasured = nil
            measureQuickActions()
        }
    }

    func undoLastAction() {
        guard let id = lastAction?.operationID else { return }
        Task {
            if await app.restoreAll(id) { lastAction = (String(localized: "Restored"), nil) }
            refreshVolumes()
            lastMeasured = nil
            measureQuickActions()
        }
    }

    func undo(_ operationID: UUID) {
        Task {
            await app.restoreAll(operationID)
            refreshVolumes()
        }
    }

    // MARK: Volumes

    func eject(_ volume: VolumeInfo) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        } catch {
            app.show(String(localized: "Couldn't eject \(volume.name)"), error)
            openMainWindow()
        }
        refreshVolumes()
    }

    // MARK: Window & login item

    func openMainWindow() {
        AppDelegate.showMainWindow()
    }

    private(set) var loginItemStatus = SMAppService.mainApp.status

    var opensAtLogin: Bool { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }

    var loginItemNeedsApproval: Bool { loginItemStatus == .requiresApproval }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            app.show(String(localized: "Couldn't change the login item"), error)
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    func refreshLoginItemStatus() { loginItemStatus = SMAppService.mainApp.status }
}
