// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Photos that look alike (bursts, retakes, edited copies) in the user's own folders.
public struct SimilarPhotoGroup: Sendable, Identifiable, Hashable {
    public var id: String { keeper.id }
    /// Best first: the one to keep.
    public let photos: [SimilarPhoto]

    public init(photos: [SimilarPhoto]) {
        self.photos = photos
    }
    public var keeper: SimilarPhoto { photos[0] }
    public var others: [SimilarPhoto] { Array(photos.dropFirst()) }
    /// Space the other photos take.
    public var reclaimable: Int64 { others.reduce(0) { $0 + $1.file.size } }
}

public struct SimilarPhoto: Sendable, Identifiable, Hashable {
    public var id: String { file.id }
    public let file: ClutterFile
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// When it was taken (EXIF), else when the file was last changed.
    public let date: Date
    public var pixels: Int { pixelWidth * pixelHeight }
}

/// Finds similar photos with Vision's image feature prints, entirely on the Mac.
///
/// To stay fast on large folders it only compares photos that sit in the same folder and were
/// taken within `window` of each other, which is where bursts and retakes are. Nothing is ever
/// ticked for removal: similar isn't identical, so the user chooses.
public enum SimilarPhotoFinder {
    /// How alike photos must be. Feature-print distances (Vision revision 2) between retakes of
    /// one scene measured about 0.3–0.43, unrelated photos from 0.46 up.
    public enum Strictness: String, Sendable, CaseIterable {
        case nearlyIdentical, similar, loose
        public var threshold: Float {
            switch self {
            case .nearlyIdentical: 0.32
            case .similar: 0.40
            case .loose: 0.48
            }
        }
    }

    public static let threshold: Float = Strictness.similar.threshold
    public static let window: TimeInterval = 24 * 3600
    /// Photos compared at most (newest first), so a huge library can't stall the scan.
    public static let limit = 8000
    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "dng"]

    public static func isPhoto(_ file: ClutterFile) -> Bool {
        extensions.contains(file.url.pathExtension.lowercased())
    }

    public static func groups(
        from files: [ClutterFile],
        threshold: Float = threshold,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> [SimilarPhotoGroup] {
        await index(files, progress: progress, isCancelled: isCancelled).groups(threshold: threshold)
    }

    /// Analyses photos once; `SimilarPhotoIndex.groups(threshold:)` then regroups instantly.
    public static func index(
        _ files: [ClutterFile],
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> SimilarPhotoIndex {
        let photos = Array(files.filter(isPhoto).sorted { $0.modified > $1.modified }.prefix(limit))
        let analysed = await analyse(photos, progress: progress, isCancelled: isCancelled)
        return SimilarPhotoIndex(items: isCancelled() ? [] : analysed, wasLimited: files.filter(isPhoto).count > limit)
    }

    struct Analysed: @unchecked Sendable {   // VNFeaturePrintObservation is immutable once made
        let photo: SimilarPhoto
        let print: VNFeaturePrintObservation
    }

    static func analyse(_ files: [ClutterFile], progress: @escaping @Sendable (Int, Int) -> Void,
                        isCancelled: @escaping @Sendable () -> Bool) async -> [Analysed] {
        let workers = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
        return await withTaskGroup(of: Analysed?.self) { group in
            var results: [Analysed] = []
            var next = 0
            var done = 0
            func add() {
                guard next < files.count else { return }
                let file = files[next]
                next += 1
                group.addTask { isCancelled() ? nil : analyse(file) }
            }
            for _ in 0..<workers { add() }
            while let result = await group.next() {
                done += 1
                if let result { results.append(result) }
                if done % 25 == 0 || done == files.count { progress(done, files.count) }
                add()
            }
            return results
        }
    }

    /// A small thumbnail is enough for a feature print and keeps memory flat.
    static func analyse(_ file: ClutterFile) -> Analysed? {
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width >= 200, height >= 200 else { return nil }   // icons and screenshots of buttons
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        guard (try? VNImageRequestHandler(cgImage: thumbnail).perform([request])) != nil,
              let print = request.results?.first else { return nil }
        let photo = SimilarPhoto(file: file, pixelWidth: width, pixelHeight: height,
                                 date: captureDate(properties) ?? file.modified)
        return Analysed(photo: photo, print: print)
    }

    static func captureDate(_ properties: [CFString: Any]) -> Date? {
        guard let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    /// Groups photos in the same folder, within `window` of each other, closer than
    /// `threshold`. Union–find, so A~B and B~C make one group.
    static func cluster(_ items: [Analysed], threshold: Float) -> [SimilarPhotoGroup] {
        var parent = Array(items.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        let byFolder = Dictionary(grouping: items.indices) { items[$0].photo.file.url.deletingLastPathComponent().path }
        for (_, indices) in byFolder where indices.count > 1 {
            let sorted = indices.sorted { items[$0].photo.date < items[$1].photo.date }
            for (position, i) in sorted.enumerated() {
                for j in sorted[(position + 1)...] {
                    guard items[j].photo.date.timeIntervalSince(items[i].photo.date) <= window else { break }
                    var distance: Float = .infinity
                    guard (try? items[i].print.computeDistance(&distance, to: items[j].print)) != nil,
                          distance < threshold else { continue }
                    parent[find(j)] = find(i)
                }
            }
        }
        let grouped = Dictionary(grouping: items.indices, by: find).values.filter { $0.count > 1 }
        return grouped.map { indices in
            SimilarPhotoGroup(photos: indices.map { items[$0].photo }.sorted(by: isBetter))
        }
        .sorted { $0.reclaimable > $1.reclaimable }
    }

    /// The photo to keep: most pixels, then the larger file (less compression), then the
    /// original name over "IMG_1234 (1)", then the oldest.
    static func isBetter(_ a: SimilarPhoto, _ b: SimilarPhoto) -> Bool {
        if a.pixels != b.pixels { return a.pixels > b.pixels }
        if a.file.size != b.file.size { return a.file.size > b.file.size }
        let aCopy = DuplicateFinder.looksLikeCopy(a.file.name), bCopy = DuplicateFinder.looksLikeCopy(b.file.name)
        if aCopy != bCopy { return !aCopy }
        return a.file.modified < b.file.modified
    }
}

/// Feature prints of analysed photos, so the grouping can change without re-reading them.
public struct SimilarPhotoIndex: Sendable {
    let items: [SimilarPhotoFinder.Analysed]
    /// More photos were found than `SimilarPhotoFinder.limit`; only the newest were compared.
    public let wasLimited: Bool
    public var photoCount: Int { items.count }

    public static let empty = SimilarPhotoIndex(items: [], wasLimited: false)

    public func groups(threshold: Float = SimilarPhotoFinder.threshold) -> [SimilarPhotoGroup] {
        SimilarPhotoFinder.cluster(items, threshold: threshold)
    }
}
