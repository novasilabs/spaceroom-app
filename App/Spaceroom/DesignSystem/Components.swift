// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The big circular primary action ("Scan", "Clean", "Stop") at the bottom of each module.
struct PrimaryCircleButton: View {
    let title: LocalizedStringResource
    /// 0…1 shows a progress ring; `nil` hides it.
    var progress: Double?
    var isIndeterminate = false
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    private let size: CGFloat = 116

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.72)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: .white.opacity(isHovering ? 0.45 : 0.25), radius: isHovering ? 26 : 18)
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 6)
                    .padding(-12)
                if let progress {
                    ProgressRing(progress: progress, isIndeterminate: isIndeterminate)
                        .padding(-9)
                }
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.78))
            }
            .frame(width: size, height: size)
            .scaleEffect(isHovering && isEnabled ? 1.04 : 1)
            .animation(.spring(duration: 0.3), value: isHovering)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(title))
        .keyboardShortcut(.defaultAction)
    }
}

/// Ring drawn around the primary button: determinate progress or a spinning arc.
struct ProgressRing: View {
    let progress: Double
    let isIndeterminate: Bool

    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: isIndeterminate ? 0.28 : min(1, max(0.02, progress)))
            .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .rotationEffect(.degrees(-90 + (spin ? 360 : 0)))
            .animation(.easeOut(duration: 0.35), value: progress)
            .onAppear {
                guard isIndeterminate, !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Secondary text button on dark gradients ("Review Details", "Undo").
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.24 : 0.14)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            .foregroundStyle(.white)
            .contentShape(Capsule())
    }
}

/// Large module illustration: layered rings and the module symbol, gently floating.
struct ModuleHero: View {
    let module: SidebarModule
    var size: CGFloat = 200
    var symbolOverride: String?

    @State private var float = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5)
                    .frame(width: size * (0.55 + CGFloat(ring) * 0.22))
            }
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.28), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.42))
                .frame(width: size * 0.9)
            Image(systemName: symbolOverride ?? module.symbol)
                .font(.system(size: size * 0.32, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.35), radius: 16)
                .offset(y: float ? -6 : 6)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .onAppear {
            guard !reduceMotion else { return }
            // A few gentle floats on arrival, then rest: an endless animation keeps the window
            // redrawing (~13 % CPU measured), which a menu bar utility can't afford while idle.
            withAnimation(.easeInOut(duration: 2.6).repeatCount(3, autoreverses: true)) { float = true }
        }
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

/// Square module icon used in the sidebar and cards.
struct ModuleIcon: View {
    let module: SidebarModule
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [module.gradient[0].mix(white: 0.25), module.gradient[1]],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: module.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

extension Color {
    /// Lightens a color by blending it with white (macOS 14 has no `Color.mix`).
    func mix(white amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let r = ns.redComponent + (1 - ns.redComponent) * amount
        let g = ns.greenComponent + (1 - ns.greenComponent) * amount
        let b = ns.blueComponent + (1 - ns.blueComponent) * amount
        return Color(.sRGB, red: r, green: g, blue: b, opacity: ns.alphaComponent)
    }
}
