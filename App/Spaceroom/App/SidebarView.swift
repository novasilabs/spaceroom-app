// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Translucent sidebar over the module gradient. Selection and hover respond instantly
/// (list navigation is high-frequency: no scale, no slide, ≤ 120 ms background fades).
struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic-light buttons (hidden title bar).
            Color.clear.frame(height: 36)
            wordmark
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            searchButton
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarModule.Section.allCases, id: \.self) { section in
                        if section == .footer {
                            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                                .padding(.vertical, 8).padding(.horizontal, 10)
                        } else if let title = section.title {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.4)
                                .textCase(.uppercase)
                                .foregroundStyle(.textTertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }
                        ForEach(SidebarModule.allCases.filter { $0.section == section }) { module in
                            SidebarRow(module: module, isSelected: app.selection == module,
                                       badge: badge(for: module)) {
                                app.selection = module
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)

            if app.fullDiskAccess == .denied {
                Button { app.isShowingOnboarding = true } label: {
                    HStack(spacing: 9) {
                        GlassGlyph(symbol: "lock.shield", tint: .hex(0xE0A93A), size: 22, isCompact: true)
                        Text("Allow Full Disk Access").font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.textTertiary)
                    }
                    // Concentric with the 22 pt glyph (radius ≈ 7) inset by 8 → 15.
                    .padding(8)
                    .glassSurface(cornerRadius: 15, wash: .hex(0xE0A93A))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 10).padding(.vertical, 10)
            }
        }
        .background {
            // Dark tint, not an opaque material: the module gradient and grain show through.
            Rectangle()
                .fill(Color.black.opacity(0.26))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
                }
                .ignoresSafeArea()
        }
    }

    private var searchButton: some View {
        Button { app.palette.open() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                Text("Search").font(.system(size: 13))
                Spacer(minLength: 0)
                Keycap("⌘K")
            }
            .foregroundStyle(.textSecondary)
            .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Search and commands"))
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            GlassGlyph(symbol: "circle.hexagongrid.fill", tint: .hex(0x8B6BE8), size: 26, isCompact: true)
            Text("Spaceroom")
                .font(.system(size: 17, weight: .bold))
        }
    }

    private func badge(for module: SidebarModule) -> String? {
        switch module {
        case .restoreCenter: app.storedSize > 0 ? app.storedSize.bytesText : nil
        default: nil
        }
    }
}

private struct SidebarRow: View {
    let module: SidebarModule
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ModuleIcon(module: module, size: 24)
                    .opacity(module.isAvailable || isSelected ? 1 : 0.55)
                Text(module.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(module.isAvailable || isSelected ? .white : .textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                // Badges keep their natural width; only the title shrinks or truncates.
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.16)))
                } else if !module.isAvailable {
                    Text("Soon").font(.system(size: 10, weight: .medium)).foregroundStyle(.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                // Concentric with the 24 pt icon: 8 (icon radius ≈ 7) + 5 inset ≈ 12.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.15 : (isHovering ? 0.07 : 0)))
            }
            .contentShape(Rectangle())
            .animation(Motion.hover, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
