// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import os
import SpaceroomCore
import SwiftUI

/// Protection: scans personal folders for disguised and tampered files, and moves the ones you
/// pick into the Restore Center.
@MainActor
@Observable
final class ProtectionModel {
    enum Phase: Equatable { case intro, scanning, results }

    private unowned let app: AppModel

    private(set) var phase: Phase = .intro
    private(set) var scannedFiles = 0
    private(set) var report: ProtectionReport?
    var selection: Set<String> = []
    private(set) var isWorking = false
    private(set) var lastResult: (message: String, operationID: UUID?)?

    /// Last finished scan, kept for the menu bar tile.
    private(set) var lastScanDate: Date?
    private(set) var lastScanCount: Int

    @ObservationIgnored private var cancelFlag = OSAllocatedUnfairLock(initialState: false)
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Snapshot tour only: scan a fixture folder instead of the real personal folders.
    @ObservationIgnored var debugRoots: [URL]?

    private enum Keys {
        static let ignored = "protection.ignored"
        static let lastScan = "protection.lastScan"
        static let lastCount = "protection.lastCount"
    }

    init(app: AppModel) {
        self.app = app
        let defaults = UserDefaults.standard
        lastScanDate = defaults.object(forKey: Keys.lastScan) as? Date
        lastScanCount = defaults.integer(forKey: Keys.lastCount)
    }

