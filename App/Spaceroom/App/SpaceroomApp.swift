// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct SpaceroomApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        Window("Spaceroom", id: "main") {
            RootView()
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
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

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
