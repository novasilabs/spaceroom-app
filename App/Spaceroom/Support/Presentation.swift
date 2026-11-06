// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

extension Int64 {
    /// "8.4 GB" — Finder-style decimal units; zero reads "0 bytes", not "Zero KB".
    var bytesText: String { formatted(.byteCount(style: .file, spellsOutZero: false)) }
}

/// Display info for a rule group (one card on the results screen).
struct GroupInfo {
    let title: LocalizedStringResource
    let symbol: String
    /// Tile wash and glass-object colour.
    let tint: Color

    static func forGroup(_ id: String) -> GroupInfo {
        switch id {
        case "caches": GroupInfo(title: "App caches", symbol: "shippingbox", tint: .hex(0x3FC29A))
        case "logs": GroupInfo(title: "Logs & crash reports", symbol: "doc.text.magnifyingglass", tint: .hex(0x6E92DA))
        case "browsers": GroupInfo(title: "Browser caches", symbol: "globe", tint: .hex(0x4FA9EA))
        case "trash": GroupInfo(title: "Trash", symbol: "trash", tint: .hex(0x9A86E0))
        case "mail": GroupInfo(title: "Mail attachments", symbol: "paperclip", tint: .hex(0x4F9BF0))
        case "preferences": GroupInfo(title: "Broken preferences", symbol: "gearshape.2", tint: .hex(0xA98BE6))
        case "photos": GroupInfo(title: "Photos caches", symbol: "photo.on.rectangle", tint: .hex(0xF0A04B))
        case "xcode": GroupInfo(title: "Xcode & Simulators", symbol: "hammer", tint: .hex(0x4F8CF0))
        case "packages": GroupInfo(title: "Package managers", symbol: "shippingbox.and.arrow.backward", tint: .hex(0xE6A246))
        case "projects": GroupInfo(title: "Project build folders", symbol: "folder.badge.gearshape", tint: .hex(0x5CC6D6))
        case "smartCare.systemJunk": GroupInfo(title: "System Junk", symbol: "bubbles.and.sparkles", tint: .hex(0x3FC79A))
        case "smartCare.developerJunk": GroupInfo(title: "Developer Junk", symbol: "hammer", tint: .hex(0x4F8CF0))
        case "smartCare.trash": GroupInfo(title: "Trash", symbol: "trash", tint: .hex(0x9A86E0))
        default: GroupInfo(title: LocalizedStringResource(stringLiteral: id.capitalized), symbol: "folder", tint: .hex(0x8A93EA))
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
        case .ignored: String(localized: "Ignored")
        case .trackedByGit(let verified):
            verified ? String(localized: "Committed to Git") : String(localized: "In a Git repository (Git isn't installed to check)")
        case .running(let name): String(localized: "\(name) is running. Quit it first.")
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
        case .ignored: "eye.slash"
        case .trackedByGit: "arrow.triangle.branch"
        case .running: "play.circle"
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
