// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// Every entry in the sidebar. The order of `allCases` is the order on screen.
enum SidebarModule: String, CaseIterable, Identifiable, Hashable {
    case smartCare
    case cleanup, devCleanup, clutter
    case spaceLens, status
    case applications, startup, performance, privacy
    case restoreCenter, automations

    var id: String { rawValue }

    enum Section: CaseIterable {
        case top, clean, understand, manage, footer

        var title: LocalizedStringResource? {
            switch self {
            case .top, .footer: nil
            case .clean: "Clean"
            case .understand: "Understand"
            case .manage: "Manage"
            }
        }
    }

    var section: Section {
        switch self {
        case .smartCare: .top
        case .cleanup, .devCleanup, .clutter: .clean
        case .spaceLens, .status: .understand
        case .applications, .startup, .performance, .privacy: .manage
        case .restoreCenter, .automations: .footer
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .devCleanup: "Dev Cleanup"
        case .clutter: "My Clutter"
        case .spaceLens: "Space Lens"
        case .status: "System Status"
        case .applications: "Applications"
        case .startup: "Startup & Background"
        case .performance: "Performance"
        case .privacy: "Privacy"
        case .restoreCenter: "Restore Center"
        case .automations: "Automations"
        }
    }

    var tagline: LocalizedStringResource {
        switch self {
        case .smartCare: "One click to a healthier Mac."
        case .cleanup: "Remove system junk, caches, logs and Trash — safely."
        case .devCleanup: "Reclaim the gigabytes your dev tools leave behind."
        case .clutter: "Find large, old and duplicate files you forgot about."
        case .spaceLens: "See what's taking up your disk, at a glance."
        case .status: "Live CPU, memory, disk, network and battery."
        case .applications: "Uninstall apps completely, leftovers included."
        case .startup: "See and control everything that runs in the background."
        case .performance: "Run maintenance tasks that keep macOS snappy."
        case .privacy: "Clear browsing traces and review app permissions."
        case .restoreCenter: "Everything Spaceroom removed, ready to restore."
        case .automations: "Keep your Mac tidy on a schedule."
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "sparkles"
        case .cleanup: "bubbles.and.sparkles"
        case .devCleanup: "hammer"
        case .clutter: "doc.on.doc"
        case .spaceLens: "circle.hexagongrid"
        case .status: "gauge.with.dots.needle.67percent"
        case .applications: "square.grid.2x2"
        case .startup: "power"
        case .performance: "bolt"
        case .privacy: "hand.raised"
        case .restoreCenter: "arrow.uturn.backward.circle"
        case .automations: "clock.arrow.2.circlepath"
        }
    }

    /// Background gradient stops (top-leading → bottom-trailing).
    var gradient: [Color] {
        switch self {
        case .smartCare: [.hex(0x6B2FA0), .hex(0x35168A), .hex(0x0E1D57)]
        case .cleanup: [.hex(0x137A55), .hex(0x0C6772), .hex(0x07303F)]
        case .devCleanup: [.hex(0x3A3FB0), .hex(0x1F5FA8), .hex(0x0A3346)]
        case .clutter: [.hex(0xA0521A), .hex(0x7A2E2A), .hex(0x2E1220)]
        case .spaceLens: [.hex(0xB0396A), .hex(0xC0582A), .hex(0x3B1530)]
        case .status: [.hex(0x1556B8), .hex(0x123A80), .hex(0x0A1A3A)]
        case .applications: [.hex(0x3D4FD0), .hex(0x2A2C8A), .hex(0x14143F)]
        case .startup: [.hex(0x9A2650), .hex(0x5A1840), .hex(0x22091C)]
        case .performance: [.hex(0xC0661A), .hex(0x8A3412), .hex(0x2E1208)]
        case .privacy: [.hex(0x13819A), .hex(0x0E5470), .hex(0x07233A)]
        case .restoreCenter: [.hex(0x4D5A75), .hex(0x2E3650), .hex(0x141826)]
        case .automations: [.hex(0x6A4FA8), .hex(0x3E2D70), .hex(0x181230)]
        }
    }

    /// The scan flow behind this entry, if it is a working scan flow in this build.
    var flowKind: FlowKind? {
        switch self {
        case .smartCare: .smartCare
        case .cleanup: .module(.cleanup)
        case .devCleanup: .module(.devCleanup)
        default: nil
        }
    }

    /// Milestone that delivers a module not built yet (PRD §11).
    var plannedMilestone: LocalizedStringResource? {
        switch self {
        case .smartCare, .cleanup, .devCleanup, .restoreCenter: nil
        case .clutter, .spaceLens, .applications: "Coming in M1"
        case .status, .startup, .performance, .privacy: "Coming in v0.5"
        case .automations: "Coming in v1.0"
        }
    }

    var isAvailable: Bool { plannedMilestone == nil }

    /// Three short promises shown on the intro screen.
    var highlights: [(symbol: String, text: LocalizedStringResource)] {
        switch self {
        case .cleanup:
            [("checkmark.shield", "Only regenerable data — never your documents"),
             ("eye", "Review every item before it's removed"),
             ("arrow.uturn.backward", "Undo anything from the Restore Center")]
        case .devCleanup:
            [("hammer", "Xcode DerivedData, simulators, DeviceSupport"),
             ("shippingbox", "Homebrew, npm, Yarn, pip, Cargo, Go, Gradle caches"),
             ("pause.circle", "Skips tools that are running right now")]
        case .smartCare:
            [("sparkles", "System junk, developer junk and Trash in one scan"),
             ("hand.thumbsup", "Only safe, regenerable data — never documents or projects"),
             ("arrow.uturn.backward", "One Undo brings everything back")]
        default:
            []
        }
    }
}

extension Color {
    static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: opacity)
    }
}
