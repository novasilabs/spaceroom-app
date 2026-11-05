// SPDX-License-Identifier: GPL-3.0-or-later

import SpaceroomCore
import SwiftUI

/// Sheet for making or changing an automation: pick When, pick Do, then the options.
struct AutomationEditor: View {
    enum When: String, CaseIterable, Identifiable {
        case daily, weekly, lowDisk, atLogin, pluggedIn
        var id: String { rawValue }

        var title: String {
            switch self {
            case .daily: String(localized: "Every day")
            case .weekly: String(localized: "Every week")
            case .lowDisk: String(localized: "When disk space is low")
            case .atLogin: String(localized: "When Spaceroom opens")
            case .pluggedIn: String(localized: "When I plug in power")
            }
        }
    }

    enum Do: String, CaseIterable, Identifiable {
        case scan, smartCare, trash, derivedData
        var id: String { rawValue }

        var title: String {
            switch self {
            case .scan: String(localized: "Check for junk and tell me")
            case .smartCare: String(localized: "Run Smart Care cleanup")
            case .trash: String(localized: "Empty the Trash")
            case .derivedData: String(localized: "Clear old Xcode builds")
            }
        }
    }

    let original: Automation
    let isNew: Bool
    let retentionDays: Int
    let onSave: (Automation) -> Void
    let onCancel: () -> Void

    @State private var when: When
    @State private var time: Date
    @State private var weekday: Int
    @State private var gigabytes: Int
    @State private var what: Do
    @State private var days: Int
    @State private var notifies: Bool
    @State private var freesSpaceNow: Bool

    private let module = SidebarModule.automations

    init(original: Automation, isNew: Bool, retentionDays: Int,
         onSave: @escaping (Automation) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.isNew = isNew
        self.retentionDays = retentionDays
        self.onSave = onSave
        self.onCancel = onCancel

        var when = When.weekly, hour = 10, minute = 0, weekday = 7, gigabytes = 10
        switch original.trigger {
        case .daily(let h, let m): when = .daily; hour = h; minute = m
        case .weekly(let w, let h, let m): when = .weekly; weekday = w; hour = h; minute = m
        case .lowDisk(let gb): when = .lowDisk; gigabytes = gb
        case .atLogin: when = .atLogin
        case .pluggedIn: when = .pluggedIn
        }
        var what = Do.scan, days = 30
        switch original.action {
        case .scanAndNotify: what = .scan
        case .smartCareClean: what = .smartCare
        case .emptyTrash: what = .trash
        case .purgeDerivedData(let d): what = .derivedData; days = d
        }
        _when = State(initialValue: when)
        _time = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now)
        _weekday = State(initialValue: weekday)
        _gigabytes = State(initialValue: gigabytes)
        _what = State(initialValue: what)
        _days = State(initialValue: days)
        _notifies = State(initialValue: original.notifies)
        _freesSpaceNow = State(initialValue: original.freesSpaceNow)
    }

    var trigger: AutomationTrigger {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 10, minute = parts.minute ?? 0
        return switch when {
        case .daily: .daily(hour: hour, minute: minute)
        case .weekly: .weekly(weekday: weekday, hour: hour, minute: minute)
        case .lowDisk: .lowDisk(freeBelowGB: gigabytes)
        case .atLogin: .atLogin
        case .pluggedIn: .pluggedIn
        }
    }

    var action: AutomationAction {
        switch what {
        case .scan: .scanAndNotify
        case .smartCare: .smartCareClean
        case .trash: .emptyTrash
        case .derivedData: .purgeDerivedData(olderThanDays: days)
        }
    }

    var body: some View {
        ZStack {
            GrainyBackground(palette: module.palette)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    GlassGlyph(symbol: module.symbol, tint: module.palette.accent, size: 38)
                    Text(isNew ? "New Automation" : "Edit Automation").font(.system(size: 19, weight: .bold))
                }

                section("When") {
                    Picker("When", selection: $when) {
                        ForEach(When.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    switch when {
                    case .daily, .weekly:
                        HStack(spacing: 10) {
                            if when == .weekly {
                                Picker("Day", selection: $weekday) {
                                    ForEach(1...7, id: \.self) { Text(AutomationTrigger.weekdayName($0)).tag($0) }
                                }
                                .labelsHidden().frame(width: 140)
                            }
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                            Spacer()
                        }
                        hint(String(localized: "If your Mac is asleep then, it runs once when it wakes."))
                    case .lowDisk:
                        Stepper(value: $gigabytes, in: 1...200) {
                            Text("Free space below \(gigabytes) GB").monospacedDigit()
                        }
                        hint(String(localized: "Checked every minute; runs at most every 12 hours."))
                    case .atLogin:
                        hint(String(localized: "Runs when Spaceroom opens, at most once an hour. Set it to open at login to run at every login."))
                    case .pluggedIn:
                        hint(String(localized: "Runs when a laptop is connected to power, at most every 6 hours."))
                    }
                }

                section("Do") {
                    Picker("Do", selection: $what) {
                        ForEach(Do.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    if what == .derivedData {
                        Stepper(value: $days, in: 1...365) {
                            Text("Projects not built for \(days) days").monospacedDigit()
                        }
                    }
                    hint(action.detail)
                }

                section("Options") {
                    switchRow("Notify me when it runs", isOn: $notifies)
                    if action.removesFiles {
                        switchRow("Free the space right away", isOn: $freesSpaceNow)
                        if freesSpaceNow {
                            hint(String(localized: "Cleaned items are deleted instead of kept in the Restore Center. They can't be restored."), isWarning: true)
                        } else if when == .lowDisk {
                            hint(String(localized: "Items kept in the Restore Center still use space for \(retentionDays) days, so this won't help a full disk until then."), isWarning: true)
                        } else {
                            hint(String(localized: "Cleaned items stay restorable for \(retentionDays) days, and their space is freed when they leave the Restore Center."))
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GhostButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(isNew ? "Add Automation" : "Save") { onSave(built) }
                        .buttonStyle(FilledButtonStyle(tint: module.palette.accent))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(26)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .toggleStyle(.switch)
        .controlSize(.regular)
        .preferredColorScheme(.dark)
    }

    private var built: Automation {
        var automation = original
        if isNew || automation.trigger != trigger { automation.createdAt = .now }
        automation.trigger = trigger
        automation.action = action
        automation.notifies = notifies
        automation.freesSpaceNow = action.removesFiles && freesSpaceNow
        automation.isEnabled = isNew ? true : automation.isEnabled
        return automation
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).textCase(.uppercase).foregroundStyle(.textTertiary)
            VStack(alignment: .leading, spacing: 8, content: content)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: 16)
        }
    }

    private func switchRow(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).frame(maxWidth: .infinity, alignment: .leading) }
            .tint(module.palette.accent)
    }

    private func hint(_ text: String, isWarning: Bool = false) -> some View {
        Text(text).font(.caption)
            .foregroundStyle(isWarning ? AnyShapeStyle(Color.yellow.opacity(0.9)) : AnyShapeStyle(.textTertiary))
            .fixedSize(horizontal: false, vertical: true)
    }
}
