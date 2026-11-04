// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Full-window module background: a diagonal gradient with two soft glows for depth.
struct ModuleBackground: View {
    let module: SidebarModule

    var body: some View {
        let colors = module.gradient
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { proxy in
                let size = proxy.size
                Circle()
                    .fill(colors[0].opacity(0.55))
                    .frame(width: size.width * 0.7)
                    .blur(radius: 120)
                    .offset(x: size.width * 0.45, y: -size.height * 0.25)
                Circle()
                    .fill(colors[1].opacity(0.45))
                    .frame(width: size.width * 0.6)
                    .blur(radius: 140)
                    .offset(x: -size.width * 0.1, y: size.height * 0.55)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Translucent "glass" surface for cards and panels.
    ///
    /// TODO(macOS 26 SDK): adopt Liquid Glass (`.glassEffect`) behind `if #available(macOS 26, *)`
    /// once the project builds with Xcode 26. macOS 14–15 keep this material fallback.
    func glassSurface(cornerRadius: CGFloat = 16, tint: Double = 0.08) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(tint))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
    }
}

enum Typography {
    static func hero(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func bigNumber(_ size: CGFloat = 60) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}
