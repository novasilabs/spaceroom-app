// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// MARK: - Staged entrance

/// One chunk of a staged entrance: opacity + blur + rise, delayed by its position.
/// Use only for infrequent moments (results, done, onboarding) — never for routine switches.
/// Under Reduce Motion it becomes a plain opacity fade.
struct Entrance: ViewModifier {
    let index: Int
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let tokens = DesignTokens.shared
        let moves = !reduceMotion
        content
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible || !moves ? 0 : tokens.enterBlur)
            .offset(y: isVisible || !moves ? 0 : tokens.enterOffset)
            .onAppear(perform: play)
            .onChange(of: tokens.replayToken) {
                isVisible = false
                DispatchQueue.main.async { play() }
            }
    }

    private func play() {
        let tokens = DesignTokens.shared
        withAnimation(Easing.out(tokens.enterDuration).delay(Double(index) * tokens.stagger)) {
            isVisible = true
        }
    }
}

extension View {
    /// Marks this view as chunk `index` of a staged entrance (0 = first).
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

// MARK: - Exit

/// Removal half of a phase change: fade, 4 px blur, small rise. Insertion is handled by `entrance`.
struct ExitEffect: ViewModifier {
    let progress: Double // 0 = visible, 1 = gone
    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .blur(radius: 4 * progress)
            .offset(y: -12 * progress)
    }
}

extension AnyTransition {
    /// Old screen leaves quickly; the new screen's own entrance does the arriving.
    static var phaseSwap: AnyTransition {
        .asymmetric(insertion: .identity,
                    removal: .modifier(active: ExitEffect(progress: 1), identity: ExitEffect(progress: 0)))
    }
}

// MARK: - Press

/// Pressed controls scale to 0.96 over 150 ms ease-out. Disabled controls never scale,
/// and Reduce Motion keeps only a brightness cue.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .scaleEffect(pressed && !reduceMotion ? DesignTokens.shared.pressScale : 1)
                .brightness(pressed && reduceMotion ? -0.06 : 0)
                .animation(Motion.press, value: pressed)
        }
    }
}

// MARK: - Icon swap

/// Cross-fades two icons on an infrequent state change: scale 0.25 → 1, opacity, 4 px blur,
/// spring 0.3 s with no bounce. Reduce Motion keeps the opacity cross-fade only.
struct IconSwap: View {
    let isOn: Bool
    let on: String
    let off: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            glyph(off, visible: !isOn)
            glyph(on, visible: isOn)
        }
        .animation(Motion.iconSwap, value: isOn)
    }

    private func glyph(_ name: String, visible: Bool) -> some View {
        Image(systemName: name)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.25)
            .blur(radius: visible || reduceMotion ? 0 : 4)
            .accessibilityHidden(!visible)
    }
}
