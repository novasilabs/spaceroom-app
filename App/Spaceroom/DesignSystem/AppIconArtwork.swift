// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The app icon body: the sidebar's glass Spaceroom glyph at Apple's macOS icon-grid size
/// (824 pt inside a 1024 pt canvas). The Debug icon export (`SPACEROOM_EXPORT_ICON`) renders
/// this and adds the drop shadow with Core Graphics, which keeps clean premultiplied alpha
/// (large SwiftUI shadows rendered offscreen showed coloured fringes).
struct AppIconArtwork: View {
    static let canvas: CGFloat = 1024
    static let bodySize: CGFloat = 824
    static let tint = Color.hex(0x8B6BE8)
    static let symbol = "circle.hexagongrid.fill"

    var body: some View {
        GlassGlyph(symbol: Self.symbol, tint: Self.tint, size: Self.bodySize, isCompact: true)
            .frame(width: Self.bodySize, height: Self.bodySize)
    }
}
