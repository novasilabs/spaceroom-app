// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import SwiftUI

/// Privacy: browser traces and recent items (clearable, undoable) plus a read-only permissions review.
@MainActor
@Observable
final class PrivacyModel {
    struct Owner: Identifiable {
        var id: String { ownerID }
        let ownerID: String
        let name: String
        let bundleID: String?
        let items: [PrivacyItem]
        var size: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    private unowned let app: AppModel

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var items: [PrivacyItem] = []
    private(set) var lockedOwners: [String] = []
    /// `nil` when macOS wouldn't let us read the permission databases.
    private(set) var grants: [PermissionGrant]?
    private(set) var runningBundleIDs: Set<String> = []
    var selection: Set<String> = []
    private(set) var isWorking = false
    private(set) var lastResult: (message: String, operationID: UUID?)?

    init(app: AppModel) {
        self.app = app
    }

    var owners: [Owner] {
        var order: [String] = []
        var grouped: [String: [PrivacyItem]] = [:]
        for item in items {
            if grouped[item.owner] == nil { order.append(item.owner) }
            grouped[item.owner, default: []].append(item)
        }
        return order.map { id in
            let members = grouped[id] ?? []
            return Owner(ownerID: id, name: members.first?.ownerName ?? id, bundleID: members.first?.bundleID, items: members)
        }
    }

    func isRunning(_ owner: Owner) -> Bool { owner.bundleID.map(runningBundleIDs.contains) ?? false }

    var selectedItems: [PrivacyItem] {
        items.filter { selection.contains($0.id) && !($0.bundleID.map(runningBundleIDs.contains) ?? false) }
    }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        reload()
    }

    func reload() {
        isLoading = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            async let scan = Task.detached(priority: .userInitiated) { PrivacyScanner.scan(home: home) }.value
            async let permissions = Task.detached(priority: .utility) {
                let all = PermissionsReader.databases(home: home).compactMap(PermissionsReader.read)
                return all.isEmpty ? nil : all.flatMap { $0 }
            }.value
            let (result, readGrants) = await (scan, permissions)
            let firstLoad = !hasLoaded
            items = result.items
            lockedOwners = result.lockedOwners
            grants = readGrants
            runningBundleIDs = AppNames.runningBundleIDs()
            if firstLoad {
                // Cookies stay unticked: clearing them signs you out of websites.
                selection = Set(result.items.filter { !$0.kind.signsYouOut }.map(\.id))
            } else {
                selection.formIntersection(Set(result.items.map(\.id)))
            }
            isLoading = false
            hasLoaded = true
        }
    }

    func refreshRunning() { runningBundleIDs = AppNames.runningBundleIDs() }

    func toggle(_ item: PrivacyItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func quit(_ owner: Owner) {
        guard let bundleID = owner.bundleID else { return }
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { running.terminate() }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshRunning()
        }
    }

    func clearSelected() {
        guard let store = app.store else { return }
        refreshRunning()
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        isWorking = true
        Task {
            do {
                let outcome = try await PrivacyCleaner(store: store).clear(chosen, runningBundleIDs: runningBundleIDs)
                await app.refreshOperations()
                if let operation = outcome.operation {
                    lastResult = (String(localized: "Cleared \(chosen.count) items. They're in the Restore Center if you change your mind."), operation.id)
                }
            } catch {
                app.show(String(localized: "Couldn't clear"), error)
            }
            isWorking = false
            reload()
        }
    }

    func undoLast() {
        guard let id = lastResult?.operationID else { return }
        Task {
            if await app.restoreAll(id) { lastResult = (String(localized: "Restored. Everything is back."), nil) }
            reload()
        }
    }

    func dismissResult() { lastResult = nil }

    // MARK: Permissions

    func grants(for service: PermissionService) -> [PermissionGrant] {
        (grants ?? []).filter { $0.service == service.rawValue && $0.allowed }
            .sorted { Self.clientName($0.client).localizedStandardCompare(Self.clientName($1.client)) == .orderedAscending }
    }

    static func clientName(_ client: String) -> String {
        if client.hasPrefix("/") { return (client as NSString).lastPathComponent }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) else { return client }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func clientIcon(_ client: String) -> NSImage? {
        if client.hasPrefix("/") { return NSWorkspace.shared.icon(forFile: client) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: client).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func openSettings(_ service: PermissionService) {
        let anchor: String = switch service {
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        case .screenRecording: "Privacy_ScreenCapture"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .contacts: "Privacy_Contacts"
        case .calendars: "Privacy_Calendars"
        case .photos: "Privacy_Photos"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
