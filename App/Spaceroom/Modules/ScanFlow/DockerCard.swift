// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import SpaceroomCore
import SwiftUI

/// Docker's build cache and dangling images, shown under the Dev Cleanup results. Docker
/// removes them itself, so this is the one clean that can't go through the Restore Center.
/// It has its own button and says so before anything runs.
@MainActor
@Observable
final class DockerModel {
    private(set) var status: DockerStatus?
    private(set) var isChecking = false
    private(set) var isPruning = false
    private(set) var lastResult: DockerPruneResult?
    var includeBuildCache = true
    var includeImages = true
    @ObservationIgnored private var docker = Docker()

    func check() {
        guard !isChecking, !isPruning else { return }
        isChecking = true
        lastResult = nil
        let docker = docker
        Task {
            let status = await Task.detached(priority: .utility) { docker.status() }.value
            self.status = status
            isChecking = false
        }
    }

    var usage: DockerUsage? {
        if case .ready(let usage) = status { return usage }
        return nil
    }

    var isVisible: Bool { isChecking || (status != nil && status != .notInstalled) || lastResult != nil }

    var selectedSize: Int64 {
        guard let usage else { return 0 }
        return (includeBuildCache ? usage.buildCache : 0) + (includeImages ? usage.danglingImages : 0)
    }

    func prune() {
        guard selectedSize > 0, !isPruning else { return }
        isPruning = true
        let docker = docker, cache = includeBuildCache && (usage?.buildCache ?? 0) > 0
        let images = includeImages && (usage?.danglingImages ?? 0) > 0
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                docker.prune(buildCache: cache, danglingImages: images)
            }.value
            lastResult = result
            status = await Task.detached(priority: .utility) { docker.status() }.value
            isPruning = false
        }
    }

    #if DEBUG
    /// Snapshot tour: show the card with sample numbers. Nothing is run.
    func showForSnapshot(_ usage: DockerUsage) {
        docker = Docker(executable: nil)
        status = .ready(usage)
    }
    #endif
}

struct DockerCard: View {
    @Bindable var model: DockerModel
    @Environment(AppModel.self) private var app
    @State private var isConfirming = false

    var body: some View {
        HStack(spacing: 14) {
            GlassGlyph(symbol: "cube.box", tint: .hex(0x3E8EF7), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Docker").font(.system(size: 14, weight: .semibold))
                detail
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassSurface(cornerRadius: 20)
        .animation(Motion.hover, value: model.isChecking)
        .sheet(isPresented: $isConfirming) {
            ConfirmSheet(
                symbol: "cube.box",
                title: String(localized: "Let Docker free up to \(model.selectedSize.bytesText)?"),
                message: String(localized: "Docker removes these itself, so they don't go to the Restore Center and can't be restored. Docker rebuilds the cache and downloads images again when it needs them."),
                details: [
                    .init(symbol: "checkmark.circle", text: String(localized: "Build cache and untagged images only")),
                    .init(symbol: "lock", text: String(localized: "Containers, volumes and tagged images aren't touched")),
                ],
                confirmTitle: String(localized: "Free Space"),
                onConfirm: {
                    isConfirming = false
                    model.prune()
                },
                onCancel: { isConfirming = false })
        }
    }

    @ViewBuilder private var detail: some View {
        Group {
            if model.isChecking {
                Text("Checking Docker…")
            } else if model.isPruning {
                Text("Docker is freeing space…")
            } else if model.status == .notRunning {
                Text("Docker isn't running. Open it to see its build cache and unused images.")
            } else if let usage = model.usage {
                if let result = model.lastResult {
                    Text(result.failures.isEmpty
                         ? String(localized: "Docker freed \(result.reclaimed.bytesText).")
                         : String(localized: "Docker freed \(result.reclaimed.bytesText). Some steps failed: \(result.failures.joined(separator: ", "))."))
                } else if usage.reclaimable == 0 {
                    Text("Nothing to free. Images in use, containers and volumes are never touched.")
                } else {
                    HStack(spacing: 14) {
                        toggle(String(localized: "Build cache \(usage.buildCache.bytesText)"),
                               isOn: $model.includeBuildCache, enabled: usage.buildCache > 0)
                        toggle(String(localized: "\(usage.danglingImageCount) untagged images, up to \(usage.danglingImages.bytesText)"),
                               isOn: $model.includeImages, enabled: usage.danglingImages > 0)
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.textSecondary)
        .lineLimit(2)
    }

    @ViewBuilder private var trailing: some View {
        if model.isChecking || model.isPruning {
            ProgressView().controlSize(.small)
        } else if model.status == .notRunning || model.lastResult != nil {
            Button("Check Again") { model.check() }.buttonStyle(GhostButtonStyle())
        } else if let usage = model.usage, usage.reclaimable > 0 {
            Button("Free up to \(model.selectedSize.bytesText)…") { isConfirming = true }
                .buttonStyle(GhostButtonStyle())
                .disabled(model.selectedSize == 0)
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn.wrappedValue && enabled ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn.wrappedValue && enabled ? .white : .textTertiary)
                Text(title).monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
