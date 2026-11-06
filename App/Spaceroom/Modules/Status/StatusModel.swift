// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SpaceroomCore
import SwiftUI

/// Live system readings for System Status. Samples only while the screen is visible.
@MainActor
@Observable
final class StatusModel {
    private(set) var cpu: Double?
    private(set) var cores: [Double] = []
    private(set) var cpuHistory: [Double] = []
    private(set) var load: (one: Double, five: Double, fifteen: Double)?
    private(set) var memory: MemorySnapshot?
    private(set) var memoryHistory: [Double] = []
    private(set) var swap: (used: Int64, total: Int64)?
    private(set) var network: (down: Double, up: Double)?
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []
    private(set) var volume: VolumeInfo?
    private(set) var battery: BatteryInfo?
    private(set) var thermal: ProcessInfo.ThermalState = .nominal
    private(set) var uptime: TimeInterval = 0
    private(set) var processes: [ProcessUsage] = []
    /// Seconds each process has stayed above 80 % CPU (for "busy for 2 min" badges).
    private(set) var busySeconds: [Int32: Int] = [:]

    private var cpuSampler = CPUSampler()
    private var networkSampler = NetworkSampler()
    private var processSampler = ProcessSampler()
    private var task: Task<Void, Never>?
    private var tick = 0

    static let historyLength = 60

    var health: HealthReport {
        let recent = cpuHistory.suffix(Self.historyLength)
        return HealthReport(.init(
            diskFreeFraction: volume?.freeFraction,
            memoryPressure: memory?.pressure,
            swapUsedBytes: swap?.used,
            averageCPU: recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count),
            thermal: thermal,
            batteryHealth: battery?.health,
            uptime: uptime))
    }

    func start() {
        guard task == nil else { return }
        // Fresh samplers and charts: rates measured since the screen was last open would be
        // averages over all that time.
        cpuSampler = CPUSampler()
        networkSampler = NetworkSampler()
        processSampler = ProcessSampler()
        cpuHistory = []
        memoryHistory = []
        downHistory = []
        upHistory = []
        sampleSlow()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleFast()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Every second: CPU, memory, network. Every 2 s: processes. Every 10 s: disk, battery.
    private func sampleFast() {
        tick += 1
        if let sample = cpuSampler.samplePerCore() {
            cpu = sample.total
            cores = sample.cores
            cpuHistory = Array((cpuHistory + [sample.total]).suffix(Self.historyLength))
        }
        if let snapshot = MemorySnapshot.current() {
            memory = snapshot
            memoryHistory = Array((memoryHistory + [snapshot.usedFraction]).suffix(Self.historyLength))
        }
        if let rates = networkSampler.sample() {
            network = rates
            downHistory = Array((downHistory + [rates.down]).suffix(Self.historyLength))
            upHistory = Array((upHistory + [rates.up]).suffix(Self.historyLength))
        }
        load = LoadAverage.current()
        thermal = ProcessInfo.processInfo.thermalState
        uptime = ProcessInfo.processInfo.systemUptime
        if tick % 2 == 0 {
            let top = processSampler.sample(limit: 8)
            if !top.isEmpty {
                processes = top
                var busy: [Int32: Int] = [:]
                for process in top where process.cpuPercent > 80 { busy[process.pid] = (busySeconds[process.pid] ?? 0) + 2 }
                busySeconds = busy
            }
        }
        if tick % 10 == 0 { sampleSlow() }
    }

    private func sampleSlow() {
        volume = Volumes.root()
        battery = BatteryInfo.current()
        swap = Swap.current()
    }

    // MARK: Actions

    /// The app behind a process, if it's a regular app the user could quit (never Spaceroom itself).
    func runningApp(for pid: Int32) -> NSRunningApplication? {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)
        return app?.activationPolicy == .regular ? app : nil
    }

    func quit(_ pid: Int32) {
        runningApp(for: pid)?.terminate()
    }
}
