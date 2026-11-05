// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct SpaceroomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app: AppModel
    @State private var menuBar: MenuBarModel

    init() {
        Self.migrateLegacyDefaults()
        let app = AppModel()
        _app = State(initialValue: app)
        _menuBar = State(initialValue: MenuBarModel(app: app))
    }

    /// Builds up to 0.9.0 used the bundle ID `io.github.spaceroom-app.spaceroom`. Carry their
    /// settings over once so testers don't lose them. Keys already set are left alone.
    private static func migrateLegacyDefaults() {
        guard ProcessInfo.processInfo.environment["SPACEROOM_SNAPSHOT_DIR"] == nil else { return }
        let defaults = UserDefaults.standard
        let marker = "migratedLegacyDefaults"
        guard !defaults.bool(forKey: marker),
              let legacy = defaults.persistentDomain(forName: "io.github.spaceroom-app.spaceroom") else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: marker)
    }

    var body: some Scene {
        Window("Spaceroom", id: "main") {
            RootView()
                .environment(app)
                .environment(menuBar)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            #if DEBUG
            CommandGroup(after: .windowArrangement) { DesignTuningCommand() }
            #endif
            CommandMenu("Modules") {
                Button("Search and Commands…") { app.palette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                ForEach(Array(SidebarModule.allCases.enumerated()), id: \.element) { index, module in
                    if index < 9 {
                        Button(String(localized: module.title)) { app.selection = module }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    } else {
                        Button(String(localized: module.title)) { app.selection = module }
                    }
                }
            }
        }

        // One menu bar item (PRD §6.12) showing every chosen reading, opening one popover.
        MenuBarExtra(isInserted: binding(\.isMenuBarItemShown)) {
            popover
        } label: {
            Image(nsImage: StatusItemImage.combined(menuBarParts))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
                .environment(menuBar)
        }

        #if DEBUG
        Window("Design Tuning", id: "design-tuning") {
            DesignTuningPanel()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        #endif
    }

    private var menuBarParts: [NSImage] {
        var parts: [NSImage] = []
        if menuBar.isStorageItemShown { parts.append(StatusItemImage.storage(menuBar.rootVolume, style: menuBar.storageStyle)) }
        if menuBar.isCPUItemShown { parts.append(StatusItemImage.cpu(menuBar.cpuUsage, history: menuBar.cpuHistory)) }
        if menuBar.isMemoryItemShown { parts.append(StatusItemImage.memory(menuBar.memory)) }
        return parts
    }

    private var popover: some View {
        MenuBarPopover()
            .environment(app)
            .environment(menuBar)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<MenuBarModel, Bool>) -> Binding<Bool> {
        let menuBar = menuBar
        // Only write real changes: MenuBarExtra re-sends `isInserted` on every update, and an
        // @Observable write always notifies — writing unchanged values loops the App body forever.
        return Binding(get: { menuBar[keyPath: keyPath] },
                       set: { if menuBar[keyPath: keyPath] != $0 { menuBar[keyPath: keyPath] = $0 } })
    }
}
