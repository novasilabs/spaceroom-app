// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

// MARK: - Volumes

/// A mounted volume and how much room is left on it.
public struct VolumeInfo: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let totalBytes: Int64
    /// Free space as Finder reports it: includes purgeable space macOS frees on demand.
    public let availableBytes: Int64
    /// Space that is free right now, without purging anything.
    public let immediatelyFreeBytes: Int64
    public let isRoot: Bool
    public let isInternal: Bool
    public let isEjectable: Bool

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    /// Purgeable space (local snapshots, iCloud-optimised files, caches macOS manages).
    public var purgeableBytes: Int64 { max(0, availableBytes - immediatelyFreeBytes) }
    public var freeFraction: Double { totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 0 }
    public var usedFraction: Double { 1 - freeFraction }
    public var level: StorageLevel { StorageLevel(freeFraction: freeFraction) }

    public init(url: URL, name: String, totalBytes: Int64, availableBytes: Int64, immediatelyFreeBytes: Int64,
                isRoot: Bool, isInternal: Bool, isEjectable: Bool) {
        self.url = url
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.immediatelyFreeBytes = immediatelyFreeBytes
        self.isRoot = isRoot
        self.isInternal = isInternal
        self.isEjectable = isEjectable
    }
}

/// Colour state of the storage indicator.
public enum StorageLevel: Sendable, Comparable {
    case ok
    /// Below 15 % free.
    case low
    /// Below 5 % free.
    case critical

    public init(freeFraction: Double) {
        switch freeFraction {
        case ..<0.05: self = .critical
        case ..<0.15: self = .low
        default: self = .ok
        }
    }
}

public enum Volumes {
    static let keys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsRootFileSystemKey,
        .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsBrowsableKey,
    ]

    /// Browsable mounted volumes, startup disk first.
    public static func mounted() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(info(for:)).sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The startup disk.
    public static func root() -> VolumeInfo? {
        info(for: URL(fileURLWithPath: "/"))
    }

    public static func info(for url: URL) -> VolumeInfo? {
        guard let v = try? url.resourceValues(forKeys: Set(keys)),
              v.volumeIsBrowsable != false,
              let total = v.volumeTotalCapacity, total > 0 else { return nil }
        let free = Int64(v.volumeAvailableCapacity ?? 0)
        let important = v.volumeAvailableCapacityForImportantUsage ?? Int64(free)
        return VolumeInfo(
            url: url,
            name: v.volumeLocalizedName ?? url.lastPathComponent,
            totalBytes: Int64(total),
            availableBytes: max(important, free),
            immediatelyFreeBytes: free,
            isRoot: v.volumeIsRootFileSystem ?? false,
            isInternal: v.volumeIsInternal ?? false,
            isEjectable: v.volumeIsEjectable ?? false
        )
    }
}

// MARK: - CPU

/// Measures total CPU usage between two calls (like Activity Monitor's CPU graph).
public struct CPUSampler: Sendable {
    private var previous: [CoreTicks]?
    /// Separate state for `samplePerCore()` so both samplers can be used independently.
    var previousCores: [CoreTicks]?

    struct CoreTicks: Sendable {
        var busy: UInt32
        var total: UInt32
    }

    public init() {}

    /// Usage 0…1 since the previous call. The first call only primes the sampler and returns `nil`.
    public mutating func sample() -> Double? {
        guard let current = Self.readTicks() else { return nil }
        defer { previous = current }
        guard let previous, previous.count == current.count else { return nil }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for (old, new) in zip(previous, current) {
            busy += UInt64(new.busy &- old.busy)
            total += UInt64(new.total &- old.total)
        }
        return total == 0 ? 0 : min(1, Double(busy) / Double(total))
    }

    static func readTicks() -> [CoreTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(SystemHost.port, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(SystemHost.task, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { cpu in
            func tick(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[cpu * states + Int(state)]) }
            let busy = tick(CPU_STATE_USER) &+ tick(CPU_STATE_SYSTEM) &+ tick(CPU_STATE_NICE)
            return CoreTicks(busy: busy, total: busy &+ tick(CPU_STATE_IDLE))
        }
    }
}

// MARK: - Memory

public struct MemorySnapshot: Sendable, Hashable {
    public enum Pressure: Sendable, Hashable { case normal, warning, critical }

    public let totalBytes: Int64
    /// "Memory Used" as Activity Monitor defines it: app memory + wired + compressed.
    public let usedBytes: Int64
    public let pressure: Pressure

    public var usedFraction: Double { totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0 }

    public static func current() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(SystemHost.port, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Int64(getpagesize())
        let appPages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let used = (max(0, appPages) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        return MemorySnapshot(totalBytes: total, usedBytes: min(used, total), pressure: currentPressure())
    }

    static func currentPressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

enum SystemHost {
    /// Cached host port (each `mach_host_self()` call adds a port reference).
    static let port: mach_port_t = mach_host_self()
    /// Same port as `mach_task_self()`, which Swift 6 can't read from the C global safely.
    static let task: mach_port_t = task_self_trap()
}
