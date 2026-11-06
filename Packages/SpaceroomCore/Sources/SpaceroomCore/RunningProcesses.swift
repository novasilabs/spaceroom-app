// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// What is running right now, by executable path. Removers use it so that nothing is moved out
/// from under a running program: the process would keep running (and an app could still be
/// open) even though its files were "removed".
public struct RunningProcesses: Sendable {
    /// Real paths of running executables, e.g. ".../Foo.app/Contents/MacOS/Foo".
    public let executablePaths: [String]

    public init(executablePaths: [String]) {
        self.executablePaths = executablePaths.map { SafetyGuard.realPath(URL(fileURLWithPath: $0)) }
    }

    /// Every process this user can see (others' paths may be unreadable and are skipped).
    public static func current() -> RunningProcesses {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return RunningProcesses(executablePaths: []) }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var paths: [String] = []
        for pid in pids.prefix(Int(max(0, found))) where pid > 0 {
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 { paths.append(String(cString: buffer)) }
        }
        return RunningProcesses(executablePaths: paths)
    }

    /// The running program at or inside `url` (an app bundle, a folder or an executable), if any.
    /// Returns a name to show: the app's name for bundles, else the executable's.
    public func program(inside url: URL) -> String? {
        let root = SafetyGuard.realPath(url)
        guard let path = executablePaths.first(where: { $0 == root || $0.hasPrefix(root + "/") }) else { return nil }
        if let range = path.range(of: ".app/", options: .backwards) {
            return URL(fileURLWithPath: String(path[..<range.lowerBound])).lastPathComponent
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
