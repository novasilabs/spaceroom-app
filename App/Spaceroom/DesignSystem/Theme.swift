// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Full-window module background.
struct ModuleBackground: View {
    let module: SidebarModule

    var body: some View {
        GrainyBackground(palette: module.palette, showsPattern: module == .smartCare)
    }
}

extension View {
    /// Translucent surface for cards and panels.
    ///
    /// Dark surfaces get depth from one faint white ring, not from borders or drop shadows
    /// (shadows vanish on dark backgrounds). `wash` adds a colour tint like CleanMyMac's tiles.
    ///
    /// TODO(macOS 26 SDK): adopt Liquid Glass (`.glassEffect`) behind `if #available(macOS 26, *)`
    /// once the project builds with Xcode 26. macOS 14–15 keep this fallback.
    func glassSurface(cornerRadius: CGFloat? = nil, wash: Color? = nil, isHighlighted: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, wash: wash, isHighlighted: isHighlighted))
    }
}

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat?
    var wash: Color?
    var isHighlighted: Bool

    func body(content: Content) -> some View {
        let tokens = DesignTokens.shared
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? tokens.cardRadius, style: .continuous)
        content.background {
            ZStack {
                shape.fill(Color.white.opacity(tokens.surfaceTint + (isHighlighted ? 0.04 : 0)))
                if let wash {
                    shape.fill(LinearGradient(colors: [wash.opacity(0.42), wash.opacity(0.10)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                shape.strokeBorder(Color.white.opacity(isHighlighted ? tokens.ringHoverOpacity : tokens.ringOpacity),
                                   lineWidth: 1)
            }
        }
    }
}

enum Typography {
    static func hero(_ size: CGFloat = 32) -> Font { .system(size: size, weight: .bold) }
    /// Big result numbers: tight, heavy, tabular.
    static func bigNumber(_ size: CGFloat = 60) -> Font { .system(size: size, weight: .bold).monospacedDigit() }
    /// Small label above a number ("Cleanup").
    static let eyebrow = Font.system(size: 12, weight: .semibold)
    static let tileNumber = Font.system(size: 26, weight: .bold).monospacedDigit()
}

extension ShapeStyle where Self == Color {
    static var textSecondary: Color { .white.opacity(0.72) }
    static var textTertiary: Color { .white.opacity(0.5) }
}
