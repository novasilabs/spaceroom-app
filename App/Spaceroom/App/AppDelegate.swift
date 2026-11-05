// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Keeps Spaceroom alive in the menu bar after the main window closes, and hides the Dock
/// icon while only the menu bar is in use.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by views that can open SwiftUI windows (they own the `openWindow` action).
    static var openMainWindowAction: (() -> Void)?

    private var closeObserver: NSObjectProtocol?

    static var keepsRunningInMenuBar: Bool {
        let defaults = UserDefaults.standard
        let keepRunning = defaults.object(forKey: "menuBar.keepRunning") as? Bool ?? true
        let anyItem = (defaults.object(forKey: "menuBar.storageItem") as? Bool ?? true)
            || defaults.bool(forKey: "menuBar.cpuItem") || defaults.bool(forKey: "menuBar.memoryItem")
        return keepRunning && anyItem
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openMainWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { notification in
            let closing = notification.object as? NSWindow
            MainActor.assumeIsolated { Self.windowWillClose(closing) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Self.keepsRunningInMenuBar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.showMainWindow() }
        return true
    }

    /// After the last regular window closes, drop the Dock icon (menu bar only).
    private static func windowWillClose(_ closing: NSWindow?) {
        guard keepsRunningInMenuBar, let closing, closing.styleMask.contains(.titled) else { return }
        // Let the close finish before checking what's left.
        Task { @MainActor in
            let remaining = NSApp.windows.filter { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) }
            if remaining.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
