// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// One drawn ring segment.
struct SunburstSegment: Identifiable {
    var id: String { node.id }
    let node: DiskNode
    /// 1 = innermost ring.
    let depth: Int
    let start: Double  // radians, 0 = 12 o'clock, clockwise
    let end: Double
    /// Index of the top-level slice it belongs to (drives its hue).
    let family: Int
}

enum SunburstLayout {
    static let rings = 3
    /// Segments narrower than this are skipped (they'd be sub-pixel).
    static let minimumSpan = 0.006

    static func segments(for node: DiskNode) -> [SunburstSegment] {
        var result: [SunburstSegment] = []
        guard node.size > 0 else { return result }
        func place(_ parent: DiskNode, depth: Int, start: Double, span: Double, family: Int?) {
            guard depth <= rings, parent.size > 0 else { return }
            var angle = start
            for (index, child) in parent.children.enumerated() {
                let childSpan = span * Double(child.size) / Double(parent.size)
                defer { angle += childSpan }
                guard childSpan >= minimumSpan else { continue }
                let fam = family ?? index
                result.append(SunburstSegment(node: child, depth: depth, start: angle, end: angle + childSpan, family: fam))
                if child.kind == .folder { place(child, depth: depth + 1, start: angle, span: childSpan, family: fam) }
            }
        }
        place(node, depth: 1, start: 0, span: 2 * .pi, family: nil)
        return result
    }
}

/// Interactive sunburst of one folder: hover highlights, click drills in, click centre goes up.
/// Hover is high-frequency, so it responds instantly; drilling (occasional, spatial) cross-fades.
/// Keeps the last computed layout so hover (which re-renders on every mouse move) doesn't redo it.
final class SunburstLayoutCache {
    private var key: DiskNode?
    private var cached: [SunburstSegment] = []

    func segments(for node: DiskNode) -> [SunburstSegment] {
        if key != node {
            key = node
            cached = SunburstLayout.segments(for: node)
        }
        return cached
    }
}

struct SunburstChart: View {
    let node: DiskNode
    /// Shown in the centre instead of the folder's own name (e.g. "Home Folder" at the root).
    var title: String?
    let canGoUp: Bool
    @Binding var hoveredID: String?
    let onDrill: (DiskNode) -> Void
    let onUp: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var layout = SunburstLayoutCache()

    static let palette: [Color] = [
        .hex(0xF2708C), .hex(0xF29A4A), .hex(0xF2C94C), .hex(0xD96BD9),
        .hex(0xA678F0), .hex(0xF07A5A), .hex(0xE5A63F), .hex(0xC45BA8),
    ]

    var body: some View {
        let segments = layout.segments(for: node)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = RingGeometry(side: side)
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let dimOthers = hoveredID != nil
                    for segment in segments {
                        let path = geometry.path(for: segment, center: center)
                        let isHovered = segment.id == hoveredID
                        context.fill(path, with: .color(color(for: segment, hovered: isHovered, dim: dimOthers && !isHovered)))
                        context.stroke(path, with: .color(.black.opacity(0.28)), lineWidth: 1)
                    }
                }
                centerLabel(segments: segments)
                    .frame(width: geometry.innerRadius * 1.7)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle().inset(by: (min(proxy.size.width, proxy.size.height) - side) / 2))
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let hit = geometry.hit(point, in: proxy.size, segments: segments)
                    if hoveredID != hit?.id { hoveredID = hit?.id }
                case .ended:
                    if hoveredID != nil { hoveredID = nil }
                }
            }
            .onTapGesture(coordinateSpace: .local) { point in
                if geometry.isInCenter(point, in: proxy.size) {
                    if canGoUp { onUp() }
                } else if let hit = geometry.hit(point, in: proxy.size, segments: segments) {
                    onDrill(hit.node)
                }
            }
        }
        .id(node.id)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(node.name.isEmpty ? "Folder" : node.name), \(node.size.bytesText)"))
        .accessibilityHint(Text("Use the list beside the chart to explore folders."))
    }

    private func color(for segment: SunburstSegment, hovered: Bool, dim: Bool) -> Color {
        if case .other = segment.node.kind { return .white.opacity(dim ? 0.10 : (hovered ? 0.35 : 0.18)) }
        let base = Self.palette[segment.family % Self.palette.count]
        let tone = base.mix(white: 0.14 * Double(segment.depth - 1))
        if hovered { return tone.mix(white: 0.25) }
        return dim ? tone.opacity(0.45) : tone.opacity(segment.node.kind == .folder ? 0.95 : 0.8)
    }

    @ViewBuilder
    private func centerLabel(segments: [SunburstSegment]) -> some View {
        let hovered = segments.first { $0.id == hoveredID }?.node
        let shown = hovered ?? node
        VStack(spacing: 4) {
            Text(hovered == nil ? (title ?? SpaceLensFormat.name(of: node)) : SpaceLensFormat.name(of: shown))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(shown.size.bytesText)
                .font(.system(size: 24, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if hovered == nil, canGoUp {
                Label("Back", systemImage: "arrow.up.left").font(.caption).foregroundStyle(.textSecondary)
            } else if hovered != nil, node.size > 0 {
                Text("\(Int((Double(shown.size) / Double(node.size) * 100).rounded()))% of this folder")
                    .font(.caption).foregroundStyle(.textSecondary)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Ring radii and polar hit-testing.
struct RingGeometry {
    let side: CGFloat
    var outerRadius: CGFloat { side / 2 - 4 }
    var innerRadius: CGFloat { outerRadius * 0.34 }
    var ringWidth: CGFloat { (outerRadius - innerRadius) / CGFloat(SunburstLayout.rings) }

    func radii(depth: Int) -> (inner: CGFloat, outer: CGFloat) {
        let inner = innerRadius + ringWidth * CGFloat(depth - 1)
        return (inner + 1, inner + ringWidth - 1)
    }

    func path(for segment: SunburstSegment, center: CGPoint) -> Path {
        let (inner, outer) = radii(depth: segment.depth)
        // 0 rad = 12 o'clock, clockwise → SwiftUI angle = θ − 90°.
        let start = Angle(radians: segment.start - .pi / 2)
        let end = Angle(radians: segment.end - .pi / 2)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    private func polar(_ point: CGPoint, in size: CGSize) -> (radius: CGFloat, angle: Double) {
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        var angle = atan2(Double(dx), Double(-dy)) // 0 at 12 o'clock, clockwise
        if angle < 0 { angle += 2 * .pi }
        return (sqrt(dx * dx + dy * dy), angle)
    }

    func isInCenter(_ point: CGPoint, in size: CGSize) -> Bool {
        polar(point, in: size).radius < innerRadius
    }

    func hit(_ point: CGPoint, in size: CGSize, segments: [SunburstSegment]) -> SunburstSegment? {
        let (radius, angle) = polar(point, in: size)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        let depth = Int((radius - innerRadius) / ringWidth) + 1
        return segments.first { $0.depth == depth && angle >= $0.start && angle < $0.end }
    }
}

enum SpaceLensFormat {
    static func name(of node: DiskNode) -> String {
        if case .other(let count) = node.kind {
            return String(localized: "\(count.formatted()) smaller items")
        }
        return node.name
    }

    static func symbol(for node: DiskNode) -> String {
        switch node.kind {
        case .folder: node.isPartial ? "folder.badge.questionmark" : "folder.fill"
        case .package: "app.fill"
        case .file: "doc.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}
