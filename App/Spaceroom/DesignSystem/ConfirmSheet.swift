// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Spaceroom-styled confirmation modal (same language as onboarding): grainy gradient, a glass
/// object on a halo, a details card and clear buttons.
///
/// Destructive confirmations have no default button, so Return can't delete by accident;
/// Escape cancels.
struct ConfirmSheet: View {
    struct Detail: Identifiable {
        let id = UUID()
        let symbol: String
        let text: String
    }

    let symbol: String
    let title: String
    let message: String
    var details: [Detail] = []
    let confirmTitle: String
    var isDestructive = true
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var tint: Color { isDestructive ? .hex(0xFF5A6E) : .hex(0x8B6BE8) }

    var body: some View {
        ZStack {
            GrainyBackground(palette: isDestructive ? .danger : SidebarModule.smartCare.palette)
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(0.5), .clear], center: .center,
                                             startRadius: 0, endRadius: 110))
                        .frame(width: 220, height: 220)
                    Circle()
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                        .frame(width: 150)
                    GlassGlyph(symbol: symbol, tint: tint, size: 76)
                }
                .frame(height: 170)
                .entrance(0)

                Text(title)
                    .font(Typography.hero(24))
                    .multilineTextAlignment(.center)
                    .entrance(1)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
                    .padding(.top, 8)
                    .entrance(1)

                if !details.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(details) { detail in
                            HStack(spacing: 12) {
                                Image(systemName: detail.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(.white.opacity(0.14)))
                                Text(detail.text).font(.callout)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 380)
                    .glassSurface(cornerRadius: 20)
                    .padding(.top, 20)
                    .entrance(2)
                }

                Spacer(minLength: 20)
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GhostButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(action: onConfirm) {
                        Text(confirmTitle)
                    }
                    .buttonStyle(FilledButtonStyle(tint: tint))
                }
                .entrance(3)
            }
            .padding(32)
        }
        .frame(width: 480, height: details.isEmpty ? 420 : 520)
        .preferredColorScheme(.dark)
    }
}

/// Filled glass capsule for a sheet's main action (red for destructive).
struct FilledButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        FilledBody(configuration: configuration, tint: tint)
    }

    private struct FilledBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(LinearGradient(colors: [tint.mix(white: isHovering ? 0.28 : 0.18),
                                                      tint.mix(with: .black, amount: 0.15)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                                                       startPoint: .top, endPoint: .bottom)))
                        .shadow(color: tint.opacity(isHovering ? 0.55 : 0.35), radius: isHovering ? 12 : 8, y: 3)
                }
                .contentShape(Capsule())
                .scaleEffect(pressed && !reduceMotion ? DesignTokens.shared.pressScale : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(Motion.press, value: pressed)
                .animation(Motion.hover, value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

extension ModulePalette {
    /// Rose-to-plum palette for destructive confirmations.
    static let danger = ModulePalette.hex(0xC9A0B4, 0x8E4A60, 0x5E2238, 0x34101E, 0x17070D, 0xFF5A6E)
}
