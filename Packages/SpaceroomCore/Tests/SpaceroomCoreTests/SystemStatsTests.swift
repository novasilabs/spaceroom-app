// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("System stats")
struct SystemStatsTests {
    @Test("Storage level thresholds", arguments: [
        (0.50, StorageLevel.ok), (0.15, .ok), (0.149, .low), (0.05, .low), (0.049, .critical), (0, .critical),
    ])
    func storageLevels(free: Double, expected: StorageLevel) {
        #expect(StorageLevel(freeFraction: free) == expected)
    }

    @Test func volumeMath() {
        let v = VolumeInfo(url: URL(fileURLWithPath: "/"), name: "HD", totalBytes: 1000, availableBytes: 300,
                           immediatelyFreeBytes: 200, isRoot: true, isInternal: true, isEjectable: false)
        #expect(v.usedBytes == 700)
        #expect(v.purgeableBytes == 100)
        #expect(v.freeFraction == 0.3)
        #expect(v.level == .ok)
    }

    @Test func startupDiskIsReadable() throws {
        let root = try #require(Volumes.root())
        #expect(root.isRoot)
        #expect(root.totalBytes > 0)
        #expect(root.availableBytes > 0 && root.availableBytes <= root.totalBytes)
        #expect(Volumes.mounted().first?.isRoot == true)
    }

    @Test func cpuSamplerNeedsTwoSamples() async throws {
        var sampler = CPUSampler()
        #expect(sampler.sample() == nil)
        try await Task.sleep(for: .milliseconds(200))
        let second = sampler.sample()
        let usage = try #require(second)
        #expect((0...1).contains(usage))
    }

    @Test func memorySnapshotIsSane() throws {
        let memory = try #require(MemorySnapshot.current())
        #expect(memory.totalBytes > 0)
        #expect(memory.usedBytes > 0 && memory.usedBytes <= memory.totalBytes)
    }
}
