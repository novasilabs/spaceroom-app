// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import UserNotifications

/// Automations: saved "when → do" rules, checked once a minute (and on wake) while Spaceroom runs.
@MainActor
@Observable
final class AutomationsModel {
    private unowned let app: AppModel
    @ObservationIgnored private let store: AutomationStore?
    let storeError: String?

    private(set) var automations: [Automation] = []
    private(set) var history: [AutomationRun] = []
    private(set) var runningID: UUID?
    private(set) var hasLoaded = false

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var wasPluggedIn: Bool?
    @ObservationIgnored let notifier = AutomationNotifier()

    init(app: AppModel) {
        self.app = app
        do {
            store = try AutomationStore()
            storeError = nil
        } catch {
            store = nil
            storeError = String(describing: error)
        }
    }

    /// Loads saved automations and, unless `schedules` is false (snapshot tour), starts checking them.
    func start(schedules: Bool) {
        Task {
            await reload()
            guard schedules, loop == nil else { return }
            notifier.activate { [weak self] module in
                self?.app.selection = module
                AppDelegate.showMainWindow()
            }
            wasPluggedIn = BatteryInfo.current()?.isPluggedIn
            await check(isLaunch: true)
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await self?.check(isLaunch: false)
                }
            }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.check(isLaunch: false) }
            }
        }
    }

    private func reload() async {
        guard let store else { hasLoaded = true; return }
        automations = await store.automations
        history = await store.history
        hasLoaded = true
    }

    private func check(isLaunch: Bool) async {
        guard runningID == nil else { return }
        let plugged = BatteryInfo.current()?.isPluggedIn
        let didPlugIn = wasPluggedIn == false && plugged == true
        wasPluggedIn = plugged
        let context = AutomationContext(now: .now, freeBytes: Volumes.root()?.availableBytes,
                                        isLaunch: isLaunch, didPlugIn: didPlugIn)
        for automation in automations where AutomationSchedule.isDue(automation, context: context) {
            await run(automation, isManual: false)
        }
    }

    // MARK: Running

    var isBusy: Bool { runningID != nil }

    func runNow(_ automation: Automation) {
        Task { await run(automation, isManual: true) }
    }

    private func run(_ automation: Automation, isManual: Bool) async {
        guard let store, runningID == nil, let catalog = app.catalog, let restore = app.store else { return }
        runningID = automation.id
        let result = await AutomationRunner(catalog: catalog, store: restore).run(automation, context: app.scanContext())
        do {
            try await store.record(result)
        } catch {
            app.show(String(localized: "Couldn't save the automation run"), error)
        }
        await reload()
        // Only now: a check in between would still see the old "last run" and start it again.
        runningID = nil
        if result.operationID != nil || result.freedNow { await app.refreshOperations() }
        // Someone who pressed Run Now sees the result on screen; notifications are for unattended runs.
        if automation.notifies && !isManual { notifier.post(result, retentionDays: app.retentionDays) }
    }

    /// Whether a run's items are still in the Restore Center, so it can be undone.
    func canUndo(_ run: AutomationRun) -> Bool {
        guard let id = run.operationID else { return false }
        return app.operations.first { $0.id == id }?.hasStoredItems == true
    }

    func undo(_ run: AutomationRun) {
        guard let id = run.operationID else { return }
        Task { _ = await app.restoreAll(id) }
    }

    func automation(for run: AutomationRun) -> Automation? { automations.first { $0.id == run.automationID } }

    // MARK: Editing

    func save(_ automation: Automation) {
        guard let store else { return }
        Task {
            do {
                try await store.save(automation)
            } catch {
                app.show(String(localized: "Couldn't save the automation"), error)
            }
            await reload()
            if automation.notifies { notifier.requestAuthorization() }
        }
    }

    func setEnabled(_ automation: Automation, _ isEnabled: Bool) {
        var changed = automation
        changed.isEnabled = isEnabled
        // Switching back on starts fresh: no catch-up run for moments missed while it was off.
        if isEnabled { changed.createdAt = .now }
        save(changed)
    }

    func delete(_ automation: Automation) {
        guard let store else { return }
        Task {
            do {
                try await store.delete(automation.id)
            } catch {
                app.show(String(localized: "Couldn't delete the automation"), error)
            }
            await reload()
        }
    }

    /// Ready-made automations that aren't set up yet.
    var suggestions: [Automation] {
        Self.templates.filter { template in
            !automations.contains { $0.trigger == template.trigger && $0.action == template.action }
        }
    }

    static var templates: [Automation] {
        [Automation(trigger: .weekly(weekday: 7, hour: 10, minute: 0), action: .scanAndNotify),
         // Keeping items in the Restore Center wouldn't help a full disk, so this one frees space at once.
         Automation(trigger: .lowDisk(freeBelowGB: 10), action: .smartCareClean, freesSpaceNow: true),
         Automation(trigger: .weekly(weekday: 2, hour: 9, minute: 0), action: .emptyTrash),
         Automation(trigger: .daily(hour: 12, minute: 0), action: .purgeDerivedData(olderThanDays: 30))]
    }

    func nextRunText(_ automation: Automation) -> String {
        guard automation.isEnabled else { return String(localized: "Off") }
        if let next = AutomationSchedule.nextFire(automation.trigger, after: .now) {
            return String(localized: "Next \(next.formatted(.relative(presentation: .named)))")
        }
        return switch automation.trigger {
        case .lowDisk: String(localized: "Checks every minute")
        case .atLogin: String(localized: "Next time Spaceroom opens")
        case .pluggedIn: BatteryInfo.current() == nil ? String(localized: "Only on laptops") : String(localized: "Next time you plug in")
        default: ""
        }
    }
}

