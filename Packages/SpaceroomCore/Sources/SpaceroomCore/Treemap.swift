// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing & van Wijk): rectangles whose areas match the
/// values, kept as close to square as possible so small items stay readable.
public enum Treemap {
    /// Rectangles for `values` (largest first works best) filling `rect`, in the same order.
    /// Zero and negative values get an empty rectangle.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let indices = values.indices.filter { values[$0] > 0 }
        let areas = Dictionary(uniqueKeysWithValues: indices.map { ($0, values[$0] * scale) })
        var remaining = rect
        var position = 0

        func worst(_ row: [Int], side: Double) -> Double {
            let sum = row.reduce(0) { $0 + areas[$1]! }
            guard let largest = row.map({ areas[$0]! }).max(), let smallest = row.map({ areas[$0]! }).min(),
                  sum > 0, smallest > 0, side > 0 else { return .infinity }
            return max(side * side * largest / (sum * sum), (sum * sum) / (side * side * smallest))
        }

        while position < indices.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [indices[position]]
            var next = position + 1
            while next < indices.count, worst(row + [indices[next]], side: side) <= worst(row, side: side) {
                row.append(indices[next])
                next += 1
            }
            let rowArea = row.reduce(0) { $0 + areas[$1]! }
            if remaining.width >= remaining.height {
                // A column along the left edge.
                let width = CGFloat(rowArea / Double(remaining.height))
                var y = remaining.minY
                for index in row {
                    let height = width > 0 ? CGFloat(areas[index]!) / width : 0
                    result[index] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(0, remaining.width - width), height: remaining.height)
            } else {
                // A row along the top edge.
                let height = CGFloat(rowArea / Double(remaining.width))
                var x = remaining.minX
                for index in row {
                    let width = height > 0 ? CGFloat(areas[index]!) / height : 0
                    result[index] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(0, remaining.height - height))
            }
            position = next
        }
        return result
    }
}
