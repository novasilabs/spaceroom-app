// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SpaceroomCore

@Suite("Similar photos")
struct SimilarPhotosTests {
    /// Draws a test "photo": a scene of shapes, optionally shifted, brightened or resized.
    static func writePhoto(to url: URL, scene: Int, shift: CGFloat = 0, brightness: CGFloat = 0,
                           width: Int = 1200, height: Int = 900, quality: Double = 0.9) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let w = CGFloat(width), h = CGFloat(height)
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            CGColor(srgbRed: min(1, r + brightness), green: min(1, g + brightness), blue: min(1, b + brightness), alpha: 1)
        }
        switch scene {
        case 0: // sky, sun and hills
            context.setFillColor(color(0.35, 0.6, 0.9)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.setFillColor(color(1, 0.85, 0.2)); context.fillEllipse(in: CGRect(x: w * 0.65 + shift, y: h * 0.6, width: w * 0.18, height: w * 0.18))
            context.setFillColor(color(0.2, 0.55, 0.25)); context.fillEllipse(in: CGRect(x: -w * 0.2 + shift, y: -h * 0.5, width: w * 0.9, height: h * 0.9))
            context.setFillColor(color(0.15, 0.45, 0.2)); context.fillEllipse(in: CGRect(x: w * 0.4 + shift, y: -h * 0.55, width: w * 0.9, height: h * 0.85))
        default: // stripes and squares, different colours
            for i in 0..<12 {
                context.setFillColor(i % 2 == 0 ? color(0.8, 0.1, 0.3) : color(0.1, 0.1, 0.12))
                context.fill(CGRect(x: CGFloat(i) * w / 12, y: 0, width: w / 12, height: h))
            }
            context.setFillColor(color(0.95, 0.95, 0.9)); context.fill(CGRect(x: w * 0.3, y: h * 0.3, width: w * 0.4, height: h * 0.4))
        }
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func file(_ url: URL, modified: Date = .now) -> ClutterFile {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ClutterFile(url: url, size: size, modified: modified)
    }

    @Test("Retakes group together, different scenes don't, and the sharpest one is kept")
    func groups() async throws {
        let box = try Sandbox()
        let folder = try box.folder("Pictures/Trip")
        let a = folder.appendingPathComponent("IMG_0001.jpg"), b = folder.appendingPathComponent("IMG_0002.jpg")
        let c = folder.appendingPathComponent("IMG_0003.jpg"), other = folder.appendingPathComponent("IMG_0004.jpg")
        try Self.writePhoto(to: a, scene: 0, width: 1600, height: 1200)
        try Self.writePhoto(to: b, scene: 0, shift: 12, brightness: 0.04)
        try Self.writePhoto(to: c, scene: 0, shift: -10, quality: 0.6)
        try Self.writePhoto(to: other, scene: 1)
        let now = Date.now
        let files = [a, b, c, other].enumerated().map { file($1, modified: now.addingTimeInterval(Double($0) * 5)) }

        let groups = await SimilarPhotoFinder.groups(from: files)
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(Set(group.photos.map(\.file.url.lastPathComponent)) == ["IMG_0001.jpg", "IMG_0002.jpg", "IMG_0003.jpg"])
        #expect(group.keeper.file.url.lastPathComponent == "IMG_0001.jpg")   // most pixels
        #expect(group.reclaimable == group.others.reduce(0) { $0 + $1.file.size })
    }

    @Test("Photos in different folders or far apart in time aren't compared")
    func scope() async throws {
        let box = try Sandbox()
        let one = try box.folder("Pictures/One"), two = try box.folder("Pictures/Two")
        let a = one.appendingPathComponent("a.jpg"), b = two.appendingPathComponent("b.jpg")
        let c = one.appendingPathComponent("c.jpg")
        try Self.writePhoto(to: a, scene: 0)
        try Self.writePhoto(to: b, scene: 0)
        try Self.writePhoto(to: c, scene: 0, shift: 5)
        let groups = await SimilarPhotoFinder.groups(from: [
            file(a, modified: .now), file(b, modified: .now),
            file(c, modified: .now.addingTimeInterval(-3 * 86_400)),
        ])
        #expect(groups.isEmpty)
    }

    @Test("Tiny images and non-photos are left out")
    func filters() async throws {
        let box = try Sandbox()
        let folder = try box.folder("Pictures")
        let icon1 = folder.appendingPathComponent("icon1.jpg"), icon2 = folder.appendingPathComponent("icon2.jpg")
        try Self.writePhoto(to: icon1, scene: 0, width: 64, height: 64)
        try Self.writePhoto(to: icon2, scene: 0, width: 64, height: 64)
        #expect(await SimilarPhotoFinder.groups(from: [file(icon1), file(icon2)]).isEmpty)
        #expect(!SimilarPhotoFinder.isPhoto(ClutterFile(url: URL(fileURLWithPath: "/x/design.psd"), size: 1, modified: .now)))
        #expect(SimilarPhotoFinder.isPhoto(ClutterFile(url: URL(fileURLWithPath: "/x/IMG.HEIC"), size: 1, modified: .now)))
    }
}
