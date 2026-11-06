// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Finds build folders inside the user's projects (`node_modules`, Rust `target`, SwiftPM
/// `.build`, …) for project rules. Read-only, like the rest of the scanner.
///
/// - Searches the rule's folders a few levels deep. Never follows symlinks, never enters app
///   bundles, hidden folders, `~/Library` or build folders themselves.
/// - A folder counts only next to one of the rule's marker files (`package.json`, …).
/// - Folders that Git tracks are never offered (`.trackedByGit`). When the project is in a Git
///   repository and Git isn't installed, the folder is skipped rather than guessed.
/// - `min_age_days` counts from the project's last change, so active projects are left alone.
enum ProjectArtifactFinder {
    static let maxDepth = 6
    static let maxFolders = 80_000

    /// Never searched inside: other tools' folders and places that aren't projects.
    static let neverEnter: Set<String> = [
        "node_modules", "target", ".build", "build", "Pods", ".venv", "venv", ".gradle", "dist",
        ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", "DerivedData", "vendor",
        "Library", "Applications", ".Trash",
    ]

    struct Project {
        let url: URL
        let artifacts: [URL]
    }

    static func scan(_ rule: Rule, spec: ProjectArtifactSpec, context: ScanContext) -> RuleScanResult {
        let guardrail = SafetyGuard(home: context.home)
        let git = GitProbe.shared
        let ruleInUse = rule.skipIfRunning.first { context.runningBundleIDs.contains($0) }
        let running = RunningProcesses.current()
        var items: [ScanItem] = []
        for project in projects(in: searchRoots(rule, home: context.home), spec: spec) {
            if Task.isCancelled { break }
            let lastChange = lastChange(of: project.url, excluding: Set(spec.folders))
            let repository = GitProbe.repositoryRoot(containing: project.url, home: context.home)
            for url in project.artifacts {
                if Task.isCancelled { break }
                guard let m = FileStat.measure(url, isCancelled: { Task.isCancelled }), m.isDirectory else { continue }
                var reason: SkipReason? = context.ignore.ignoresItem(at: url) ? .ignored : nil
                if reason == nil { reason = guardrail.check(url, root: project.url) }
                if reason == nil, let app = ruleInUse { reason = .inUse(bundleID: app) }
                if reason == nil, let name = running.program(inside: url) { reason = .running(name: name) }
                if reason == nil, let repository {
                    switch git.isTracked(url, in: repository) {
                    case .some(true): reason = .trackedByGit(verified: true)
                    case .some(false): break
                    case .none: reason = .trackedByGit(verified: false)
                    }
                }
                if reason == nil, rule.minAgeDays > 0,
                   context.now.timeIntervalSince(lastChange) < TimeInterval(rule.minAgeDays) * 86_400 {
                    reason = .tooRecent(minAgeDays: rule.minAgeDays)
                }
                items.append(ScanItem(
                    url: url, ruleID: rule.id, root: project.url, size: m.allocatedSize, fileCount: m.fileCount,
                    lastModified: lastChange, isDirectory: true, identity: m.identity, skipReason: reason,
                    label: project.url.lastPathComponent + " › " + url.lastPathComponent))
            }
        }
        items.sort { $0.size > $1.size }
        return RuleScanResult(rule: rule, items: items)
    }

    /// Existing search folders, deduplicated after resolving symlinks (and case, on the usual
    /// case-insensitive volume, `~/Projects` and `~/projects` are the same folder).
    static func searchRoots(_ rule: Rule, home: URL) -> [URL] {
        var seen: Set<String> = []
        var roots: [URL] = []
        for raw in rule.paths where raw.hasPrefix("~/") {
            let url = home.appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let real = try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath,
                  seen.insert(real.lowercased()).inserted else { continue }
            roots.append(url)
        }
        // A root inside another root would be walked twice.
        return roots.filter { root in
            !roots.contains { other in other != root && root.path.hasPrefix(other.path + "/") }
        }
    }

