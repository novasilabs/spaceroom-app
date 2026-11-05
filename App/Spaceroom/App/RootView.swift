// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Main window: full-bleed module gradient, translucent sidebar, module content.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 236)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .overlay {
            if app.palette.isPresented {
                CommandPaletteView(model: app.palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(Easing.out(0.15), value: app.palette.isPresented)
        .overlay(alignment: .bottom) {
            if let toast = app.palette.toast {
                ToastView(toast: toast, onUndo: { app.palette.undoToast() }, onDismiss: { app.palette.dismissToast() })
                    .padding(.bottom, 84)
                    .padding(.leading, 236)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .id(toast.id)
            }
        }
        .animation(Easing.out(0.2), value: app.palette.toast)
        .sheet(item: Bindable(app.palette).quickClean) { pending in
            ConfirmSheet(symbol: pending.module.symbol,
                         title: String(localized: "\(pending.title): \(pending.plan.size.bytesText)?"),
                         message: String(localized: "It moves to the Restore Center, so you can bring it back for \(app.retentionDays) days."),
                         details: [.init(symbol: "doc.on.doc", text: String(localized: "\(pending.plan.items.count) items")),
                                   .init(symbol: "checkmark.shield", text: pending.plan.rules.first?.whySafe ?? "")]
                             + (pending.plan.skippedCount > 0
                                ? [.init(symbol: "hand.raised", text: String(localized: "\(pending.plan.skippedCount) items in use or too new are left alone"))]
                                : []),
                         confirmTitle: String(localized: "Move to Restore Center"),
                         onConfirm: { app.palette.confirmQuickClean() },
                         onCancel: { app.palette.quickClean = nil })
        }
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
            app.palette.openSettings = { openSettings() }
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
            } else if module == .protection {
                ProtectionView(model: app.protection)
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
