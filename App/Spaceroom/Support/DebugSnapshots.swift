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

    static func runIfRequested(_ app: AppModel) async {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        app.isShowingOnboarding = true
        await pause(1.2)
        capture("01-onboarding", in: directory, sheet: true)

        app.isShowingOnboarding = false
        app.selection = .cleanup
        await pause(1.2)
        capture("02-cleanup-intro", in: directory)

        if let flow = app.flow(for: .cleanup) {
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
        if let flow = app.flow(for: .devCleanup) {
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
