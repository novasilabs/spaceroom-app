// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Docker")
struct DockerTests {
    /// A stand-in `docker` that answers like the real one and logs every call.
    private func fakeDocker(in box: Sandbox, running: Bool = true) throws -> (Docker, URL) {
        let script = box.home.appendingPathComponent("bin/docker")
        let log = box.home.appendingPathComponent("calls.log")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = """
        #!/bin/sh
        echo "$*" >> '\(log.path)'
        case "$1 $2" in
          "version --format") \(running ? "echo 27.3.1" : "echo 'Cannot connect' >&2; exit 1") ;;
          "system df")
            echo '{"Active":"2","Reclaimable":"1.5GB (40%)","Size":"3.8GB","TotalCount":"9","Type":"Images"}'
            echo '{"Active":"1","Reclaimable":"0B","Size":"12MB","TotalCount":"1","Type":"Containers"}'
            echo '{"Active":"1","Reclaimable":"0B","Size":"2.1GB","TotalCount":"3","Type":"Local Volumes"}'
            echo '{"Active":"0","Reclaimable":"2.4GB","Size":"2.4GB","TotalCount":"40","Type":"Build Cache"}' ;;
          "images --filter") echo "300MB"; echo "1.2GB" ;;
          "builder prune") echo "Deleted build cache objects:"; echo "abc"; echo "Total:	2.4GB" ;;
          "image prune") echo "Deleted Images:"; echo "Total reclaimed space: 1.5GB" ;;
          *) exit 2 ;;
        esac
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (Docker(executable: script), log)
    }

    @Test("Reports only regenerable data as reclaimable")
    func usage() throws {
        let box = try Sandbox()
        let (docker, _) = try fakeDocker(in: box)
        guard case .ready(let usage) = docker.status() else { Issue.record("not ready"); return }
        #expect(usage.buildCache == 2_400_000_000)
        #expect(usage.danglingImages == 1_500_000_000)
        #expect(usage.danglingImageCount == 2)
        #expect(usage.imagesTotal == 3_800_000_000)
        #expect(usage.volumesTotal == 2_100_000_000)
        #expect(usage.reclaimable == 3_900_000_000)
    }

    @Test("Not running and not installed are told apart; the engine is never started")
    func states() throws {
        let box = try Sandbox()
        let (stopped, log) = try fakeDocker(in: box, running: false)
        #expect(stopped.status() == .notRunning)
        #expect(try String(contentsOf: log, encoding: .utf8) == "version --format {{.Server.Version}}\n")
        #expect(Docker(executable: nil).status() == .notInstalled)
    }

    @Test("Prune runs only builder prune and image prune, never -a, volumes or containers")
    func prune() throws {
        let box = try Sandbox()
        let (docker, log) = try fakeDocker(in: box)
        let result = docker.prune(buildCache: true, danglingImages: true)
        #expect(result.reclaimed == 3_900_000_000)
        #expect(result.failures.isEmpty)
        let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(calls == ["builder prune --all --force", "image prune --force"])

        try Data().write(to: log)
        _ = docker.prune(buildCache: false, danglingImages: true)
        #expect(try String(contentsOf: log, encoding: .utf8) == "image prune --force\n")
    }

    @Test("Sizes in Docker's units", arguments: [
        ("1.2GB", Int64(1_200_000_000)), ("512MB", 512_000_000), ("0B", 0), ("12.3kB", 12_300),
        ("2.4GB (40%)", 2_400_000_000), ("1GiB", 1_073_741_824), ("junk", 0),
    ])
    func sizes(text: String, bytes: Int64) {
        #expect(Docker.bytes(text) == bytes)
    }

    @Test("A tool that hangs is stopped at the time limit")
    func timeout() throws {
        let started = Date.now
        #expect(Tool.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: 0.5) == nil)
        #expect(Date.now.timeIntervalSince(started) < 5)
    }
}
