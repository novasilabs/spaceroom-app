// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// The ⌘K overlay: a search field over a ranked list. Keyboard first (↑ ↓ ↩ esc), mouse works too.
struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.close() }
            panel
                .padding(.top, 88)
        }
        .onAppear { isFocused = true }
    }

    private var panel: some View {
        let results = model.results
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(.textSecondary)
                TextField("Search or run a command", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isFocused)
                    .onSubmit { model.runHighlighted() }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.escape) { model.close(); return .handled }
                Keycap("esc")
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            if results.isEmpty {
                Text("No matches for “\(model.query)”")
                    .font(.callout).foregroundStyle(.textTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                                if showsHeader(at: index, in: results) {
                                    Text(command.kind.title)
                                        .font(.system(size: 11, weight: .semibold)).tracking(0.3).textCase(.uppercase)
                                        .foregroundStyle(.textTertiary)
                                        .padding(.horizontal, 12).padding(.top, index == 0 ? 4 : 10).padding(.bottom, 3)
                                }
                                PaletteRow(command: command, isHighlighted: index == model.highlighted,
                                           showsKind: !model.query.trimmingCharacters(in: .whitespaces).isEmpty)
                                    .id(command.id)
                                    .onHover { if $0 { model.highlighted = index } }
                                    .onTapGesture { model.run(command) }
                            }
                        }
                        .padding(6)
                    }
                    .scrollIndicators(.never)
                    .frame(maxHeight: 380)
                    .onChange(of: model.highlighted) { _, index in
                        guard results.indices.contains(index) else { return }
                        proxy.scrollTo(results[index].id)
                    }
                }
            }

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 14) {
                hint(["↑", "↓"], "to move")
                hint(["↩"], "to run")
                Spacer()
                Text("Anything that removes files asks first").font(.caption).foregroundStyle(.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.38))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .glassSurface(cornerRadius: 22)
        .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
        .environment(\.colorScheme, .dark)
    }

    private func showsHeader(at index: Int, in results: [PaletteCommand]) -> Bool {
        guard model.query.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return index == 0 || results[index - 1].kind != results[index].kind
    }

    private func hint(_ keys: [String], _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { Keycap($0) }
            Text(text).font(.caption).foregroundStyle(.textTertiary)
        }
    }
}

private struct PaletteRow: View {
    let command: PaletteCommand
    let isHighlighted: Bool
    let showsKind: Bool

    var body: some View {
        HStack(spacing: 11) {
            GlassGlyph(symbol: command.symbol, tint: command.tint, size: 26, isCompact: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let subtitle = command.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsKind {
                Text(command.kind.title).font(.caption).foregroundStyle(.textTertiary)
            }
            if let shortcut = command.shortcut { Keycap(shortcut) }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background {
            // Keyboard-driven list: highlight follows instantly, no animation.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHighlighted ? 0.12 : 0))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// A small key label, like "⌘K" or "esc".
struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// The bottom-of-window message after a palette action, with Undo when something moved.
struct ToastView: View {
    let toast: CommandPaletteModel.Toast
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.message).font(.callout.weight(.medium))
            if toast.operationID != nil {
                Button { onUndo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(GhostButtonStyle())
            }
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.textSecondary).accessibilityLabel(Text("Dismiss"))
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.45)).background(.ultraThinMaterial, in: Capsule()))
        .glassSurface(cornerRadius: 30)
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}
