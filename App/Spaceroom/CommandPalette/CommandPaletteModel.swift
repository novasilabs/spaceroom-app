// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import SwiftUI

/// One thing the palette can do.
struct PaletteCommand: Identifiable {
    enum Kind: Int, CaseIterable {
        case recent, action, module, app, automation

        var title: String {
            switch self {
            case .recent: String(localized: "Recent")
            case .action: String(localized: "Actions")
            case .module: String(localized: "Go to")
            case .app: String(localized: "Apps")
            case .automation: String(localized: "Automations")
            }
        }
    }

    let id: String
    let title: String
    var subtitle: String?
    let symbol: String
    let tint: Color
    var keywords: [String] = []
    var kind: Kind
    var shortcut: String?
    /// Opens a confirmation before anything is removed.
    var asksFirst = false
    let perform: @MainActor () -> Void
}

/// ⌘K: jump anywhere, run actions, find apps and automations by typing.
@MainActor
@Observable
final class CommandPaletteModel {
    /// A one-step clean started from the palette, waiting for confirmation.
    struct QuickClean: Identifiable {
        let id = UUID()
        let title: String
        let plan: AutomationRunner.Plan
        let module: SidebarModule
    }

    /// A short message at the bottom of the window, with Undo when something moved.
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var operationID: UUID?
    }

    private unowned let app: AppModel

    private(set) var isPresented = false
    var query = "" { didSet { if query != oldValue { highlighted = 0 } } }
    var highlighted = 0
    var quickClean: QuickClean?
    private(set) var isPlanning = false
    private(set) var toast: Toast?
    @ObservationIgnored var openSettings: (() -> Void)?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private var recentIDs: [String] {
        didSet { UserDefaults.standard.set(recentIDs, forKey: "palette.recent") }
    }

    init(app: AppModel) {
        self.app = app
        recentIDs = UserDefaults.standard.stringArray(forKey: "palette.recent") ?? []
    }

    // MARK: Presenting

    func toggle() { isPresented ? close() : open() }

    func open() {
        if NSApp.keyWindow == nil { AppDelegate.showMainWindow() }
        query = ""
        highlighted = 0
        isPresented = true
        // Apps become searchable as soon as the palette is used.
        app.applications.loadIfNeeded()
    }

    func close() { isPresented = false }

    // MARK: Results

    /// With no query: recent, then actions, then modules. With a query: everything, best match first.
    var results: [PaletteCommand] {
        let all = allCommands
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty else {
            return FuzzyMatch.rank(all, query: trimmed, title: \.title, keywords: { $0.keywords + [$0.subtitle ?? ""] })
        }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var recent = recentIDs.compactMap { byID[$0] }.prefix(4).map { command in
            var command = command
            command.kind = .recent
            return command
        }
        let recentSet = Set(recent.map(\.id))
        recent += all.filter { ($0.kind == .action || $0.kind == .module) && !recentSet.contains($0.id) }
        return recent
    }

    func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    func runHighlighted() {
        let results = results
        guard results.indices.contains(highlighted) else { return }
        run(results[highlighted])
    }

    func run(_ command: PaletteCommand) {
        recentIDs = [command.id] + recentIDs.filter { $0 != command.id }.prefix(7)
        close()
        command.perform()
    }

    // MARK: Commands

    private var allCommands: [PaletteCommand] {
        actions + modules + apps + automations
    }

    private var actions: [PaletteCommand] {
        var list: [PaletteCommand] = [
            PaletteCommand(id: "action.smartCare", title: String(localized: "Run Smart Care"),
                           subtitle: String(localized: "Scan for everything safe to clean"),
                           symbol: "sparkles", tint: SidebarModule.smartCare.palette.accent,
                           keywords: ["scan", "clean", "junk", "one click"], kind: .action) { [app] in app.runSmartCare() },
            PaletteCommand(id: "action.scanCleanup", title: String(localized: "Scan for system junk"),
                           subtitle: String(localized: "Caches, logs and the Trash"),
                           symbol: SidebarModule.cleanup.symbol, tint: SidebarModule.cleanup.palette.accent,
                           keywords: ["cleanup", "cache", "logs"], kind: .action) { [weak self] in self?.startScan(.cleanup) },
            PaletteCommand(id: "action.scanDev", title: String(localized: "Scan for developer junk"),
                           subtitle: String(localized: "Xcode, simulators and package caches"),
                           symbol: SidebarModule.devCleanup.symbol, tint: SidebarModule.devCleanup.palette.accent,
                           keywords: ["dev cleanup", "xcode", "npm", "brew", "cache"], kind: .action) { [weak self] in self?.startScan(.devCleanup) },
            PaletteCommand(id: "action.emptyTrash", title: String(localized: "Empty the Trash…"),
                           subtitle: String(localized: "Moves it into the Restore Center"),
                           symbol: "trash", tint: SidebarModule.cleanup.palette.accent,
                           keywords: ["bin", "delete", "trash"], kind: .action, asksFirst: true) { [weak self] in
                self?.prepareQuickClean(.emptyTrash, title: String(localized: "Empty the Trash"), module: .cleanup)
            },
            PaletteCommand(id: "action.derivedData", title: String(localized: "Clear Xcode DerivedData…"),
                           subtitle: String(localized: "Build files Xcode rebuilds on the next build"),
                           symbol: "hammer", tint: SidebarModule.devCleanup.palette.accent,
                           keywords: ["xcode", "build", "derived data", "purge"], kind: .action, asksFirst: true) { [weak self] in
                self?.prepareQuickClean(.purgeDerivedData(olderThanDays: 0), title: String(localized: "Clear Xcode DerivedData"),
                                        module: .devCleanup)
            },
            PaletteCommand(id: "action.protection", title: String(localized: "Scan for malware"),
                           subtitle: String(localized: "Find files disguised to trick you"),
                           symbol: SidebarModule.protection.symbol, tint: SidebarModule.protection.palette.accent,
                           keywords: ["virus", "protection", "security", "threat"], kind: .action) { [app] in
                app.selection = .protection
                app.protection.startScan()
            },
            PaletteCommand(id: "action.spaceLens", title: String(localized: "Map my disk"),
                           subtitle: String(localized: "Scan your home folder with Space Lens"),
                           symbol: SidebarModule.spaceLens.symbol, tint: SidebarModule.spaceLens.palette.accent,
                           keywords: ["space lens", "storage", "what is using space", "big folders"], kind: .action) { [app] in
                app.selection = .spaceLens
                if app.spaceLens.phase == .intro { app.spaceLens.start() }
            },
            PaletteCommand(id: "action.tour", title: String(localized: "Show Welcome Tour"),
                           subtitle: String(localized: "What Spaceroom does and how it keeps you safe"),
                           symbol: "hand.wave", tint: SidebarModule.smartCare.palette.accent,
                           keywords: ["onboarding", "welcome", "help", "tour"], kind: .action) { [app] in
                app.hasCompletedOnboarding = false
                app.isShowingOnboarding = true
            },
            PaletteCommand(id: "action.settings", title: String(localized: "Settings…"),
                           symbol: "gearshape", tint: .hex(0x8E8E98),
                           keywords: ["preferences", "retention", "menu bar"], kind: .action, shortcut: "⌘,") { [weak self] in
                self?.openSettings?()
            },
        ]
        if app.fullDiskAccess != .granted {
            list.append(PaletteCommand(id: "action.fda", title: String(localized: "Allow Full Disk Access…"),
                                       subtitle: String(localized: "Lets Spaceroom see protected caches and Safari data"),
                                       symbol: "lock.shield", tint: .hex(0xE0A93A),
                                       keywords: ["permission", "privacy", "fda"], kind: .action) { [app] in
                app.isShowingOnboarding = true
            })
        }
        return list
    }

    private var modules: [PaletteCommand] {
        SidebarModule.allCases.enumerated().map { index, module in
            PaletteCommand(id: "module.\(module.rawValue)", title: String(localized: module.title),
                           subtitle: String(localized: module.tagline), symbol: module.symbol, tint: module.palette.accent,
                           keywords: module.paletteKeywords, kind: .module, shortcut: index < 9 ? "⌘\(index + 1)" : nil) { [app] in
                app.selection = module
            }
        }
    }

    /// Installed apps, once Applications has listed them. Only shown while searching.
    private var apps: [PaletteCommand] {
        let model = app.applications
        guard model.hasLoaded else { return [] }
        return model.rows.filter { !$0.app.isProtected }.map { row in
            PaletteCommand(id: "app.\(row.id)", title: row.app.name,
                           subtitle: row.size.map { String(localized: "Uninstall · \($0.bytesText)") } ?? String(localized: "Uninstall"),
                           symbol: "app.dashed", tint: SidebarModule.applications.palette.accent,
                           keywords: ["uninstall", "remove", row.app.bundleID], kind: .app) { [app] in
                app.selection = .applications
                app.applications.tab = .installed
                app.applications.selectedID = row.id
            }
        }
    }

    private var automations: [PaletteCommand] {
        app.automations.automations.map { automation in
            PaletteCommand(id: "automation.\(automation.id)", title: String(localized: "Run now: \(automation.action.title)"),
                           subtitle: automation.trigger.summary, symbol: automation.action.symbol,
                           tint: SidebarModule.automations.palette.accent,
                           keywords: ["automation", "schedule", "run"], kind: .automation) { [app] in
                app.selection = .automations
                app.automations.runNow(automation)
            }
        }
    }

    private func startScan(_ module: CleanModule) {
        let sidebar: SidebarModule = module == .cleanup ? .cleanup : .devCleanup
        app.selection = sidebar
        guard let flow = app.flow(for: .module(module)) else { return }
        if flow.phase == .done { flow.finish() }
        if flow.phase == .intro { flow.startScan() }
    }

    // MARK: Quick clean

    /// Measures first, then asks; nothing moves until the confirmation is accepted.
    private func prepareQuickClean(_ action: AutomationAction, title: String, module: SidebarModule) {
        if let reason = app.cleaningBlockedReason {
            showToast(reason)
            return
        }
        guard let catalog = app.catalog, let store = app.store, !isPlanning else { return }
        isPlanning = true
        showToast(String(localized: "Measuring…"), duration: 30)
        let context = app.scanContext()
        Task {
            let plan = await AutomationRunner(catalog: catalog, store: store).plan(action, context: context)
            isPlanning = false
            if plan.items.isEmpty {
                showToast(plan.skippedCount > 0
                          ? String(localized: "Nothing can be cleaned right now: \(plan.skippedCount) items are in use or too new.")
                          : String(localized: "Nothing to clean. It's already empty."))
            } else {
                dismissToast()
                quickClean = QuickClean(title: title, plan: plan, module: module)
            }
        }
    }

    func confirmQuickClean() {
        guard let pending = quickClean, let catalog = app.catalog, let store = app.store else { return }
        quickClean = nil
        let context = app.scanContext()
        let operationName = pending.module.rawValue
        Task {
            let result = await AutomationRunner(catalog: catalog, store: store)
                .clean(pending.plan, operationName: operationName, context: context)
            await app.refreshOperations()
            if let error = result.error {
                showToast(String(localized: "Couldn't clean: \(error)"))
            } else if result.cleanedBytes > 0 {
                showToast(String(localized: "Moved \(result.cleanedBytes.bytesText) to the Restore Center"), operationID: result.operationID)
            } else {
                showToast(String(localized: "Nothing was cleaned. The items changed or are in use."))
            }
        }
    }

    // MARK: Toast

    func showToast(_ message: String, operationID: UUID? = nil, duration: Double = 6) {
        toastTask?.cancel()
        toast = Toast(message: message, operationID: operationID)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func undoToast() {
        guard let id = toast?.operationID else { return }
        dismissToast()
        Task {
            if await app.restoreAll(id) { showToast(String(localized: "Restored. Everything is back.")) }
        }
    }
}

extension SidebarModule {
    /// Extra words people might type for a module.
    var paletteKeywords: [String] {
        switch self {
        case .smartCare: ["scan", "one click", "clean"]
        case .cleanup: ["junk", "cache", "logs", "trash"]
        case .devCleanup: ["xcode", "developer", "npm", "docker", "simulator"]
        case .clutter: ["large files", "old files", "duplicates", "downloads", "installers"]
        case .spaceLens: ["disk map", "storage", "what is using space"]
        case .status: ["cpu", "memory", "ram", "battery", "health", "network"]
        case .applications: ["uninstall", "apps", "leftovers"]
        case .startup: ["login items", "launch agents", "background", "persistence"]
        case .protection: ["malware", "virus", "security", "threat", "disguised", "trojan"]
        case .performance: ["maintenance", "speed", "dns", "spotlight"]
        case .privacy: ["browser", "history", "cookies", "permissions", "camera"]
        case .restoreCenter: ["undo", "quarantine", "restore", "history"]
        case .automations: ["schedule", "automatic", "rules"]
        }
    }
}
