// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import SwiftUI

/// Debug-only UI tour: `SPACEROOM_SNAPSHOT_DIR=/some/dir` makes the app step through its main
/// screens and write a PNG of each. It only scans — it never cleans or changes files.
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SPACEROOM_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested(_ app: AppModel, menuBar: MenuBarModel) async {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        await captureMenuBar(app: app, menuBar: menuBar, in: directory)

        app.isShowingOnboarding = true
        await pause(1.2)
        capture("01-onboarding", in: directory, sheet: true)

        app.isShowingOnboarding = false
        app.selection = .smartCare
        await pause(1.2)
        capture("02a-smartcare-intro", in: directory)
        if let flow = app.flow(for: .smartCare) {
            flow.startScan()
            await pause(0.5)
            capture("02b-smartcare-scanning", in: directory)
            await waitUntil { flow.phase == .results }
            await pause(1.0)
            capture("02c-smartcare-results", in: directory)
        }

        app.selection = .cleanup
        await pause(1.2)
        capture("02-cleanup-intro", in: directory)

        if let flow = app.flow(for: .module(.cleanup)) {
            flow.startScan()
            await pause(0.4)
            capture("03-cleanup-scanning", in: directory)
            await waitUntil { flow.phase == .results }
            await pause(1.0)
            capture("04-cleanup-results", in: directory)
            flow.isReviewing = true
            await pause(1.0)
            capture("05-cleanup-review", in: directory)
            flow.isReviewing = false
        }

        app.selection = .devCleanup
        if let flow = app.flow(for: .module(.devCleanup)) {
            flow.startScan()
            await waitUntil { flow.phase == .results }
            await pause(1.0)
            capture("06-dev-results", in: directory)
        }

        app.selection = .restoreCenter
        await pause(1.0)
        capture("07-restore-center", in: directory)

        app.selection = .spaceLens
        await pause(1.0)
        capture("08-placeholder", in: directory)

        NSApp.terminate(nil)
    }

    /// Renders the popover in an off-screen window and the status item images in both appearances.
    private static func captureMenuBar(app: AppModel, menuBar: MenuBarModel, in directory: URL) async {
        let host = NSHostingView(rootView: MenuBarPopover().environment(app).environment(menuBar))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 340, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        await waitUntil(timeout: 60) {
            !menuBar.actionStates.isEmpty && !menuBar.actionStates.values.contains(.measuring)
        }
        await pause(2.5) // let CPU/memory sparklines collect a few samples
        host.setFrameSize(host.fittingSize)
        window.setContentSize(host.fittingSize)
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("00-menubar-popover.png"))
        }
        window.orderOut(nil)

        // Design tuning panel.
        let tuning = NSHostingView(rootView: DesignTuningPanel())
        let tuningWindow = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 380, height: 900),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        tuningWindow.contentView = tuning
        tuningWindow.orderFrontRegardless()
        await pause(0.8)
        if let rep = tuning.bitmapImageRepForCachingDisplay(in: tuning.bounds) {
            tuning.cacheDisplay(in: tuning.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("09-design-tuning.png"))
        }
        tuningWindow.orderOut(nil)

        var images: [NSImage] = MenuBarModel.StorageStyle.allCases.map {
            StatusItemImage.storage(menuBar.rootVolume, style: $0)
        }
        images.append(StatusItemImage.cpu(menuBar.cpuUsage, history: menuBar.cpuHistory))
        images.append(StatusItemImage.memory(menuBar.memory))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            writeStrip(images, appearance: NSAppearance(named: appearance)!,
                       to: directory.appendingPathComponent("00-menubar-items-\(name).png"))
        }
    }

    private static func writeStrip(_ images: [NSImage], appearance: NSAppearance, to url: URL) {
        let scale: CGFloat = 3
        let width = images.reduce(CGFloat(16)) { $0 + $1.size.width + 16 }
        let size = NSSize(width: width, height: 26)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            (appearance.name == .darkAqua ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(origin: .zero, size: size).fill()
            var x: CGFloat = 16
            for image in images {
                image.draw(in: NSRect(x: x, y: 4, width: image.size.width, height: image.size.height))
                x += image.size.width + 16
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func waitUntil(timeout: Double = 120, _ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition(), Date.now < deadline { await pause(0.25) }
    }

    private static func capture(_ name: String, in directory: URL, sheet: Bool = false) {
        guard let main = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil && $0.frame.width >= 900 })
        else { return }
        let window = sheet ? (main.attachedSheet ?? main) : main
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}
#endif
