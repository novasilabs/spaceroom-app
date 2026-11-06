// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import IOKit

// MARK: - CPU (per core) and load

extension CPUSampler {
    /// Usage 0…1 per core since the previous call (`nil` on the first call).
    public mutating func samplePerCore() -> (total: Double, cores: [Double])? {
        guard let current = Self.readTicks() else { return nil }
        defer { previousCores = current }
        guard let previous = previousCores, previous.count == current.count else { return nil }
        var busyAll: UInt64 = 0, totalAll: UInt64 = 0
        let cores = zip(previous, current).map { old, new -> Double in
            let busy = UInt64(new.busy &- old.busy), total = UInt64(new.total &- old.total)
            busyAll += busy
            totalAll += total
            return total == 0 ? 0 : min(1, Double(busy) / Double(total))
        }
        return (totalAll == 0 ? 0 : min(1, Double(busyAll) / Double(totalAll)), cores)
    }
}

public enum LoadAverage {
    /// 1, 5 and 15 minute load averages.
    public static func current() -> (one: Double, five: Double, fifteen: Double)? {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return nil }
        return (loads[0], loads[1], loads[2])
    }
}

// MARK: - Swap

public enum Swap {
    public static func current() -> (used: Int64, total: Int64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (Int64(usage.xsu_used), Int64(usage.xsu_total))
    }
}

// MARK: - Network

/// Bytes per second in and out across physical and VPN interfaces (loopback excluded).
public struct NetworkSampler: Sendable {
    private var previous: (received: UInt64, sent: UInt64, at: Date)?

    public init() {}

    public mutating func sample(now: Date = .now) -> (down: Double, up: Double)? {
        guard let counters = Self.readCounters() else { return nil }
        defer { previous = (counters.received, counters.sent, now) }
        guard let previous else { return nil }
        let seconds = now.timeIntervalSince(previous.at)
        guard seconds > 0 else { return nil }
        // Per-interface 32-bit counters wrap; a drop means a wrap or an interface going away.
        let down = counters.received >= previous.received ? Double(counters.received - previous.received) : 0
        let up = counters.sent >= previous.sent ? Double(counters.sent - previous.sent) : 0
        return (down / seconds, up / seconds)
    }

    static func readCounters() -> (received: UInt64, sent: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var received: UInt64 = 0, sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }
}

// MARK: - Battery

public struct BatteryInfo: Sendable, Hashable {
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let cycleCount: Int
    /// Full-charge capacity vs. design capacity, 0…1.
    public let health: Double
    public let temperatureCelsius: Double?
    /// Positive while charging, negative on battery.
    public let watts: Double?

    /// Apple considers a battery worn below 80 % of its design capacity.
    public var needsService: Bool { health < 0.8 }

    public static func current() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryInfo(properties: properties)
    }

    /// Parses AppleSmartBattery registry properties (Apple silicon and Intel report capacity differently).
    init?(properties p: [String: Any]) {
        func int(_ key: String) -> Int? { (p[key] as? NSNumber)?.intValue }
        guard let current = int("CurrentCapacity"), let max = int("MaxCapacity"), max > 0 else { return nil }
        // Apple silicon reports MaxCapacity as a percentage and the real figure separately.
        let fullCharge = int("AppleRawMaxCapacity") ?? max
        let design = int("DesignCapacity") ?? fullCharge
        percent = max <= 100 ? current : Int((Double(current) / Double(max) * 100).rounded())
        isCharging = (p["IsCharging"] as? Bool) ?? false
        isPluggedIn = (p["ExternalConnected"] as? Bool) ?? false
        cycleCount = int("CycleCount") ?? 0
        health = design > 0 ? min(1, Double(fullCharge) / Double(design)) : 1
        temperatureCelsius = int("Temperature").map { Double($0) / 100 }
        if let millivolts = int("Voltage"),
           let raw = (p["InstantAmperage"] as? NSNumber)?.uint64Value {
            let milliamps = Int64(bitPattern: raw) // reported unsigned; negative while discharging
            watts = Double(millivolts) / 1000 * Double(milliamps) / 1000
        } else {
            watts = nil
        }
    }

    init(percent: Int, isCharging: Bool, isPluggedIn: Bool, cycleCount: Int, health: Double,
         temperatureCelsius: Double?, watts: Double?) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.cycleCount = cycleCount
        self.health = health
        self.temperatureCelsius = temperatureCelsius
        self.watts = watts
    }
}

// MARK: - Processes

public struct ProcessUsage: Sendable, Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    /// Percent of one core (can exceed 100 for multi-threaded work).
    public let cpuPercent: Double
    public let memoryBytes: Int64
}

