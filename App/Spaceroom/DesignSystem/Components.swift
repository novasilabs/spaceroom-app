// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The glowing circular primary action ("Scan", "Clean", "Stop") at the bottom of each module.
struct PrimaryCircleButton: View {
    let title: LocalizedStringResource
    var tint: Color = .hex(0x9B6BFF)
    /// 0…1 shows a progress ring; `nil` hides it.
    var progress: Double?
    var isIndeterminate = false
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let tokens = DesignTokens.shared
        let size = tokens.primarySize
        Button(action: action) {
            ZStack {
                // Soft outer glow in the module accent.
                Circle()
                    .fill(tint.opacity(tokens.primaryGlow + (isHovering ? 0.15 : 0)))
                    .blur(radius: size * 0.28)
                    .frame(width: size * 1.25, height: size * 1.25)
                // Track ring.
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 4)
                    .frame(width: size + 18, height: size + 18)
                if let progress {
                    ProgressRing(progress: progress, isIndeterminate: isIndeterminate)
                        .frame(width: size + 18, height: size + 18)
                }
                // Glass body.
                // Darker body than the glyphs so the white label keeps contrast.
                Circle()
                    .fill(LinearGradient(colors: [tint.mix(white: 0.25), tint.mix(with: .black, amount: 0.1),
                                                  tint.mix(with: .black, amount: 0.35)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.38), .clear],
                                                     center: UnitPoint(x: 0.5, y: 0.08),
                                                     startRadius: 0, endRadius: size * 0.55))
                    }
                    .overlay {
                        Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.1)],
                                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                    }
                    .frame(width: size, height: size)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .frame(width: size + 24, height: size + 24)
            .contentShape(Circle())
            .animation(Motion.hover, value: isHovering)
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 && isEnabled }
        .accessibilityLabel(Text(title))
        .keyboardShortcut(.defaultAction)
    }
}

/// Ring around the primary button: determinate progress or a fast spinning arc
/// (a faster spinner reads as a faster app).
struct ProgressRing: View {
    let progress: Double
    let isIndeterminate: Bool

    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: isIndeterminate ? 0.28 : min(1, max(0.02, progress)))
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90 + (spin ? 360 : 0)))
            .animation(Easing.out(0.35), value: progress)
            .onAppear {
                guard isIndeterminate, !reduceMotion else { return }
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

/// Secondary capsule button on dark gradients ("Review Details", "Undo").
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration)
    }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            let fill = pressed ? 0.22 : (isHovering ? 0.17 : 0.11)
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(fill)))
                .overlay(Capsule().strokeBorder(.white.opacity(isHovering ? 0.16 : 0.10)))
                .foregroundStyle(.white)
                .contentShape(Capsule())
                .scaleEffect(pressed && !reduceMotion ? DesignTokens.shared.pressScale : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(Motion.press, value: pressed)
                .animation(Motion.hover, value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

/// Module illustration: a large glass glyph on a soft halo with two faint orbit rings. Static.
struct ModuleHero: View {
    let module: SidebarModule
    var size: CGFloat = 150
    var symbolOverride: String?

    var body: some View {
        let accent = module.palette.accent
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.9))
                .frame(width: size * 1.8, height: size * 1.8)
            ForEach(0..<2, id: \.self) { ring in
                Circle()
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                    .frame(width: size * (1.25 + CGFloat(ring) * 0.35))
            }
            GlassGlyph(symbol: symbolOverride ?? module.symbol, tint: accent, size: size * 0.62)
        }
        .frame(width: size * 1.6, height: size * 1.35)
        .accessibilityHidden(true)
    }
}

/// Small rounded capsule label ("Coming in M1", "In use").
struct Pill: View {
    let text: Text
    var tint: Color = .white

    var body: some View {
        text
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

/// Small module icon used in the sidebar, cards and the Restore Center.
struct ModuleIcon: View {
    let module: SidebarModule
    var size: CGFloat = 22

    var body: some View {
        GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: size, isCompact: size < 30)
    }
}
