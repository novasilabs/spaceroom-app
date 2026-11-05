// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct SpaceroomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app: AppModel
    @State private var menuBar: MenuBarModel

    init() {
        let app = AppModel()
        _app = State(initialValue: app)
        _menuBar = State(initialValue: MenuBarModel(app: app))
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

        // Menu bar items (PRD §6.12). Each opens the same popover.
        MenuBarExtra(isInserted: binding(\.isStorageItemShown)) {
            popover
        } label: {
            Image(nsImage: StatusItemImage.storage(menuBar.rootVolume, style: menuBar.storageStyle))
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: binding(\.isCPUItemShown)) {
            popover
        } label: {
            Image(nsImage: StatusItemImage.cpu(menuBar.cpuUsage, history: menuBar.cpuHistory))
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: binding(\.isMemoryItemShown)) {
            popover
        } label: {
            Image(nsImage: StatusItemImage.memory(menuBar.memory))
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
