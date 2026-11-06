// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Docker's disk use, as Docker reports it.
public struct DockerUsage: Sendable, Equatable {
    /// Build cache Docker could remove (`docker builder prune`).
    public var buildCache: Int64
    /// Untagged images left behind by rebuilds (`docker image prune`, without `-a`). An upper
    /// bound: layers they share with tagged images stay.
    public var danglingImages: Int64
    public var danglingImageCount: Int
    /// Everything else, for context only. Never offered: tagged images may exist nowhere else,
    /// and volumes and containers hold data.
    public var imagesTotal: Int64
    public var volumesTotal: Int64

    public init(buildCache: Int64 = 0, danglingImages: Int64 = 0, danglingImageCount: Int = 0,
                imagesTotal: Int64 = 0, volumesTotal: Int64 = 0) {
        self.buildCache = buildCache
        self.danglingImages = danglingImages
        self.danglingImageCount = danglingImageCount
        self.imagesTotal = imagesTotal
        self.volumesTotal = volumesTotal
    }

    public var reclaimable: Int64 { buildCache + danglingImages }
}

public enum DockerStatus: Sendable, Equatable {
    case notInstalled
    /// The command-line tool exists but the engine isn't running. Spaceroom never starts it.
    case notRunning
    case ready(DockerUsage)
}

public struct DockerPruneResult: Sendable, Equatable {
    /// What Docker says it freed.
    public var reclaimed: Int64
    /// Steps that failed, with Docker's message.
    public var failures: [String]
}

/// Talks to Docker (Docker Desktop, OrbStack, Colima, Rancher Desktop, …) through its
/// command-line tool. Removing data is left to Docker itself, so it is **not** restorable from
/// the Restore Center. The app says so before anything runs. Only regenerable data is offered.
public struct Docker: Sendable {
    public let executable: URL?

    public init(executable: URL? = Docker.find()) {
        self.executable = executable
    }

    /// Where Docker-compatible tools put `docker`. Apps don't inherit the shell's PATH.
    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            "/usr/local/bin/docker", "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            home.path + "/.docker/bin/docker", home.path + "/.orbstack/bin/docker", home.path + "/.rd/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    public func status() -> DockerStatus {
        guard let executable else { return .notInstalled }
        guard let version = Tool.run(executable, ["version", "--format", "{{.Server.Version}}"], timeout: 10),
              version.status == 0, !version.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .notRunning
        }
        var usage = DockerUsage()
        if let df = Tool.run(executable, ["system", "df", "--format", "{{json .}}"], timeout: 30), df.status == 0 {
            for line in df.output.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = row["Type"] as? String else { continue }
                let size = Self.bytes(row["Size"] as? String ?? "")
                switch type {
                case "Images": usage.imagesTotal = size
                case "Local Volumes": usage.volumesTotal = size
                case "Build Cache": usage.buildCache = Self.bytes(row["Reclaimable"] as? String ?? "")
                default: break
                }
            }
        }
        if let images = Tool.run(executable, ["images", "--filter", "dangling=true", "--format", "{{.Size}}"], timeout: 30),
           images.status == 0 {
            let sizes = images.output.split(separator: "\n").map { Self.bytes(String($0)) }
            usage.danglingImageCount = sizes.count
            usage.danglingImages = sizes.reduce(0, +)
        }
        return .ready(usage)
    }

    /// Asks Docker to remove its build cache and/or dangling images. Never `-a`, never volumes
    /// or containers.
    public func prune(buildCache: Bool, danglingImages: Bool) -> DockerPruneResult {
        var result = DockerPruneResult(reclaimed: 0, failures: [])
        guard let executable else { return result }
        var steps: [[String]] = []
        // --all: every unused build cache entry, which is what `system df` reports as reclaimable
        // (plain prune only removes dangling entries, so the card would promise more than it frees).
        if buildCache { steps.append(["builder", "prune", "--all", "--force"]) }
        if danglingImages { steps.append(["image", "prune", "--force"]) }
        for arguments in steps {
            guard let run = Tool.run(executable, arguments, timeout: 900), run.status == 0 else {
                result.failures.append(arguments.prefix(2).joined(separator: " "))
                continue
            }
            result.reclaimed += Self.reclaimed(in: run.output)
        }
        return result
    }

    /// "Total reclaimed space: 1.21GB" (or "Total: 1.2GB" from older builders).
    static func reclaimed(in output: String) -> Int64 {
        for line in output.split(separator: "\n").reversed() where line.lowercased().hasPrefix("total") {
            if let value = line.split(separator: ":").last { return bytes(String(value)) }
        }
        return 0
    }

    /// Parses Docker's human sizes ("1.2GB", "512MB", "0B", "12.3kB"). Docker counts in powers
    /// of 1000, except `KiB`-style units, which are powers of 1024.
    static func bytes(_ text: String) -> Int64 {
        var string = text.trimmingCharacters(in: .whitespaces)
        if let paren = string.firstIndex(of: "(") { string = String(string[..<paren]).trimmingCharacters(in: .whitespaces) }
        let number = string.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(number) else { return 0 }
        let unit = string.dropFirst(number.count).trimmingCharacters(in: .whitespaces).lowercased()
        let scale: Double = switch unit {
        case "", "b": 1
        case "kb", "k": 1e3
        case "mb", "m": 1e6
        case "gb", "g": 1e9
        case "tb", "t": 1e12
        case "kib": 1024
        case "mib": 1_048_576
        case "gib": 1_073_741_824
        case "tib": 1_099_511_627_776
        default: 0
        }
        return Int64(value * scale)
    }
}

/// Runs a command-line tool with a time limit and collects its output.
///
/// Output goes to a temporary file rather than a pipe: a pipe only reaches end-of-file once every
/// process holding its write end has exited, and children started at the same moment elsewhere in
/// the app can inherit it. A file can be read as soon as the tool itself is done.
enum Tool {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval,
                    environment: [String: String]? = nil) -> Result? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spaceroom-tool-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else { return nil }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
            return nil
        }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
