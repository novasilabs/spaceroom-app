// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Chunky translucent "glass candy" object with a symbol inside — Spaceroom's own take on the
/// glossy 3D objects CleanMyMac pairs with each tile. Built from gradients only (no image assets).
struct GlassGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 64
    /// Small sizes (sidebar) drop the depth shadow and glow so they stay crisp.
    var isCompact = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
        ZStack {
            // Body: tint, lighter at the top-left like light passing through glass.
            shape.fill(LinearGradient(colors: [tint.mix(white: 0.45), tint, tint.mix(with: .black, amount: 0.25)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            // Inner glow from below.
            shape.fill(RadialGradient(colors: [tint.mix(white: 0.6).opacity(0.55), .clear],
                                      center: UnitPoint(x: 0.5, y: 1.0), startRadius: 0, endRadius: size * 0.7))
            // Specular highlight, top-left.
            shape.fill(RadialGradient(colors: [.white.opacity(0.65), .white.opacity(0)],
                                      center: UnitPoint(x: 0.28, y: 0.18), startRadius: 0, endRadius: size * 0.45))
            // Rim: bright on top, faint underneath.
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.08)],
                                              startPoint: .top, endPoint: .bottom),
                               lineWidth: max(1, size * 0.025))
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: tint.mix(with: .black, amount: 0.5).opacity(0.5), radius: size * 0.03, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: isCompact ? .black.opacity(0.25) : tint.opacity(0.45),
                radius: isCompact ? 1.5 : size * 0.18, y: isCompact ? 1 : size * 0.10)
        .accessibilityHidden(true)
    }
}
