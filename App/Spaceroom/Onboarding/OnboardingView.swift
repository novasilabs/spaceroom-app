// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// First launch: the three promises, then Full Disk Access with live detection.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var step: Step = .welcome

    enum Step { case welcome, fullDiskAccess }

    var body: some View {
        ZStack {
            ModuleBackground(module: .smartCare)
            Group {
                switch step {
                case .welcome: welcome.transition(.phaseSwap)
                case .fullDiskAccess: fullDiskAccess.transition(.phaseSwap)
                }
            }
            .padding(40)
        }
        .frame(width: 620, height: 560)
        .preferredColorScheme(.dark)
        .animation(Motion.phaseChange, value: step)
        .onAppear {
            // Reopened from the "Grant Access" hint: go straight to the permission step.
            if app.hasCompletedOnboarding { step = .fullDiskAccess }
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            ModuleHero(module: .smartCare, size: 140)
            Text("Welcome to Spaceroom").font(Typography.hero(30))
            Text("Give your Mac room again.")
                .font(.title3).foregroundStyle(.white.opacity(0.75)).padding(.top, 4)
            VStack(alignment: .leading, spacing: 16) {
                promise("eye", "See everything", "Every item shows its size, location and why it's safe to remove.")
                promise("arrow.uturn.backward.circle", "Undo anything", "Cleaned items wait in the Restore Center before they're deleted.")
                promise("lock.shield", "Nothing leaves your Mac", "No account, no tracking. All analysis happens on this Mac.")
            }
            .padding(.top, 26)
            Spacer()
            Button("Continue") { step = .fullDiskAccess }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var fullDiskAccess: some View {
        let granted = app.fullDiskAccess == .granted
        return VStack(spacing: 0) {
            ModuleHero(module: .privacy, size: 120, symbolOverride: granted ? "checkmark.shield.fill" : "lock.shield")
            Text(granted ? "Full Disk Access is on" : "Allow Full Disk Access")
                .font(Typography.hero(28))
            Text(granted
                 ? "Spaceroom can now see every cleanable location."
                 : "macOS protects some folders, such as Trash, Mail and Safari data. Spaceroom needs access to measure and clean them. It never reads the contents of your documents.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 8)

            if !granted {
                VStack(alignment: .leading, spacing: 10) {
                    stepLine(1, "Click Open System Settings.")
                    stepLine(2, "Turn on Spaceroom in the Full Disk Access list.")
                    stepLine(3, "Come back here. Spaceroom notices automatically.")
                }
                .padding(18)
                .glassSurface(cornerRadius: 14)
                .padding(.top, 22)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for access…").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 14)
            }
            Spacer()
            HStack {
                if !granted {
                    Button("Not Now") { finish() }.buttonStyle(GhostButtonStyle())
                    Spacer()
                    Button("Open System Settings") { app.openFullDiskAccessSettings() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Spacer()
                    Button("Start Using Spaceroom") { finish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    Spacer()
                }
            }
        }
        .task {
            // Live detection: poll while this step is visible.
            while !Task.isCancelled, app.fullDiskAccess != .granted {
                app.refreshFullDiskAccess()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func promise(_ symbol: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
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

    private func finish() {
        app.hasCompletedOnboarding = true
        app.isShowingOnboarding = false
    }
}
