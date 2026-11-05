// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCLI
import SpaceroomCore

let appBundleIDs = ["com.novasilabs.spaceroom", "io.github.spaceroom-app.spaceroom"]

let environment = CLI.Environment(
    home: FileManager.default.homeDirectoryForCurrentUser,
    storeDirectory: RestoreStore.defaultDirectory,
    catalog: { try RuleCatalog.bundled() },
    runningBundleIDs: { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) },
    runningAppNames: {
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName { names.insert(name) }
            if let executable = app.executableURL?.lastPathComponent { names.insert(executable) }
            if let last = app.bundleIdentifier?.split(separator: ".").last, last.count > 3 { names.insert(String(last)) }
        }
        return names
    },
    isAppRunning: { appBundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } },
    isInteractive: isatty(STDIN_FILENO) != 0,
    readLine: { Swift.readLine() },
    write: { FileHandle.standardOutput.write(Data($0.utf8)) },
    writeError: { FileHandle.standardError.write(Data($0.utf8)) },
    retentionDays: {
        let stored = UserDefaults(suiteName: appBundleIDs[0])?.integer(forKey: "retentionDays") ?? 0
        return (1...30).contains(stored) ? stored : 7
    })

let code = await CLI(environment: environment).run(Array(CommandLine.arguments.dropFirst()))
exit(code.rawValue)
