// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

extension Int64 {
    /// "8.4 GB" — Finder-style decimal units.
    var bytesText: String { formatted(.byteCount(style: .file)) }
}

/// Display info for a rule group (one card on the results screen).
struct GroupInfo {
    let title: LocalizedStringResource
    let symbol: String

    static func forGroup(_ id: String) -> GroupInfo {
        switch id {
        case "caches": GroupInfo(title: "App caches", symbol: "shippingbox")
        case "logs": GroupInfo(title: "Logs & crash reports", symbol: "doc.text.magnifyingglass")
        case "browsers": GroupInfo(title: "Browser caches", symbol: "globe")
        case "trash": GroupInfo(title: "Trash", symbol: "trash")
        case "xcode": GroupInfo(title: "Xcode & Simulators", symbol: "hammer")
        case "packages": GroupInfo(title: "Package managers", symbol: "shippingbox.and.arrow.backward")
        default: GroupInfo(title: LocalizedStringResource(stringLiteral: id.capitalized), symbol: "folder")
        }
    }
}

enum AppNames {
    /// "Xcode" for "com.apple.dt.Xcode"; falls back to the bundle ID.
    @MainActor
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @MainActor
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Display names, executable names and last bundle-ID components of running apps.
    @MainActor
    static func runningAppNames() -> Set<String> {
        var names: Set<String> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            if let name = app.localizedName { names.insert(name) }
            if let exe = app.executableURL?.lastPathComponent { names.insert(exe) }
            if let last = app.bundleIdentifier?.split(separator: ".").last, last.count > 3 { names.insert(String(last)) }
        }
        return names
    }
}

extension SkipReason {
    @MainActor
    var text: String {
        switch self {
        case .inUse(let bundleID): String(localized: "In use by \(AppNames.name(for: bundleID))")
        case .tooRecent(let days): String(localized: "Used in the last \(days) days")
        case .outsideRoot, .protectedPath: String(localized: "Protected location")
        case .changedSinceScan: String(localized: "Changed since the scan")
        case .missing: String(localized: "No longer exists")
        case .notPermitted: String(localized: "Needs Full Disk Access")
        case .moveFailed(let message): message
        }
    }

    var symbol: String {
        switch self {
        case .inUse: "app.badge.checkmark"
        case .tooRecent: "clock"
        case .outsideRoot, .protectedPath: "lock.shield"
        case .changedSinceScan: "arrow.triangle.2.circlepath"
        case .missing: "questionmark.folder"
        case .notPermitted: "lock"
        case .moveFailed: "exclamationmark.triangle"
        }
    }
}

enum Finder {
    @MainActor
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension String {
    /// `/Users/me/Library/Caches` → `~/Library/Caches`
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
