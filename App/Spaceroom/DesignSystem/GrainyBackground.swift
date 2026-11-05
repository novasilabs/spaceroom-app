// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Analogous palette for one module: light and cool at the top, dark and warm at the bottom.
struct ModulePalette {
    /// Cool tone for the top corners.
    let cool: Color
    let top: Color
    let middle: Color
    let bottom: Color
    /// Near-black floor for the bottom 15–20 %.
    let floor: Color
    /// Brightest accent, placed at mid-height on a side edge. Also tints buttons and glyphs.
    let accent: Color

    static func hex(_ cool: UInt32, _ top: UInt32, _ middle: UInt32, _ bottom: UInt32, _ floor: UInt32, _ accent: UInt32) -> ModulePalette {
        ModulePalette(cool: .hex(cool), top: .hex(top), middle: .hex(middle), bottom: .hex(bottom),
                      floor: .hex(floor), accent: .hex(accent))
    }
}

/// Soft premium background (grainy-gradient skill): a multi-stop base gradient, four large
/// radial blobs at corners and edges, a 1-physical-pixel grain layer, and an optional faint
/// contour pattern masked away from the centre. Fully static — no drift — so it costs nothing at rest.
struct GrainyBackground: View {
    let palette: ModulePalette
    var showsPattern = false

    var body: some View {
        let tokens = DesignTokens.shared
        GeometryReader { proxy in
            let size = proxy.size
            let span = max(size.width, size.height)
            ZStack {
                // 1. Base: several stops, dark floor at the bottom.
                LinearGradient(stops: [
                    .init(color: palette.top, location: 0),
                    .init(color: palette.top.mix(with: palette.middle, amount: 0.5), location: 0.30),
                    .init(color: palette.middle, location: 0.55),
                    .init(color: palette.bottom, location: 0.78),
                    .init(color: palette.floor, location: 1),
                ], startPoint: .top, endPoint: .bottom)

                // 2. Blobs, each at the height of its colour band, fading over several stops.
                Group {
                    blob(palette.cool, center: UnitPoint(x: 0.05, y: 0.0), radius: span * 0.55)
                    blob(palette.cool.mix(with: palette.top, amount: 0.5), center: UnitPoint(x: 0.95, y: 0.05), radius: span * 0.5)
                    blob(palette.accent, center: UnitPoint(x: 1.0, y: 0.48), radius: span * 0.48)
                    blob(palette.floor, center: UnitPoint(x: 0.35, y: 1.15), radius: span * 0.6)
                }
                .opacity(tokens.blobOpacity)

                // 3. Optional pattern: thin concentric contours, clear in the middle.
                if showsPattern {
                    ContourPattern()
                        .stroke(.white, lineWidth: 0.8)
                        .opacity(tokens.patternOpacity)
                        .mask(RadialGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black, location: 1)],
                                             center: .center, startRadius: 0, endRadius: span * 0.55))
                }

                // 4. Grain over everything; overlay makes it vanish in dark areas.
                GrainLayer()
                    .opacity(tokens.grainOpacity)
                    .blendMode(.overlay)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(stops: [
            .init(color: color.opacity(0.85), location: 0),
            .init(color: color.opacity(0.45), location: 0.35),
            .init(color: color.opacity(0.12), location: 0.7),
            .init(color: color.opacity(0), location: 1),
        ], center: center, startRadius: 0, endRadius: radius)
    }
}

/// Concentric contour lines centred low in the frame, like topographic rings.
struct ContourPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.08)
        let maxRadius = hypot(rect.width, rect.height) * 0.75
        var radius: CGFloat = 60
        while radius < maxRadius {
            path.addEllipse(in: CGRect(x: center.x - radius * 1.15, y: center.y - radius,
                                       width: radius * 2.3, height: radius * 2))
            radius += 34
        }
        return path
    }
}

/// Tiled grey noise where one noise pixel is one physical pixel.
struct GrainLayer: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(nsImage: GrainTile.image(scale: displayScale))
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
    }
}

@MainActor
enum GrainTile {
    private static var cache: [CGFloat: NSImage] = [:]

    /// 128 × 128 px tile of greys in 128 ± 70 (full range speckles saturated colours).
    static func image(scale: CGFloat) -> NSImage {
        if let cached = cache[scale] { return cached }
        let pixels = 128
        var bytes = [UInt8](repeating: 0, count: pixels * pixels)
        var generator = SplitMix64(seed: 0x5EED_5A1C)
        for index in bytes.indices {
            bytes[index] = UInt8(58 + Int(generator.next() % 141)) // 58…198 ≈ 128 ± 70
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 8,
                              bytesPerRow: pixels, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let points = CGFloat(pixels) / max(scale, 1)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: points, height: points))
        cache[scale] = image
        return image
    }
}

/// Small deterministic PRNG so the grain is identical on every launch.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Color {
    /// Linear blend in sRGB (macOS 14 has no `Color.mix`).
    func mix(with other: Color, amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * amount }
        return Color(.sRGB, red: lerp(a.redComponent, b.redComponent), green: lerp(a.greenComponent, b.greenComponent),
                     blue: lerp(a.blueComponent, b.blueComponent), opacity: lerp(a.alphaComponent, b.alphaComponent))
    }

    func mix(white amount: Double) -> Color { mix(with: .white, amount: amount) }

    static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: opacity)
    }
}