    static func projects(in roots: [URL], spec: ProjectArtifactSpec) -> [Project] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        var queue: [(URL, Int)] = roots.map { ($0, 0) }
        var visited = 0
        var found: [Project] = []
        var seen: Set<String> = []
        while !queue.isEmpty, visited < maxFolders, !Task.isCancelled {
            let (folder, depth) = queue.removeFirst()
            visited += 1
            guard seen.insert(folder.path).inserted,
                  let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) else { continue }
            let names = Set(entries.map(\.lastPathComponent))
            let isProject = names.contains { name in spec.markers.contains { fnmatch($0, name, 0) == 0 } }
            var artifacts: [URL] = []
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: keys),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let name = entry.lastPathComponent
                if isProject, spec.folders.contains(name) {
                    artifacts.append(entry)
                    continue
                }
                guard depth < maxDepth, values.isPackage != true, !name.hasPrefix("."), !neverEnter.contains(name) else { continue }
                queue.append((entry, depth + 1))
            }
            if !artifacts.isEmpty {
                found.append(Project(url: folder, artifacts: artifacts.sorted { $0.path < $1.path }))
            }
        }
        return found
    }

    /// The newest change in the project's own files (a few levels deep), ignoring build
    /// folders, plus Git's index, which moves on every commit and checkout.
    static func lastChange(of project: URL, excluding artifacts: Set<String>) -> Date {
        let fm = FileManager.default
        var newest = Date.distantPast
        func consider(_ url: URL) {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               date > newest { newest = date }
        }
        consider(project.appendingPathComponent(".git/index"))
        consider(project.appendingPathComponent(".git/HEAD"))
        var queue: [(URL, Int)] = [(project, 0)]
        var checked = 0
        while !queue.isEmpty, checked < 4_000 {
            let (folder, depth) = queue.removeFirst()
            guard let entries = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]) else { continue }
            for entry in entries {
                checked += 1
                let name = entry.lastPathComponent
                if artifacts.contains(name) || neverEnter.contains(name) { continue }
                let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
                if let date = values?.contentModificationDate, date > newest { newest = date }
                if values?.isDirectory == true, values?.isSymbolicLink != true, depth < 3 { queue.append((entry, depth + 1)) }
            }
        }
        return newest
    }
}

/// Asks Git whether a folder holds tracked files. Uses the Git that comes with Xcode or the
/// command line tools (never `/usr/bin/git`, which would offer to install them), or Homebrew's.
final class GitProbe: Sendable {
    static let shared = GitProbe()

    let executable: URL?

    init(executable: URL? = GitProbe.findGit()) {
        self.executable = executable
    }

    static func findGit() -> URL? {
        var candidates: [String] = []
        if let developer = run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"])?.output
            .trimmingCharacters(in: .whitespacesAndNewlines), !developer.isEmpty {
            candidates.append(developer + "/usr/bin/git")
        }
        candidates += ["/Library/Developer/CommandLineTools/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// The nearest folder at or above `folder` (but inside the home folder) that has `.git`.
    static func repositoryRoot(containing folder: URL, home: URL) -> URL? {
        let homePath = SafetyGuard.realPath(home)
        var current = folder.standardizedFileURL
        while current.path.hasPrefix(homePath + "/") {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) { return current }
            current.deleteLastPathComponent()
        }
        return nil
    }

    /// `true` when Git tracks anything inside `url`, `false` when it tracks nothing there, and
    /// `nil` when that can't be known (no Git, or Git failed).
    func isTracked(_ url: URL, in repository: URL) -> Bool? {
        guard let executable,
              let result = Self.run(executable, ["-C", repository.path, "ls-files", "--cached", "-z", "--", url.path]),
              result.status == 0 else { return nil }
        return !result.output.isEmpty
    }

    /// Runs Git (or `xcode-select`) without ever letting it take locks in the repository.
    static func run(_ executable: URL, _ arguments: [String]) -> Tool.Result? {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        return Tool.run(executable, arguments, timeout: 30, environment: environment)
    }
}
