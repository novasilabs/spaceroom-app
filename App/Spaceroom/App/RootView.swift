// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Main window: full-bleed module gradient, translucent sidebar, module content.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 236)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .background {
            ZStack {
                ModuleBackground(module: app.selection)
                    .id(app.selection)
                    .transition(.opacity)
            }
            .animation(Motion.moduleSwitch, value: app.selection)
        }
        .frame(minWidth: 1000, minHeight: 680)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $app.isShowingOnboarding) { OnboardingView() }
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .task {
            await app.onLaunch()
            #if DEBUG
            await DebugSnapshots.runIfRequested(app, menuBar: menuBar)
            #endif
        }
        .onAppear {
            AppDelegate.openMainWindowAction = { openWindow(id: "main") }
            NSApp.setActivationPolicy(.regular)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshFullDiskAccess()
        }
    }

    @ViewBuilder
    private var detail: some View {
        let module = app.selection
        Group {
            if module == .restoreCenter {
                RestoreCenterView()
            } else if module == .spaceLens {
                SpaceLensView(model: app.spaceLens)
            } else if module == .applications {
                ApplicationsView(model: app.applications)
            } else if module == .clutter {
                ClutterView(model: app.clutter)
            } else if module == .status {
                StatusView(model: app.status)
            } else if module == .startup {
                StartupView(model: app.startup)
            } else if module == .performance {
                PerformanceView(model: app.performance)
            } else if module == .privacy {
                PrivacyView(model: app.privacy)
            } else if module == .automations {
                AutomationsView(model: app.automations)
            } else if let kind = module.flowKind, let flow = app.flow(for: kind) {
                ScanFlowView(module: module, flow: flow)
            } else {
                PlaceholderModuleView(module: module)
            }
        }
        .id(module)
        .transition(.opacity)
        .animation(Motion.moduleSwitch, value: module)
    }
}
