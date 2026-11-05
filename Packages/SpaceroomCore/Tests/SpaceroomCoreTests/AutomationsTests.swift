// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Automations")
struct AutomationsTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func due(_ automation: Automation, at now: Date, free: Int64? = nil, launch: Bool = false, plugIn: Bool = false) -> Bool {
        AutomationSchedule.isDue(automation, context: AutomationContext(now: now, freeBytes: free, isLaunch: launch, didPlugIn: plugIn),
                                 calendar: calendar)
    }

    // MARK: Schedules

    @Test func dailyRunsOncePerDayAfterItsTime() {
        var daily = Automation(trigger: .daily(hour: 9, minute: 0), action: .scanAndNotify, createdAt: date(4, 20))
        #expect(!due(daily, at: date(5, 8, 59)))
        #expect(due(daily, at: date(5, 9, 0)))
        daily.lastRun = date(5, 9, 0)
        #expect(!due(daily, at: date(5, 18)))
        #expect(due(daily, at: date(6, 9, 1)))
    }

    @Test func aNewScheduleWaitsForItsNextTime() {
        // Made at 10:00, after today's 9:00: nothing runs until tomorrow.
        let daily = Automation(trigger: .daily(hour: 9, minute: 0), action: .scanAndNotify, createdAt: date(5, 10))
        #expect(!due(daily, at: date(5, 23)))
        #expect(due(daily, at: date(6, 9)))
    }

    @Test func catchesUpAfterTheMacSleptThroughIt() {
        var daily = Automation(trigger: .daily(hour: 9, minute: 0), action: .scanAndNotify, createdAt: date(1, 8))
        daily.lastRun = date(2, 9)
        // Asleep for three days: one catch-up run, not three.
        #expect(due(daily, at: date(5, 14)))
        daily.lastRun = date(5, 14)
        #expect(!due(daily, at: date(5, 23)))
    }

    @Test func weeklyRunsOnItsWeekday() {
        // 5 Nov 2026 is a Thursday (weekday 5).
        let weekly = Automation(trigger: .weekly(weekday: 7, hour: 10, minute: 0), action: .scanAndNotify, createdAt: date(5, 12))
        #expect(!due(weekly, at: date(6, 23)))
        #expect(due(weekly, at: date(7, 10)))
        #expect(AutomationSchedule.nextFire(weekly.trigger, after: date(5, 12), calendar: calendar) == date(7, 10))
    }

    @Test func switchingBackOnDoesNotCatchUp() {
        var daily = Automation(trigger: .daily(hour: 9, minute: 0), action: .scanAndNotify, createdAt: date(1, 8))
        daily.lastRun = date(1, 9)
        daily.createdAt = date(5, 12) // switched back on at noon, after today's 9:00
        #expect(!due(daily, at: date(5, 13)))
        #expect(due(daily, at: date(6, 9)))
    }

    @Test func disabledNeverRuns() {
        let off = Automation(trigger: .atLogin, action: .scanAndNotify, isEnabled: false)
        #expect(!due(off, at: .now, launch: true))
    }

    // MARK: Events

    @Test func lowDiskRunsBelowTheLimitWithACooldown() {
        var low = Automation(trigger: .lowDisk(freeBelowGB: 10), action: .smartCareClean, createdAt: date(1, 0))
        #expect(!due(low, at: date(5, 9), free: 20_000_000_000))
        #expect(!due(low, at: date(5, 9), free: nil))
        #expect(due(low, at: date(5, 9), free: 5_000_000_000))
        low.lastRun = date(5, 9)
        #expect(!due(low, at: date(5, 15), free: 5_000_000_000))
        #expect(due(low, at: date(5, 21, 1), free: 5_000_000_000))
    }

    @Test func loginAndPowerOnlyOnTheirEvent() {
        let login = Automation(trigger: .atLogin, action: .scanAndNotify)
        #expect(!due(login, at: .now))
        #expect(due(login, at: .now, launch: true))
        var power = Automation(trigger: .pluggedIn, action: .emptyTrash)
        #expect(!due(power, at: date(5, 9)))
        #expect(due(power, at: date(5, 9), plugIn: true))
        power.lastRun = date(5, 9)
        #expect(!due(power, at: date(5, 10), plugIn: true))
    }

    // MARK: Running

    func catalog() throws -> RuleCatalog {
        try RuleCatalog(rules: [
            Rule(id: "trash.user", module: .cleanup, group: "trash", title: "Trash", whySafe: "Already trashed.",
                 paths: ["~/.Trash/*"], smartCare: true),
            Rule(id: AutomationRunner.derivedDataRuleID, module: .devCleanup, group: "xcode", title: "DerivedData",
                 whySafe: "Rebuilt.", paths: ["~/Library/Developer/Xcode/DerivedData/*"], smartCare: true),
            Rule(id: "user.logs", module: .cleanup, group: "logs", title: "Not for automations",
                 whySafe: "Needs review.", paths: ["~/Library/Logs/*"], smartCare: false),
        ])
    }

    @Test func onlySmartCareRulesEverRunUnattended() throws {
        let runner = AutomationRunner(catalog: try catalog(), store: try Sandbox().store())
        #expect(Set(runner.rules(for: .smartCareClean).map(\.id)) == ["trash.user", AutomationRunner.derivedDataRuleID])
        #expect(runner.rules(for: .emptyTrash).map(\.id) == ["trash.user"])
        #expect(runner.rules(for: .purgeDerivedData(olderThanDays: 14)).first?.minAgeDays == 14)
    }

    @Test func scanOnlyNeverRemovesAnything() async throws {
        let box = try Sandbox()
        try box.file(".Trash/old.zip", bytes: 10_000)
        let runner = AutomationRunner(catalog: try catalog(), store: try box.store())
        let run = await runner.run(Automation(trigger: .atLogin, action: .scanAndNotify), context: box.context())
        #expect(run.foundBytes > 0)
        #expect(run.cleanedBytes == 0)
        #expect(run.operationID == nil)
        #expect(box.exists(".Trash/old.zip"))
    }

    @Test func emptyTrashGoesToTheRestoreCenter() async throws {
        let box = try Sandbox()
        try box.file(".Trash/old.zip", bytes: 10_000)
        try box.file("Library/Logs/keep.log")
        let store = try box.store()
        let runner = AutomationRunner(catalog: try catalog(), store: store)
        let run = await runner.run(Automation(trigger: .pluggedIn, action: .emptyTrash), context: box.context())
        #expect(run.error == nil)
        #expect(!box.exists(".Trash/old.zip"))
        #expect(box.exists("Library/Logs/keep.log"))
        let operationID = try #require(run.operationID)
        let operation = try #require(await store.operation(operationID))
        #expect(operation.module == "automations")
        _ = try await store.restoreAll(in: operation.id)
        #expect(box.exists(".Trash/old.zip"))
    }

    @Test func derivedDataKeepsRecentProjects() async throws {
        let box = try Sandbox()
        let base = "Library/Developer/Xcode/DerivedData"
        let old = try box.file("\(base)/Old-abc/Build/x.o", modified: .now.addingTimeInterval(-40 * 86_400))
        try box.backdate(old.deletingLastPathComponent(), to: .now.addingTimeInterval(-40 * 86_400))
        try box.backdate(box.home.appendingPathComponent("\(base)/Old-abc"), to: .now.addingTimeInterval(-40 * 86_400))
        try box.file("\(base)/Fresh-def/Build/y.o")
        let runner = AutomationRunner(catalog: try catalog(), store: try box.store())
        let run = await runner.run(Automation(trigger: .daily(hour: 3, minute: 0), action: .purgeDerivedData(olderThanDays: 30)),
                                   context: box.context())
        #expect(run.cleanedBytes > 0)
        #expect(!box.exists("\(base)/Old-abc"))
        #expect(box.exists("\(base)/Fresh-def/Build/y.o"))
    }

    @Test func freeSpaceNowSkipsTheRestoreCenter() async throws {
        let box = try Sandbox()
        try box.file(".Trash/old.zip", bytes: 10_000)
        let store = try box.store()
        let runner = AutomationRunner(catalog: try catalog(), store: store)
        let run = await runner.run(Automation(trigger: .lowDisk(freeBelowGB: 10), action: .emptyTrash, freesSpaceNow: true),
                                   context: box.context())
        #expect(run.freedNow)
        #expect(run.operationID == nil)
        #expect(await store.storedSize == 0)
    }

    // MARK: Store

    @Test func storeKeepsAutomationsAndCappedHistory() async throws {
        let box = try Sandbox()
        let automation = Automation(trigger: .weekly(weekday: 2, hour: 9, minute: 30), action: .purgeDerivedData(olderThanDays: 14))
        let store = try AutomationStore(directory: box.support)
        try await store.save(automation)
        for index in 0..<(AutomationStore.historyLimit + 5) {
            try await store.record(AutomationRun(automationID: automation.id, date: date(5, 9, index % 60), action: automation.action))
        }

        let reopened = try AutomationStore(directory: box.support)
        #expect(await reopened.automations.map(\.trigger) == [automation.trigger])
        #expect(await reopened.automations.first?.lastRun != nil)
        #expect(await reopened.history.count == AutomationStore.historyLimit)
        try await reopened.delete(automation.id)
        #expect(await reopened.automations.isEmpty)
    }

    @Test func unreadableFileIsNeverOverwritten() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.support, withIntermediateDirectories: true)
        let file = box.support.appendingPathComponent("automations.json")
        try Data("not json".utf8).write(to: file)
        #expect(throws: (any Error).self) { try AutomationStore(directory: box.support) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "not json")
    }
}