/// Posts run results and opens the right module when one is clicked.
@MainActor
final class AutomationNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var onOpen: ((SidebarModule) -> Void)?

    func activate(onOpen: @escaping (SidebarModule) -> Void) {
        self.onOpen = onOpen
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ run: AutomationRun, retentionDays: Int) {
        let content = UNMutableNotificationContent()
        var module = SidebarModule.automations
        if let error = run.error {
            content.title = String(localized: "An automation couldn't finish")
            content.body = error
        } else if run.action == .scanAndNotify {
            // Small finds aren't worth an interruption.
            guard run.foundBytes >= 100_000_000 else { return }
            content.title = String(localized: "\(run.foundBytes.bytesText) can be cleaned")
            content.body = String(localized: "Your scheduled check found junk Smart Care can clean. Nothing was removed.")
            module = .smartCare
        } else {
            guard run.cleanedBytes > 0 else { return }
            content.title = String(localized: "Cleaned \(run.cleanedBytes.bytesText)")
            content.body = run.freedNow
                ? String(localized: "\(run.action.title). The space is free now.")
                : String(localized: "\(run.action.title). It's in the Restore Center for \(retentionDays) days if you need it back.")
        }
        content.userInfo = ["module": module.rawValue]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: run.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["module"] as? String
        Task { @MainActor in
            if let raw, let module = SidebarModule(rawValue: raw) { self.onOpen?(module) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

// MARK: - Wording

extension AutomationAction {
    var title: String {
        switch self {
        case .scanAndNotify: String(localized: "Check for junk and tell me")
        case .smartCareClean: String(localized: "Run Smart Care cleanup")
        case .emptyTrash: String(localized: "Empty the Trash")
        case .purgeDerivedData(let days): String(localized: "Clear Xcode builds older than \(days) days")
        }
    }

    var detail: String {
        switch self {
        case .scanAndNotify: String(localized: "Scans with the Smart Care rules and tells you what it found. Nothing is removed.")
        case .smartCareClean: String(localized: "Cleans the same regenerable caches, logs and Trash as one-click Smart Care.")
        case .emptyTrash: String(localized: "Moves what's in the Trash into the Restore Center.")
        case .purgeDerivedData: String(localized: "Only DerivedData of projects you haven't built for that long. Xcode rebuilds it when needed.")
        }
    }

    var symbol: String {
        switch self {
        case .scanAndNotify: "bell.badge"
        case .smartCareClean: "sparkles"
        case .emptyTrash: "trash"
        case .purgeDerivedData: "hammer"
        }
    }
}

extension AutomationTrigger {
    var summary: String {
        switch self {
        case .daily(let hour, let minute):
            String(localized: "Every day at \(Self.time(hour, minute))")
        case .weekly(let weekday, let hour, let minute):
            String(localized: "Every \(Self.weekdayName(weekday)) at \(Self.time(hour, minute))")
        case .lowDisk(let gigabytes):
            String(localized: "When free space drops below \(gigabytes) GB")
        case .atLogin:
            String(localized: "When Spaceroom opens")
        case .pluggedIn:
            String(localized: "When you plug in power")
        }
    }

    var symbol: String {
        switch self {
        case .daily, .weekly: "calendar"
        case .lowDisk: "internaldrive"
        case .atLogin: "person.crop.circle"
        case .pluggedIn: "powerplug"
        }
    }

    static func time(_ hour: Int, _ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(max(1, min(7, weekday)) - 1) % symbols.count]
    }
}
