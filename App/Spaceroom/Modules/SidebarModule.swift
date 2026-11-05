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

    /// Analogous palette: light and cool at the top, dark and warm at the bottom (grainy-gradient skill).
    var palette: ModulePalette {
        switch self {
        //                    cool      top       middle    bottom    floor     accent
        case .smartCare:     .hex(0x8A93EA, 0x6C5CC7, 0x4A2C9E, 0x2A145E, 0x120A2C, 0xB86AE6)
        case .cleanup:       .hex(0x92BFCB, 0x4F9196, 0x22665F, 0x10403A, 0x061F1C, 0x4FCB98)
        case .devCleanup:    .hex(0x93B6EA, 0x4C77C9, 0x24479A, 0x12265E, 0x08122E, 0x4FB2EE)
        case .clutter:       .hex(0xAEB6C4, 0x9A7F78, 0x8A4A33, 0x5A2416, 0x2A0E08, 0xE8804E)
        case .spaceLens:     .hex(0xCB90DB, 0xB5579E, 0x9A3A5C, 0x5E1F2A, 0x290C11, 0xF2A444)
        case .status:        .hex(0x97ADCB, 0x5F7EB0, 0x33508A, 0x1A2A52, 0x0A1227, 0x5AAAF2)
        case .applications:  .hex(0x9EABF2, 0x6070D8, 0x3A3FA8, 0x1E1D62, 0x0C0B2C, 0x7C8CFF)
        case .startup:       .hex(0xC99FC2, 0xA85A88, 0x7E2E5E, 0x4A1636, 0x210818, 0xF06C9C)
        case .performance:   .hex(0xDABC8E, 0xC98A4A, 0xA4512A, 0x5E2414, 0x290D06, 0xF68C3C)
        case .privacy:       .hex(0x93CBD2, 0x4E9AAE, 0x23687E, 0x103C4C, 0x061C25, 0x4CD2DA)
        case .restoreCenter: .hex(0xA7B2C4, 0x6E7A90, 0x4A4E5E, 0x2E2824, 0x14100D, 0x9CA8CA)
        case .automations:   .hex(0xB6AAE8, 0x7F6CC4, 0x503E94, 0x2A1F58, 0x130D2B, 0xAA8EF2)
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
        case .smartCare, .cleanup, .devCleanup, .clutter, .spaceLens, .applications, .restoreCenter: nil

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
        case .clutter:
            [("doc.badge.clock", "Large files you haven't touched in months"),
             ("doc.on.doc", "Duplicates confirmed by content, not just name"),
             ("shippingbox", "Installer downloads you no longer need")]
        default:
            []
        }
    }
}
