// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// One drawn treemap tile.
struct TreemapTile: Identifiable {
    var id: String { node.id }
    let node: DiskNode
    let rect: CGRect
    /// 1 = a child of the folder on screen, 2 = a grandchild drawn inside it.
    let depth: Int
    let family: Int
}

enum TreemapChartLayout {
    static let gap: CGFloat = 2
    static let header: CGFloat = 20

    static func tiles(for node: DiskNode, in bounds: CGRect) -> [TreemapTile] {
        var result: [TreemapTile] = []
        let children = node.children.filter { $0.size > 0 }
        let rects = Treemap.squarify(children.map { Double($0.size) }, in: bounds)
        for (index, (child, rect)) in zip(children, rects).enumerated() {
            let tile = rect.insetBy(dx: gap / 2, dy: gap / 2)
            guard tile.width >= 2, tile.height >= 2 else { continue }
            result.append(TreemapTile(node: child, rect: tile, depth: 1, family: index))
            // Room for a label and a second level inside big folders.
            guard child.isContainer, tile.width > 90, tile.height > 70 else { continue }
            let inner = CGRect(x: tile.minX + 3, y: tile.minY + header, width: tile.width - 6, height: tile.height - header - 3)
            let grandchildren = child.children.filter { $0.size > 0 }
            let innerRects = Treemap.squarify(grandchildren.map { Double($0.size) }, in: inner)
            for (grandchild, innerRect) in zip(grandchildren, innerRects) {
                let small = innerRect.insetBy(dx: 1, dy: 1)
                guard small.width >= 3, small.height >= 3 else { continue }
                result.append(TreemapTile(node: grandchild, rect: small, depth: 2, family: index))
            }
        }
        return result
    }
}

/// Caches the layout for the current folder and size, so hover doesn't redo it.
final class TreemapLayoutCache {
    private var key: (DiskNode, CGSize)?
    private var cached: [TreemapTile] = []

    func tiles(for node: DiskNode, size: CGSize) -> [TreemapTile] {
        if key?.0 != node || key?.1 != size {
            key = (node, size)
            cached = TreemapChartLayout.tiles(for: node, in: CGRect(origin: .zero, size: size))
        }
        return cached
    }
}

/// Treemap of one folder: hover highlights, click opens a folder. The same colours as the
/// sunburst, so switching between the two keeps every folder recognisable.
struct TreemapChart: View {
    let node: DiskNode
    var selectedPaths: Set<String> = []
    @Binding var hoveredID: String?
    let onDrill: (DiskNode) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var layout = TreemapLayoutCache()

    var body: some View {
        GeometryReader { proxy in
            let tiles = layout.tiles(for: node, size: proxy.size)
            ZStack(alignment: .bottomLeading) {
                Canvas { context, _ in
                    let dim = hoveredID != nil
                    for tile in tiles {
                        let isHovered = tile.id == hoveredID
                        let shape = Path(roundedRect: tile.rect, cornerRadius: tile.depth == 1 ? 8 : 4, style: .continuous)
                        context.fill(shape, with: .color(color(for: tile, hovered: isHovered, dim: dim && !isHovered)))
                        if SpaceLensSelection.isMarked(tile.node, in: selectedPaths) {
                            context.stroke(shape, with: .color(.white.opacity(0.95)), lineWidth: 2)
                        } else {
                            context.stroke(shape, with: .color(.black.opacity(tile.depth == 1 ? 0.22 : 0.18)), lineWidth: 1)
                        }
                        let fits = tile.depth == 1 ? tile.rect.width > 64 && tile.rect.height > 18
                                                   : tile.rect.width > 70 && tile.rect.height > 30
                        guard fits else { continue }
                        let size: CGFloat = tile.depth == 1 ? 11 : 10
                        let label = Text(SpaceLensFormat.name(of: tile.node)).font(.system(size: size, weight: .semibold))
                            + Text("  " + tile.node.size.bytesText).font(.system(size: size - 1, weight: .medium))
                        context.draw(
                            context.resolve(label.foregroundStyle(.white.opacity(tile.depth == 1 ? 1 : 0.85))),
                            in: CGRect(x: tile.rect.minX + 6, y: tile.rect.minY + 4, width: tile.rect.width - 12, height: 14))
                    }
                }
                if let hovered = tiles.first(where: { $0.id == hoveredID })?.node {
                    HoverCaption(node: hovered, parentSize: node.size)
                        .padding(10)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let hit = Self.hit(point, in: tiles)
                    if hoveredID != hit?.id { hoveredID = hit?.id }
                case .ended:
                    if hoveredID != nil { hoveredID = nil }
                }
            }
            .onTapGesture(coordinateSpace: .local) { point in
                if let hit = Self.hit(point, in: tiles) { onDrill(hit.node) }
            }
        }
        .id(node.id)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(node.name.isEmpty ? "Folder" : node.name), \(node.size.bytesText)"))
        .accessibilityHint(Text("Use the list beside the chart to explore folders."))
    }

    /// The deepest tile under the point.
    static func hit(_ point: CGPoint, in tiles: [TreemapTile]) -> TreemapTile? {
        tiles.last { $0.rect.contains(point) }
    }

    private func color(for tile: TreemapTile, hovered: Bool, dim: Bool) -> Color {
        if case .other = tile.node.kind { return .white.opacity(dim ? 0.08 : (hovered ? 0.3 : 0.15)) }
        let base = SunburstChart.palette[tile.family % SunburstChart.palette.count]
        let tone = tile.depth == 1 ? base : base.mix(white: 0.22)
        if hovered { return tone.mix(white: 0.25) }
        return dim ? tone.opacity(0.45) : tone.opacity(tile.depth == 1 ? 0.9 : 0.75)
    }

    private struct HoverCaption: View {
        let node: DiskNode
        let parentSize: Int64
        var body: some View {
            HStack(spacing: 8) {
                Text(SpaceLensFormat.name(of: node)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(node.size.bytesText).font(.system(size: 12, weight: .bold)).monospacedDigit()
                if parentSize > 0 {
                    Text("\(Int((Double(node.size) / Double(parentSize) * 100).rounded()))% of this folder")
                        .font(.caption).foregroundStyle(.textSecondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassSurface(cornerRadius: 12)
            .allowsHitTesting(false)
        }
    }
}

enum SpaceLensSelection {
    /// Ticked itself, or inside a ticked folder.
    static func isMarked(_ node: DiskNode, in selected: Set<String>) -> Bool {
        guard !selected.isEmpty, !node.isAggregate else { return false }
        if selected.contains(node.path) { return true }
        return selected.contains { node.path.hasPrefix($0 + "/") }
    }
}
