// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import SwiftUI

/// Debug-only live tuning panel — a native take on DialKit (dialkit.dev), which only exists for
/// web frameworks. Every slider edits `DesignTokens.shared`, so changes show instantly in the app.
/// "Copy Values" puts Swift on the clipboard; paste it into `DesignTokens` to keep a tuning.
/// Copying never edits source files.
struct DesignTuningPanel: View {
    @Bindable private var tokens = DesignTokens.shared
    @State private var copied = false

    var body: some View {
        Form {
            Section("Press") {
                slider("Scale", $tokens.pressScale, 0.90...1, step: 0.005)
                slider("Duration", $tokens.pressDuration, 0.05...0.4, step: 0.01, unit: "s")
            }
            Section("Entrance (results, done, onboarding)") {
                slider("Duration", $tokens.enterDuration, 0.1...0.8, step: 0.01, unit: "s")
                slider("Rise", $tokens.enterOffset, 0...40, step: 1, unit: "pt")
                slider("Blur", $tokens.enterBlur, 0...12, step: 0.5, unit: "pt")
                slider("Stagger", $tokens.stagger, 0...0.25, step: 0.01, unit: "s")
                Button("Replay Entrance") { tokens.replayToken += 1 }
            }
            Section("Exit & switches") {
                slider("Exit", $tokens.exitDuration, 0.05...0.5, step: 0.01, unit: "s")
                slider("Module switch", $tokens.switchDuration, 0...0.5, step: 0.01, unit: "s")
                slider("Hover", $tokens.hoverDuration, 0...0.4, step: 0.01, unit: "s")
                slider("Icon swap", $tokens.iconSwapDuration, 0.1...0.8, step: 0.01, unit: "s")
            }
            Section("Surfaces") {
                slider("Card radius", $tokens.cardRadius, 8...32, step: 1, unit: "pt")
                slider("Ring", $tokens.ringOpacity, 0...0.3, step: 0.01)
                slider("Ring (hover)", $tokens.ringHoverOpacity, 0...0.4, step: 0.01)
                slider("Fill", $tokens.surfaceTint, 0...0.25, step: 0.01)
            }
            Section("Background") {
                slider("Grain", $tokens.grainOpacity, 0...1, step: 0.02)
                slider("Blobs", $tokens.blobOpacity, 0...1, step: 0.02)
                slider("Pattern", $tokens.patternOpacity, 0...0.6, step: 0.02)
            }
            Section("Primary button") {
                slider("Size", $tokens.primarySize, 60...140, step: 1, unit: "pt")
                slider("Glow", $tokens.primaryGlow, 0...1, step: 0.02)
            }
            Section {
                HStack {
                    Button("Reset to Defaults") { tokens.reset() }
                    Spacer()
                    Button(copied ? "Copied" : "Copy Values") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tokens.swiftSnippet, forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .frame(minHeight: 560)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double, unit: String = "") -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                // Continuous slider (a stepped one draws a tick per step); the value is rounded on display.
                Slider(value: Binding(get: { value.wrappedValue },
                                      set: { value.wrappedValue = ($0 / step).rounded() * step }),
                       in: range)
                    .frame(width: 140)
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(step < 0.1 ? 2 : 0))) + unit)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }
}

/// Debug menu command that opens the tuning panel.
struct DesignTuningCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Design Tuning…") { openWindow(id: "design-tuning") }
            .keyboardShortcut("t", modifiers: [.command, .option])
    }
}
#endif
