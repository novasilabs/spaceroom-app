// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO
import SpaceroomCore
import SwiftUI

/// My Clutter: the user's own forgotten files, in four tabs.
struct ClutterView: View {
    @Bindable var model: ClutterModel
    @Environment(AppModel.self) private var app
    @State private var isConfirming = false

    private let module = SidebarModule.clutter

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro: intro.transition(.phaseSwap)
            case .scanning: scanning.transition(.phaseSwap)
            case .results: results.transition(.phaseSwap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Intro & scanning

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            ModuleHero(module: module, size: 150)
            Text(module.title).font(Typography.hero()).padding(.top, 6)
            Text(module.tagline).font(.title3).foregroundStyle(.textSecondary).padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(module.highlights.enumerated()), id: \.offset) { _, item in
                    Label { Text(item.text) } icon: { Image(systemName: item.symbol).foregroundStyle(.white).frame(width: 20) }
                        .font(.system(size: 14))
                        .foregroundStyle(.textSecondary)
                }
            }
            .padding(.top, 22)
            Text("Scans your home folder. App data in Library, hidden folders, apps and build folders like node_modules are skipped.")
                .font(.callout).foregroundStyle(.textTertiary).multilineTextAlignment(.center).frame(maxWidth: 520)
                .padding(.top, 18)
            Spacer(minLength: 20)
            PrimaryCircleButton(title: "Scan", tint: module.palette.accent) { model.start() }
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }

    private var scanning: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                Text(model.scannedItems.formatted())
                    .font(Typography.bigNumber())
                    .contentTransition(.numericText())
                Text("items checked").font(.title3).foregroundStyle(.textSecondary)
            }
            .entrance(0)
            Spacer()
            PrimaryCircleButton(title: "Stop", tint: module.palette.accent, progress: 0.25, isIndeterminate: true) {
                model.stop()
            }
            .padding(.bottom, 36)
        }
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 12)
            if let result = model.lastResult {
                resultBanner(result).padding(.horizontal, 28).padding(.bottom, 10).transition(.opacity)
            }
            if model.tab == .large { filterBar.padding(.horizontal, 28).padding(.bottom, 10) }
            Group {
                switch model.tab {
                case .large: fileList(model.largeFiles, empty: String(localized: "No files match these filters"))
                case .installers: fileList(model.installers, empty: String(localized: "No installer downloads found"))
                case .duplicates: duplicateList
                case .similar: similarList
                }
            }
            .padding(.horizontal, 28)
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .animation(Motion.hover, value: model.lastResult?.message)
        .sheet(isPresented: $isConfirming) {
            let files = model.selectedInTab
            ConfirmSheet(
                symbol: "trash",
                title: files.count == 1
                    ? String(localized: "Remove \(files[0].name)?")
                    : String(localized: "Remove \(files.count) files?"),
                message: String(localized: "They move to the Restore Center first, so you can put them back for \(app.retentionDays) days."),
                details: [
                    .init(symbol: "doc.on.doc", text: String(localized: "\(files.count) files · \(model.selectedSize.bytesText)")),
                    .init(symbol: "folder", text: String(localized: "From \(Set(files.map { $0.url.deletingLastPathComponent().path }).count) folders")),
                ],
                confirmTitle: String(localized: "Remove"),
                onConfirm: {
                    isConfirming = false
                    model.removeSelected()
                },
                onCancel: { isConfirming = false })
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(.system(size: 22, weight: .bold))
                Text("\(model.scannedItems.formatted()) items checked")
                    .font(.callout).foregroundStyle(.textSecondary).monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize()
            Spacer(minLength: 12)
            Picker("", selection: $model.tab) {
                Text("Large & Old · \(model.largeFiles.count)").tag(ClutterModel.Tab.large)
                Text(model.isFindingDuplicates ? "Duplicates…" : "Duplicates · \(model.duplicatesWaste.bytesText)")
                    .tag(ClutterModel.Tab.duplicates)
                Text(model.isFindingSimilar ? "Similar Photos…" : "Similar Photos · \(model.similarReclaimable.bytesText)")
                    .tag(ClutterModel.Tab.similar)
                Text("Installers · \(model.installersSize.bytesText)").tag(ClutterModel.Tab.installers)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
            Button { model.newScan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(GhostButtonStyle())
                .help("New Scan")
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Size", selection: $model.minimumSize) {
                ForEach(ClutterModel.MinimumSize.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Picker("Age", selection: $model.age) {
                ForEach(ClutterModel.Age.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Spacer()
            Text("Nothing is ticked for you here: these are your own files.")
                .font(.caption).foregroundStyle(.textTertiary)
        }
    }

    private func resultBanner(_ result: (message: String, operationID: UUID?)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(result.message).font(.callout.weight(.medium))
            Spacer()
            if result.operationID != nil {
                Button { model.undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(GhostButtonStyle())
            }
            Button { model.dismissResult() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.textSecondary)
                .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8)
        .glassSurface(cornerRadius: 18, wash: .hex(0x4FCB98))
    }

    private var footer: some View {
        HStack {
            if model.tab == .duplicates, !model.visibleDuplicates.isEmpty {
                Button("Tick All Extras") { model.tickAllExtras() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Ticks every copy except the one marked Keep")
            }
            if model.tab == .similar, !model.visibleSimilar.isEmpty {
                Button("Tick All but the Best") { model.tickAllButBest() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Ticks every photo except the one marked Keep in each group")
                Picker("Match", selection: $model.strictness) {
                    Text("Nearly identical").tag(SimilarPhotoFinder.Strictness.nearlyIdentical)
                    Text("Similar").tag(SimilarPhotoFinder.Strictness.similar)
                    Text("Loosely similar").tag(SimilarPhotoFinder.Strictness.loose)
                }
                .fixedSize()
                .help("How alike photos must be to be grouped")
            }
            Text(model.selectedInTab.isEmpty
                 ? String(localized: "Tick files to remove them")
                 : String(localized: "\(model.selectedInTab.count) selected · \(model.selectedSize.bytesText)"))
                .font(.callout).foregroundStyle(.textSecondary).monospacedDigit()
            Spacer()
            Button("Remove · \(model.selectedSize.bytesText)") { isConfirming = true }
                .buttonStyle(FilledButtonStyle(tint: .hex(0xFF5A6E)))
                .disabled(model.selectedInTab.isEmpty || model.isWorking || app.cleaningBlockedReason != nil)
        }
    }

    // MARK: Lists

    private func fileList(_ files: [ClutterFile], empty: String) -> some View {
        Group {
            if files.isEmpty {
                VStack(spacing: 8) {
                    GlassGlyph(symbol: "checkmark.seal", tint: module.palette.accent, size: 52)
                    Text(empty).font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(files) { file in
                            FileRow(file: file, isSelected: model.selection.contains(file.id),
                                    source: model.tab == .installers ? model.downloadSource(of: file) : nil,
                                    onIgnore: { model.ignore(file) }) {
                                model.toggle(file)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 20)
    }

    private var duplicateList: some View {
        Group {
            if model.isFindingDuplicates {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Comparing files by content…").foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleDuplicates.isEmpty {
                VStack(spacing: 8) {
                    GlassGlyph(symbol: "checkmark.seal", tint: module.palette.accent, size: 52)
                    Text("No duplicates over 1 MB").font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.visibleDuplicates) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(group.keeper.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Text("\(group.files.count) copies · \(group.wasted.bytesText) extra")
                                        .font(.caption).foregroundStyle(.textSecondary).monospacedDigit()
                                }
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                                ForEach(group.files) { file in
                                    let isKeeper = file.id == group.keeper.id
                                    FileRow(file: file, isSelected: !isKeeper && model.selection.contains(file.id),
                                            source: nil, isKeeper: isKeeper, onIgnore: { model.ignore(file) }) {
                                        model.toggle(file)
                                    }
                                    .disabled(isKeeper)
                                    .help(isKeeper ? "This copy is kept, so one always remains" : "")
                                }
                            }
                            .padding(4)
                            .glassSurface(cornerRadius: 16)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 20)
    }
}

extension ClutterView {
    var similarList: some View {
        Group {
            if model.isFindingSimilar {
                VStack(spacing: 10) {
                    ProgressView(value: Double(model.similarProgress.done), total: Double(max(model.similarProgress.total, 1)))
                        .frame(width: 260)
                    Text("Comparing photos… \(model.similarProgress.done.formatted()) of \(model.similarProgress.total.formatted())")
                        .foregroundStyle(.textSecondary).monospacedDigit()
                    Text("On this Mac, with Apple's Vision framework. Nothing is uploaded.")
                        .font(.caption).foregroundStyle(.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleSimilar.isEmpty {
                VStack(spacing: 8) {
                    GlassGlyph(symbol: "checkmark.seal", tint: module.palette.accent, size: 52)
                    Text("No similar photos").font(.title3.weight(.semibold))
                    Text("Photos in your Photos library aren't included. Photos has its own Duplicates album.")
                        .font(.callout).foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if model.similarIndex?.wasLimited == true {
                            Text("Only your \(SimilarPhotoFinder.limit.formatted()) newest photos were compared.")
                                .font(.caption).foregroundStyle(.textTertiary)
                        }
                        ForEach(model.visibleSimilar) { group in
                            SimilarGroupCard(group: group, selection: model.selection,
                                             toggle: { model.toggle($0) }, ignore: { model.ignore($0) })
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 20)
    }
}

/// One group of similar photos as a strip of thumbnails. The best one is marked Keep and
/// can't be ticked.
private struct SimilarGroupCard: View {
    let group: SimilarPhotoGroup
    let selection: Set<String>
    let toggle: (ClutterFile) -> Void
    let ignore: (ClutterFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.photos.count) similar photos").font(.system(size: 13, weight: .semibold))
                Text(group.keeper.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.textTertiary)
                Spacer()
                Text("\(group.reclaimable.bytesText) besides the best one")
                    .font(.caption).foregroundStyle(.textSecondary).monospacedDigit()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(group.photos) { photo in
                        let isKeeper = photo.id == group.keeper.id
                        PhotoTile(photo: photo, isKeeper: isKeeper, isSelected: !isKeeper && selection.contains(photo.id)) {
                            if !isKeeper { toggle(photo.file) }
                        }
                        .contextMenu {
                            Button("Show in Finder") { Finder.reveal(photo.file.url) }
                            Button("Always Ignore", systemImage: "eye.slash") { ignore(photo.file) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(10)
        .glassSurface(cornerRadius: 16)
    }
}

private struct PhotoTile: View {
    let photo: SimilarPhoto
    let isKeeper: Bool
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    PhotoThumbnail(url: photo.file.url)
                        .frame(width: 132, height: 99)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.white : .white.opacity(0.12), lineWidth: isSelected ? 2 : 1))
                    if isKeeper {
                        Pill(text: Text("Keep"), tint: .green)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .padding(6)
                    } else {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
                Text(photo.file.name).font(.caption).lineLimit(1).truncationMode(.middle).frame(width: 132, alignment: .leading)
                Text("\(photo.pixelWidth)×\(photo.pixelHeight) · \(photo.file.size.bytesText)")
                    .font(.system(size: 10)).foregroundStyle(.textTertiary).monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .help(isKeeper ? String(localized: "The best photo of the group is kept") : photo.file.url.path.abbreviatingHome)
        .accessibilityLabel(Text(photo.file.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small thumbnail read with ImageIO off the main thread, cached for the session.
private struct PhotoThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.06))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
            let url = url
            let cgImage = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                kCGImageSourceCreateThumbnailWithTransform: true,
                                                kCGImageSourceThumbnailMaxPixelSize: 300]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            guard let cgImage else { return }
            let result = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            Self.cache.setObject(result, forKey: url as NSURL)
            image = result
        }
    }
}

private struct FileRow: View {
    let file: ClutterFile
    let isSelected: Bool
    let source: String?
    var isKeeper = false
    var onIgnore: (() -> Void)?
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                IconSwap(isOn: isSelected, on: "checkmark.square.fill", off: "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? .white : .textTertiary)
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable().frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if isKeeper { Pill(text: Text("Keep"), tint: .green) }
                    }
                    Text(detail).font(.caption).foregroundStyle(.textTertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(file.modified, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.textTertiary)
                Text(file.size.bytesText)
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .frame(width: 76, alignment: .trailing)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.07 : 0)))
            .contentShape(Rectangle())
            .animation(Motion.hover, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Show in Finder") { Finder.reveal(file.url) }
            Button("Open") { NSWorkspace.shared.open(file.url) }
            if let onIgnore {
                Divider()
                Button("Always Ignore", systemImage: "eye.slash", action: onIgnore)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detail: String {
        let folder = file.url.deletingLastPathComponent().path.abbreviatingHome
        if let source { return String(localized: "\(folder) · from \(source)") }
        return folder
    }
}
