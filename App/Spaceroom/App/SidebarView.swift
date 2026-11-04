// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic-light buttons (hidden title bar).
            Color.clear.frame(height: 38)
            wordmark
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarModule.Section.allCases, id: \.self) { section in
                        if section == .footer {
                            Divider().overlay(.white.opacity(0.15)).padding(.vertical, 10).padding(.horizontal, 8)
                        } else if let title = section.title {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.top, 14)
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
                    Label("Full Disk Access needed", systemImage: "lock.shield")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.yellow.opacity(0.18)))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.22))
                .ignoresSafeArea()
        }
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
            Text("Spaceroom")
                .font(.system(size: 18, weight: .bold, design: .rounded))
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
                ModuleIcon(module: module)
                Text(module.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.18)))
                } else if !module.isAvailable {
                    Text("Soon").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.18 : (isHovering ? 0.08 : 0)))
            }
            .contentShape(Rectangle())
            .opacity(module.isAvailable || isSelected ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
