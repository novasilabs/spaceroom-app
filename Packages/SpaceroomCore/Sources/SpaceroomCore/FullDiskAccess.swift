// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Detects whether the app has Full Disk Access by probing files macOS protects with TCC.
public enum FullDiskAccess {
    public enum Status: Sendable, Equatable {
        case granted
        case denied
        /// None of the probe files exist, so we can't tell. Treated as "probably granted".
        case unknown
    }

    public static func status(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Status {
        let probes = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Containers/com.apple.stocks"),
            home.appendingPathComponent("Library/Mail"),
        ]
        var sawDenied = false
        for probe in probes {
            let fd = open(probe.path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return .granted
            }
            if errno == EPERM || errno == EACCES { sawDenied = true }
        }
        return sawDenied ? .denied : .unknown
    }

    /// Deep link to System Settings › Privacy & Security › Full Disk Access.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
