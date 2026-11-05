// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// My Clutter: the user's own forgotten files, in three tabs.
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
                Text("Installers · \(model.installersSize.bytesText)").tag(ClutterModel.Tab.installers)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
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
                                    source: model.tab == .installers ? model.downloadSource(of: file) : nil) {
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
                                            source: nil, isKeeper: isKeeper) {
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

private struct FileRow: View {
    let file: ClutterFile
    let isSelected: Bool
    let source: String?
    var isKeeper = false
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
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detail: String {
        let folder = file.url.deletingLastPathComponent().path.abbreviatingHome
        if let source { return String(localized: "\(folder) · from \(source)") }
        return folder
    }
}
