// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore
import SwiftUI

/// First launch: a five-step tour (welcome, safety, Full Disk Access, menu bar, ready).
/// Reopened later for permissions only, it shows just the Full Disk Access step.
struct OnboardingView: View {
    enum Step: Int, CaseIterable, Comparable {
        case welcome, safety, access, menuBar, ready
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    @Environment(AppModel.self) private var app
    @Environment(MenuBarModel.self) private var menuBar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    @State private var isForward = true
    /// Only the permission step, when reopened from a "Grant Access" hint.
    @State private var accessOnly = false

    private let accent = SidebarModule.smartCare.palette.accent

    /// Set when a step was asked for explicitly (snapshot tour): show it as part of the tour.
    private let isPinned: Bool

    init(initialStep: Step? = nil) {
        _step = State(initialValue: initialStep ?? .welcome)
        isPinned = initialStep != nil
    }

    var body: some View {
        ZStack {
            ModuleBackground(module: .smartCare)
            VStack(spacing: 0) {
                if !accessOnly { progress.padding(.bottom, 18) }
                ZStack {
                    page(step)
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer.padding(.top, 18)
            }
            .padding(.horizontal, 44).padding(.top, 30).padding(.bottom, 30)
        }
        .frame(width: 680, height: 620)
        .preferredColorScheme(.dark)
        .onAppear {
            if app.hasCompletedOnboarding && !isPinned {
                accessOnly = true
                step = .access
            }
        }
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(.white.opacity(item == step ? 0.9 : item < step ? 0.45 : 0.18))
                    .frame(width: item == step ? 22 : 7, height: 7)
            }
        }
        .animation(Easing.out(0.25), value: step)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))
    }

    /// Pages slide a little in the direction of travel; with Reduce Motion they only fade.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let offset: CGFloat = isForward ? 28 : -28
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: offset)),
            removal: .opacity.combined(with: .offset(x: -offset)))
    }

    private func go(to next: Step) {
        isForward = next > step
        withAnimation(Easing.out(0.28)) { step = next }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        go(to: next)
    }

    @ViewBuilder
    private var footer: some View {
        if accessOnly {
            HStack {
                if app.fullDiskAccess == .granted {
                    Spacer()
                    Button("Done") { close() }
                        .buttonStyle(FilledButtonStyle(tint: accent)).keyboardShortcut(.defaultAction)
                    Spacer()
                } else {
                    Button("Not Now") { close() }.buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Open System Settings") { app.openFullDiskAccessSettings() }
                        .buttonStyle(FilledButtonStyle(tint: accent))
                }
            }
        } else {
            HStack {
                if step == .welcome {
                    Button("Skip Tour") { finish() }.buttonStyle(GhostButtonStyle())
                } else {
                    Button { go(to: Step(rawValue: step.rawValue - 1) ?? .welcome) } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                Spacer()
                switch step {
                case .access where app.fullDiskAccess != .granted:
                    Button("Later") { advance() }.buttonStyle(GhostButtonStyle())
                    Button("Open System Settings") { app.openFullDiskAccessSettings() }
                        .buttonStyle(FilledButtonStyle(tint: accent))
                case .ready:
                    Button("Explore on My Own") { finish() }.buttonStyle(GhostButtonStyle())
                    Button {
                        finish()
                        app.runSmartCare()
                    } label: { Label("Run Smart Care", systemImage: "sparkles") }
                        .buttonStyle(FilledButtonStyle(tint: accent))
                        .keyboardShortcut(.defaultAction)
                default:
                    Button("Continue") { advance() }
                        .buttonStyle(FilledButtonStyle(tint: accent))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome: welcome
        case .safety: safety
        case .access: access
        case .menuBar: menuBarPage
        case .ready: ready
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 0) {
            ModuleHero(module: .smartCare, size: 132, symbolOverride: "circle.hexagongrid.fill")
            Text("Welcome to Spaceroom").font(Typography.hero(30))
            Text("Give your Mac room again.")
                .font(.title3).foregroundStyle(.textSecondary).padding(.top, 4)
            HStack(spacing: 10) {
                area(String(localized: "Clean"), String(localized: "System and developer junk, and your forgotten files"),
                     modules: [.cleanup, .devCleanup, .clutter])
                area(String(localized: "Understand"), String(localized: "What fills your disk and how your Mac is doing"),
                     modules: [.spaceLens, .status])
                area(String(localized: "Manage"), String(localized: "Apps, startup items, malware, speed and privacy"),
                     modules: [.applications, .startup, .protection, .performance, .privacy])
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 26)
        }
    }

    private func area(_ title: String, _ detail: String, modules: [SidebarModule]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: -6) {
                ForEach(modules, id: \.self) { module in
                    GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 26, isCompact: true)
                }
            }
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassSurface(cornerRadius: 18)
    }

    private var safety: some View {
        @Bindable var app = app
        return VStack(spacing: 0) {
            ModuleHero(module: .restoreCenter, size: 104, symbolOverride: "checkmark.shield")
            Text("Safe by design").font(Typography.hero(28))
            Text("Spaceroom only removes what it can explain, and everything can come back.")
                .font(.callout).foregroundStyle(.textSecondary).multilineTextAlignment(.center).padding(.top, 4)
            VStack(spacing: 2) {
                promise("eye", String(localized: "Review first"),
                        String(localized: "Every item shows its size, location and why it's safe to remove."))
                promise("arrow.uturn.backward.circle", String(localized: "Undo anything"),
                        String(localized: "Cleaned items wait in the Restore Center before they're deleted.")) {
                    Picker("", selection: $app.retentionDays) {
                        ForEach(AppModel.retentionChoices, id: \.self) { Text("\($0) days").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                promise("eye.slash", String(localized: "Never touch what matters"),
                        String(localized: "Right-click anything and choose Always Ignore. Ignored items are never cleaned."))
                promise("lock.shield", String(localized: "Nothing leaves your Mac"),
                        String(localized: "No account, no tracking. All analysis happens on this Mac."))
            }
            .padding(6)
            .glassSurface()
            .padding(.top, 20)
        }
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        promise(symbol, title, detail) { EmptyView() }
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String,
                         @ViewBuilder accessory: () -> some View) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 28).foregroundStyle(.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
    }

    private var access: some View {
        let granted = app.fullDiskAccess == .granted
        return VStack(spacing: 0) {
            ModuleHero(module: .smartCare, size: 112, symbolOverride: granted ? "checkmark.shield.fill" : "lock.shield")
            Text(granted ? "Full Disk Access is on" : "Allow Full Disk Access").font(Typography.hero(28))
            Text(granted
                 ? "Spaceroom can now see every cleanable location."
                 : "macOS protects some folders, such as Trash, Mail and Safari data. Spaceroom needs access to measure and clean them. It never reads the contents of your documents.")
                .font(.callout).foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 480).padding(.top, 8)
            if !granted {
                VStack(alignment: .leading, spacing: 10) {
                    stepLine(1, "Click Open System Settings.")
                    stepLine(2, "Turn on Spaceroom in the Full Disk Access list.")
                    stepLine(3, "Come back here. Spaceroom notices automatically.")
                }
                .padding(18)
                .glassSurface(cornerRadius: 16)
                .padding(.top, 20)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for access…").font(.caption).foregroundStyle(.textTertiary)
                }
                .padding(.top, 12)
                if !accessOnly {
                    Text("You can do this later: locked places are marked, and the rest works without it.")
                        .font(.caption).foregroundStyle(.textTertiary).padding(.top, 6)
                }
            }
        }
        .task {
            // Live detection while this step is visible.
            while !Task.isCancelled, app.fullDiskAccess != .granted {
                app.refreshFullDiskAccess()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func stepLine(_ number: Int, _ text: LocalizedStringResource) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.2)))
            Text(text).font(.callout)
        }
    }

    private var menuBarPage: some View {
        @Bindable var menuBar = menuBar
        return VStack(spacing: 0) {
            // A slice of the menu bar with Spaceroom's item, drawn live from the chosen readings.
            HStack(spacing: 14) {
                Spacer()
                Image(nsImage: StatusItemImage.combined(menuBarParts))
                Image(systemName: "wifi").foregroundStyle(.white.opacity(0.7))
                Image(systemName: "battery.75percent").foregroundStyle(.white.opacity(0.7))
                Text(Date.now.formatted(date: .omitted, time: .shortened)).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.35)))
            .frame(maxWidth: 460)
            .padding(.top, 8)
            Text("Spaceroom in your menu bar").font(Typography.hero(28)).padding(.top, 26)
            Text("One item with the readings you pick. Click it for storage, quick cleans and your Mac's health.")
                .font(.callout).foregroundStyle(.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 480).padding(.top, 6)
            VStack(spacing: 0) {
                toggleRow("internaldrive", String(localized: "Free space"), isOn: $menuBar.isStorageItemShown)
                toggleRow("cpu", String(localized: "CPU usage"), isOn: $menuBar.isCPUItemShown)
                toggleRow("memorychip", String(localized: "Memory usage"), isOn: $menuBar.isMemoryItemShown)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, 4)
                toggleRow("power", String(localized: "Open at login"),
                          isOn: Binding(get: { menuBar.opensAtLogin }, set: { menuBar.setOpensAtLogin($0) }))
                toggleRow("menubar.rectangle", String(localized: "Keep running after the window closes"),
                          isOn: $menuBar.keepsRunningInMenuBar)
            }
            .padding(8)
            .glassSurface()
            .frame(maxWidth: 480)
            .padding(.top, 18)
        }
    }

    private var menuBarParts: [NSImage] {
        var parts: [NSImage] = []
        if menuBar.isStorageItemShown { parts.append(StatusItemImage.storage(menuBar.rootVolume, style: menuBar.storageStyle)) }
        if menuBar.isCPUItemShown { parts.append(StatusItemImage.cpu(menuBar.cpuUsage, history: menuBar.cpuHistory)) }
        if menuBar.isMemoryItemShown { parts.append(StatusItemImage.memory(menuBar.memory)) }
        return parts
    }

    private func toggleRow(_ symbol: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(.textSecondary)
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(accent)
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private var ready: some View {
        VStack(spacing: 0) {
            ModuleHero(module: .smartCare, size: 132, symbolOverride: "sparkles")
            Text("You're all set").font(Typography.hero(30))
            Text("Smart Care checks everything safe to clean in one go. Nothing is removed until you press Clean.")
                .font(.callout).foregroundStyle(.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 480).padding(.top, 6)
            HStack(spacing: 10) {
                tip("command", String(localized: "Press ⌘K to find any screen or run any action."))
                tip("clock.arrow.2.circlepath", String(localized: "Automations can keep your Mac tidy on a schedule."))
                tip("arrow.uturn.backward.circle", String(localized: "Changed your mind? The Restore Center brings it back."))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.textSecondary)
            Text(text).font(.caption).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassSurface(cornerRadius: 18)
    }

    // MARK: Closing

    private func finish() {
        app.hasCompletedOnboarding = true
        app.isShowingOnboarding = false
    }

    private func close() { app.isShowingOnboarding = false }
}
