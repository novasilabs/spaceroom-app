// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("System Status: health score")
struct HealthReportTests {
    @Test func healthyMacScores100() {
        let report = HealthReport(.init(diskFreeFraction: 0.4, memoryPressure: .normal, swapUsedBytes: 0,
                                        averageCPU: 0.2, thermal: .nominal, batteryHealth: 0.95, uptime: 3_600))
        #expect(report.score == 100)
        #expect(report.grade == .good)
        #expect(report.factors.isEmpty)
    }

    @Test func worstFactorsComeFirstAndAddUp() {
        let report = HealthReport(.init(diskFreeFraction: 0.04, memoryPressure: .warning, averageCPU: 0.9,
                                        thermal: .fair, batteryHealth: 0.79, uptime: 20 * 86_400))
        #expect(report.factors.map(\.area) == [.disk, .cpu, .memory, .battery, .thermal, .uptime])
        #expect(report.score == 100 - 30 - 15 - 10 - 10 - 5 - 5)
        #expect(report.grade == .poor)
    }

    @Test("Disk thresholds", arguments: [(0.30, 0), (0.14, 10), (0.09, 20), (0.04, 30)])
    func diskThresholds(free: Double, penalty: Int) {
        #expect(100 - HealthReport(.init(diskFreeFraction: free)).score == penalty)
    }

    @Test func aSingleSeriousIssueIsNotHealthy() {
        #expect(HealthReport(.init(diskFreeFraction: 0.06)).grade == .fair) // 80
        #expect(HealthReport(.init(uptime: 20 * 86_400)).grade == .good)   // 95
    }

    @Test func neverBelowZero() {
        let report = HealthReport(.init(diskFreeFraction: 0, memoryPressure: .critical, averageCPU: 1,
                                        thermal: .critical, batteryHealth: 0.5, uptime: 100 * 86_400))
        #expect(report.score == 0)
    }
}

@Suite("System Status: battery")
struct BatteryInfoTests {
    @Test func parsesAppleSiliconRegistryValues() throws {
        // Values as reported by an Apple silicon MacBook (capacity as a percentage + raw mAh).
        let info = try #require(BatteryInfo(properties: [
            "CurrentCapacity": 80, "MaxCapacity": 100, "AppleRawMaxCapacity": 3541, "DesignCapacity": 4382,
            "CycleCount": 413, "IsCharging": false, "ExternalConnected": false, "Temperature": 3104,
            "Voltage": 11939, "InstantAmperage": NSNumber(value: UInt64(bitPattern: -498)),
        ]))
        #expect(info.percent == 80)
        #expect(info.cycleCount == 413)
        #expect(abs(info.health - 0.808) < 0.001)
        #expect(info.temperatureCelsius == 31.04)
        #expect(try #require(info.watts) < 0) // discharging
        #expect(!info.needsService)
    }

    @Test func parsesIntelStyleCapacityInMilliampHours() throws {
        let info = try #require(BatteryInfo(properties: [
            "CurrentCapacity": 2500, "MaxCapacity": 5000, "DesignCapacity": 6500, "CycleCount": 900,
        ]))
        #expect(info.percent == 50)
        #expect(info.needsService) // 5000 / 6500 ≈ 77 %
    }
}

@Suite("System Status: live readers")
struct LiveReaderTests {
    @Test func perCoreUsageCoversEveryCore() async throws {
        var sampler = CPUSampler()
        #expect(sampler.samplePerCore() == nil)
        try await Task.sleep(for: .milliseconds(200))
        let sample = sampler.samplePerCore()
        let result = try #require(sample)
        #expect(result.cores.count == ProcessInfo.processInfo.processorCount)
        #expect(result.cores.allSatisfy { (0...1).contains($0) })
    }

    @Test func swapLoadAndNetworkAreReadable() async throws {
        #expect(Swap.current() != nil)
        #expect(LoadAverage.current() != nil)
        var network = NetworkSampler()
        #expect(network.sample() == nil)
        try await Task.sleep(for: .milliseconds(200))
        let rates = network.sample()
        let value = try #require(rates)
        #expect(value.down >= 0 && value.up >= 0)
    }

    @Test("Process CPU uses Mach time units (a busy thread reads ~100 %, not 4000 %)")
    func processCPUIsPlausible() async throws {
        var sampler = ProcessSampler()
        _ = sampler.sample()
        // Burn one core for ~0.4 s.
        let deadline = Date.now.addingTimeInterval(0.4)
        var x = 0.0
        while Date.now < deadline { x += sin(x) + 1 }
        #expect(x > 0)
        let rows = sampler.sample(limit: 500)
        let me = try #require(rows.first { $0.pid == getpid() })
        #expect(me.cpuPercent > 40 && me.cpuPercent < 400, "measured \(me.cpuPercent)%")
        #expect(me.memoryBytes > 0)
        #expect(!me.name.isEmpty)
    }
}