    var findings: [ThreatFinding] {
        (report?.findings ?? []).filter { !app.ignoreList.ignores($0.url) && FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func findings(_ severity: ThreatSeverity) -> [ThreatFinding] { findings.filter { $0.severity == severity } }

    var selectedFindings: [ThreatFinding] { findings.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedFindings.reduce(0) { $0 + $1.size } }
    /// Findings of the last scan hidden by the ignore list.
    var ignoredCount: Int { (report?.findings ?? []).filter { app.ignoreList.ignores($0.url) }.count }

    /// Protection kept its own ignore list before the app-wide one existed; fold it in once.
    func migrateLegacyIgnores() {
        let defaults = UserDefaults.standard
        guard let paths = defaults.stringArray(forKey: Keys.ignored), !paths.isEmpty else { return }
        for path in paths { app.ignore(.path(URL(fileURLWithPath: path))) }
        defaults.removeObject(forKey: Keys.ignored)
    }

    // MARK: Scanning

    func startScan() {
        guard phase != .scanning else { return }
        cancelFlag.withLock { $0 = false }
        scannedFiles = 0
        lastResult = nil
        phase = .scanning
        let roots = debugRoots ?? ProtectionScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        let flag = cancelFlag
        scanTask = Task {
            let report = await Task.detached(priority: .userInitiated) {
                ProtectionScanner().scan(roots, isCancelled: { flag.withLock { $0 } }) { count in
                    Task { @MainActor [weak self] in self?.scannedFiles = count }
                }
            }.value
            finish(report)
        }
    }

    func cancelScan() {
        cancelFlag.withLock { $0 = true }
    }

    private func finish(_ report: ProtectionReport) {
        guard !report.wasCancelled else {
            phase = self.report == nil ? .intro : .results
            return
        }
        self.report = report
        // Only the clearest cases start ticked; the rest are for you to judge.
        selection = Set(findings.filter { $0.severity == .high }.map(\.id))
        lastScanDate = report.finishedAt
        lastScanCount = findings.count
        // A fixture scan (snapshot tour) must never change what the real menu bar shows.
        if debugRoots == nil {
            UserDefaults.standard.set(report.finishedAt, forKey: Keys.lastScan)
            UserDefaults.standard.set(lastScanCount, forKey: Keys.lastCount)
        }
        phase = .results
    }

    // MARK: Acting

    func toggle(_ finding: ThreatFinding) {
        if selection.contains(finding.id) { selection.remove(finding.id) } else { selection.insert(finding.id) }
    }

    func reveal(_ finding: ThreatFinding) { Finder.reveal(finding.url) }

    func ignore(_ finding: ThreatFinding) {
        app.ignore(.path(finding.url))
        selection.remove(finding.id)
        lastScanCount = findings.count
        UserDefaults.standard.set(lastScanCount, forKey: Keys.lastCount)
    }


    func removeSelected() {
        guard let store = app.store else { return }
        let chosen = selectedFindings
        guard !chosen.isEmpty else { return }
        isWorking = true
        Task {
            do {
                let outcome = try await ThreatRemover(store: store).remove(chosen)
                await app.refreshOperations()
                var message: String
                if let operation = outcome.operation {
                    message = String(localized: "Moved \(operation.items.count) items to the Restore Center.")
                } else {
                    message = String(localized: "Nothing was moved. The files changed or are protected.")
                }
                // A running program would keep running from its new place, so it's never moved.
                let running = outcome.skipped.compactMap { item -> String? in
                    if case .running(let name) = item.reason { return name }
                    return nil
                }
                if !running.isEmpty {
                    message += " " + String(localized: "Still running, so not moved: \(Set(running).sorted().formatted(.list(type: .and))). Quit and try again.")
                }
                lastResult = (message, outcome.operation?.id)
            } catch {
                app.show(String(localized: "Couldn't move the files"), error)
            }
            selection = []
            lastScanCount = findings.count
            UserDefaults.standard.set(lastScanCount, forKey: Keys.lastCount)
            isWorking = false
        }
    }

    func undoLast() {
        guard let id = lastResult?.operationID else { return }
        Task {
            if await app.restoreAll(id) { lastResult = (String(localized: "Restored. Everything is back."), nil) }
            lastScanCount = findings.count
        }
    }

    func dismissResult() { lastResult = nil }
}

extension ThreatKind {
    var title: String {
        switch self {
        case .disguisedProgram: String(localized: "Program disguised as a file")
        case .deceptiveName: String(localized: "Misleading name")
        case .hiddenPayload: String(localized: "Code hidden in an image")
        case .activePDF: String(localized: "PDF that runs code")
        case .unsignedApp: String(localized: "Unsigned app")
        case .hiddenProgram: String(localized: "Hidden program")
        case .downloadedScript: String(localized: "Downloaded script")
        }
    }

    var explanation: String {
        switch self {
        case .disguisedProgram: String(localized: "Its name says photo or document, but its contents are a program. Real files never do this.")
        case .deceptiveName: String(localized: "The name is built so the real type is easy to miss, a common trick to get you to open it.")
        case .hiddenPayload: String(localized: "Something extra is tucked in after the picture. Viewing the image is harmless; the hidden part can be pulled out by other malware.")
        case .activePDF: String(localized: "Most PDFs never need scripts. Open it only if you trust who sent it.")
        case .unsignedApp: String(localized: "Nobody vouches for who made this app. Keep it only if you know where it came from.")
        case .hiddenProgram: String(localized: "A program with a hidden name in your personal folders, where apps don't normally keep programs.")
        case .downloadedScript: String(localized: "Opening it runs commands in Terminal. Fine if you meant to download it.")
        }
    }

    var symbol: String {
        switch self {
        case .disguisedProgram: "theatermasks"
        case .deceptiveName: "textformat.abc.dottedunderline"
        case .hiddenPayload: "photo"
        case .activePDF: "doc.richtext"
        case .unsignedApp: "app.badge.checkmark"
        case .hiddenProgram: "eye.slash"
        case .downloadedScript: "terminal"
        }
    }
}

extension ThreatSeverity {
    var title: String {
        switch self {
        case .high: String(localized: "Likely harmful")
        case .medium: String(localized: "Suspicious")
        case .low: String(localized: "Worth a look")
        }
    }

    var tint: Color {
        switch self {
        case .high: .hex(0xFF6B7A)
        case .medium: .hex(0xF2A444)
        case .low: .hex(0x9CA8CA)
        }
    }
}