/// Per-process CPU between samples, for processes this user may inspect.
public struct ProcessSampler: Sendable {
    private var previous: [Int32: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    public init() {}

    /// Top processes by CPU since the previous call (empty on the first call).
    public mutating func sample(limit: Int = 8) -> [ProcessUsage] {
        let now = mach_absolute_time()
        var current: [Int32: UInt64] = [:]
        var rows: [(pid: Int32, cpu: UInt64, memory: Int64)] = []
        for pid in Self.allPIDs() where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let cpu = info.pti_total_user + info.pti_total_system
            current[pid] = cpu
            rows.append((pid, cpu, Int64(info.pti_resident_size)))
        }
        defer {
            previous = current
            previousTime = now
        }
        guard previousTime > 0, now > previousTime else { return [] }
        let wall = Double(now - previousTime)
        let usages: [ProcessUsage] = rows.compactMap { row in
            guard let before = previous[row.pid], row.cpu >= before else { return nil }
            // Task times are in Mach time units, like `mach_absolute_time`.
            let percent = Double(row.cpu - before) / wall * 100
            return ProcessUsage(pid: row.pid, name: Self.name(of: row.pid), cpuPercent: percent, memoryBytes: row.memory)
        }
        return Array(usages.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
    }

    static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(max(0, filled))))
    }

    static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return String(localized: "process \(pid)", bundle: .module) }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

// MARK: - Health score

/// Mac health from 0 to 100 with the factors behind it, worst first.
public struct HealthReport: Sendable, Hashable {
    public enum Area: String, Sendable, Hashable { case disk, memory, cpu, thermal, battery, uptime }

    public struct Factor: Sendable, Hashable, Identifiable {
        public var id: Area { area }
        public let area: Area
        public let penalty: Int
        public let summary: String
        public let advice: String
    }

    public enum Grade: Sendable { case good, fair, poor }

    public let score: Int
    public let factors: [Factor]

    /// "Good" leaves no room for a real problem: one 20-point issue already drops below it.
    public var grade: Grade { score >= 85 ? .good : score >= 60 ? .fair : .poor }

    public struct Inputs: Sendable {
        public var diskFreeFraction: Double?
        public var memoryPressure: MemorySnapshot.Pressure?
        public var swapUsedBytes: Int64?
        /// Average total CPU over the last minute, 0…1.
        public var averageCPU: Double?
        public var thermal: ProcessInfo.ThermalState?
        public var batteryHealth: Double?
        public var uptime: TimeInterval?

        public init(diskFreeFraction: Double? = nil, memoryPressure: MemorySnapshot.Pressure? = nil,
                    swapUsedBytes: Int64? = nil, averageCPU: Double? = nil, thermal: ProcessInfo.ThermalState? = nil,
                    batteryHealth: Double? = nil, uptime: TimeInterval? = nil) {
            self.diskFreeFraction = diskFreeFraction
            self.memoryPressure = memoryPressure
            self.swapUsedBytes = swapUsedBytes
            self.averageCPU = averageCPU
            self.thermal = thermal
            self.batteryHealth = batteryHealth
            self.uptime = uptime
        }
    }

    public init(_ input: Inputs) {
        var factors: [Factor] = []
        func add(_ area: Area, _ penalty: Int, _ summary: String.LocalizationValue, _ advice: String.LocalizationValue) {
            factors.append(Factor(area: area, penalty: penalty, summary: String(localized: summary, bundle: .module),
                                  advice: String(localized: advice, bundle: .module)))
        }
        if let free = input.diskFreeFraction {
            let percent = Int((free * 100).rounded())
            if free < 0.05 { add(.disk, 30, "Startup disk is almost full (\(percent)% free)", "Run Smart Care, then look for big folders in Space Lens.") }
            else if free < 0.10 { add(.disk, 20, "Startup disk is low on space (\(percent)% free)", "Run Smart Care to free space.") }
            else if free < 0.15 { add(.disk, 10, "Startup disk is getting full (\(percent)% free)", "Clean up before macOS runs short of room.") }
        }
        switch input.memoryPressure {
        case .critical: add(.memory, 25, "Memory pressure is critical", "Quit apps you're not using.")
        case .warning: add(.memory, 10, "Memory is under pressure", "Quit a heavy app or browser tabs.")
        default:
            if let swap = input.swapUsedBytes, swap > 4_000_000_000 {
                add(.memory, 5, "Heavy swap use", "Restarting apps that have run for days frees swap.")
            }
        }
        if let cpu = input.averageCPU {
            if cpu > 0.8 { add(.cpu, 15, "CPU has been busy for a while", "Check the top processes below.") }
            else if cpu > 0.5 { add(.cpu, 5, "CPU is fairly busy", "Check the top processes below.") }
        }
        switch input.thermal {
        case .critical: add(.thermal, 25, "Your Mac is very hot", "Let it cool down and close heavy apps.")
        case .serious: add(.thermal, 15, "Your Mac is running hot", "Close heavy apps and keep the vents clear.")
        case .fair: add(.thermal, 5, "Your Mac is warm", "Nothing to do unless it stays warm.")
        default: break
        }
        if let health = input.batteryHealth, health < 0.8 {
            add(.battery, 10, "Battery holds \(Int((health * 100).rounded()))% of its original charge", "Apple recommends a battery service at this level.")
        }
        if let uptime = input.uptime, uptime > 14 * 86_400 {
            add(.uptime, 5, "Running for \(Int(uptime / 86_400)) days without a restart", "A restart applies updates and clears memory.")
        }
        factors.sort { $0.penalty > $1.penalty }
        self.factors = factors
        score = max(0, 100 - factors.reduce(0) { $0 + $1.penalty })
    }
}
