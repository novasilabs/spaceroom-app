// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Treemap layout")
struct TreemapTests {
    let bounds = CGRect(x: 10, y: 20, width: 600, height: 400)

    @Test("Areas match the values and tiles fill the bounds without overlapping")
    func areas() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = Treemap.squarify(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = Double(bounds.width * bounds.height) * value / total
            #expect(abs(Double(rect.width * rect.height) - expected) < 0.5)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test("Tiles stay close to square")
    func aspect() {
        let rects = Treemap.squarify([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], in: bounds)
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        #expect(worst < 4)
    }

    @Test("Zero values and empty bounds are handled")
    func edges() {
        #expect(Treemap.squarify([0, 5, 0], in: bounds)[0] == .zero)
        #expect(Treemap.squarify([0, 5, 0], in: bounds)[1].width * Treemap.squarify([0, 5, 0], in: bounds)[1].height > 239_000)
        #expect(Treemap.squarify([1, 2], in: .zero) == [.zero, .zero])
        #expect(Treemap.squarify([], in: bounds).isEmpty)
    }
}
