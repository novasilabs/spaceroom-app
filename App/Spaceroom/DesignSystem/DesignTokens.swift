// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// Every tunable design value in one place.
///
/// Defaults follow Emil Kowalski's design-engineering rules and the better-ui skill:
/// press scale 0.96 over 150 ms ease-out, entrances of opacity + 4 px blur + 12 px rise over
/// 300 ms staggered 100 ms, exits 150 ms, high-frequency switches ≤ 150 ms, icon swaps as a
/// 0.3 s spring with no bounce, concentric radii and a single faint white ring on dark surfaces.
///
/// In Debug builds the Design Tuning panel edits these live (the native take on DialKit);
/// "Copy Values" produces the Swift to paste back here.
@MainActor
@Observable
final class DesignTokens {
    static let shared = DesignTokens()

    // Press feedback
    var pressScale: Double = 0.96
    var pressDuration: Double = 0.15

    // Staged entrances (infrequent moments only: results, done, onboarding)
    var enterDuration: Double = 0.30
    var enterOffset: Double = 12
    var enterBlur: Double = 4
    var stagger: Double = 0.10

    // Exits are shorter and smaller than enters
    var exitDuration: Double = 0.15

    // High-frequency changes (module switch, hover)
    var switchDuration: Double = 0.15
    var hoverDuration: Double = 0.12

    // Icon swaps (checkmarks, states)
    var iconSwapDuration: Double = 0.30

    // Surfaces
    var cardRadius: Double = 20
    var ringOpacity: Double = 0.08
    var ringHoverOpacity: Double = 0.13
    var surfaceTint: Double = 0.07

    // Background
    var grainOpacity: Double = 0
    var blobOpacity: Double = 1
    var patternOpacity: Double = 0

    // Primary circle button
    var primarySize: Double = 92
    var primaryGlow: Double = 0.55

    /// Bumped by the tuning panel's "Replay" action; entrances re-run when it changes.
    var replayToken = 0

    private init() {}

    func reset() {
        let fresh = Defaults()
        pressScale = fresh.pressScale; pressDuration = fresh.pressDuration
        enterDuration = fresh.enterDuration; enterOffset = fresh.enterOffset
        enterBlur = fresh.enterBlur; stagger = fresh.stagger; exitDuration = fresh.exitDuration
        switchDuration = fresh.switchDuration; hoverDuration = fresh.hoverDuration
        iconSwapDuration = fresh.iconSwapDuration
        cardRadius = fresh.cardRadius; ringOpacity = fresh.ringOpacity
        ringHoverOpacity = fresh.ringHoverOpacity; surfaceTint = fresh.surfaceTint
        grainOpacity = fresh.grainOpacity; blobOpacity = fresh.blobOpacity; patternOpacity = fresh.patternOpacity
        primarySize = fresh.primarySize; primaryGlow = fresh.primaryGlow
    }

    /// Plain value copy of the defaults (keeps `reset()` honest without duplicating literals).
    private struct Defaults {
        let pressScale = 0.96, pressDuration = 0.15
        let enterDuration = 0.30, enterOffset = 12.0, enterBlur = 4.0, stagger = 0.10, exitDuration = 0.15
        let switchDuration = 0.15, hoverDuration = 0.12, iconSwapDuration = 0.30
        let cardRadius = 20.0, ringOpacity = 0.08, ringHoverOpacity = 0.13, surfaceTint = 0.07
        let grainOpacity = 0.0, blobOpacity = 1.0, patternOpacity = 0.0
        let primarySize = 92.0, primaryGlow = 0.55
    }

    /// Swift source for the current values, for pasting into this file after tuning.
    var swiftSnippet: String {
        func f(_ v: Double) -> String { String(format: "%.3g", v) }
        return """
        // DesignTokens tuned values
        pressScale = \(f(pressScale)); pressDuration = \(f(pressDuration))
        enterDuration = \(f(enterDuration)); enterOffset = \(f(enterOffset)); enterBlur = \(f(enterBlur)); stagger = \(f(stagger))
        exitDuration = \(f(exitDuration)); switchDuration = \(f(switchDuration)); hoverDuration = \(f(hoverDuration))
        iconSwapDuration = \(f(iconSwapDuration))
        cardRadius = \(f(cardRadius)); ringOpacity = \(f(ringOpacity)); ringHoverOpacity = \(f(ringHoverOpacity)); surfaceTint = \(f(surfaceTint))
        grainOpacity = \(f(grainOpacity)); blobOpacity = \(f(blobOpacity)); patternOpacity = \(f(patternOpacity))
        primarySize = \(f(primarySize)); primaryGlow = \(f(primaryGlow))
        """
    }
}

/// Named curves. Built-in easings are too weak for UI; these are the strong variants.
enum Easing {
    /// Strong ease-out for entering, pressing and responding (Emil Kowalski).
    static func out(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    /// Strong ease-in-out for things moving on screen.
    static func inOut(_ duration: Double) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: duration) }
    /// Icon swap curve without a spring (better-ui).
    static func swap(_ duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
}

@MainActor
enum Motion {
    static var tokens: DesignTokens { .shared }

    /// Phase changes inside a module (scan → results → done): the old screen exits fast.
    static var phaseChange: Animation { Easing.out(tokens.exitDuration) }
    /// Module switches, tab-like changes: high frequency, opacity only.
    static var moduleSwitch: Animation { .easeOut(duration: tokens.switchDuration) }
    static var hover: Animation { .easeOut(duration: tokens.hoverDuration) }
    static var press: Animation { Easing.out(tokens.pressDuration) }
    static var iconSwap: Animation { .spring(duration: tokens.iconSwapDuration, bounce: 0) }
}
