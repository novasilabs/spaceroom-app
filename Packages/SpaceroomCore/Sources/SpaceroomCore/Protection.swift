// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

// Protection: looks for the disguises malware uses to get opened — programs named like photos or
// documents, misleading file names, code hidden after an image, PDFs that run scripts, unsigned
// apps whose download flag was removed. It reads headers and tails only; it never runs anything.
// It is not an antivirus: it has no signature database and can't know every threat.

public enum ThreatKind: String, Codable, Sendable, CaseIterable {
    /// A program or script whose extension claims it's a photo, document or media file.
    case disguisedProgram
    /// A name built to mislead: "invoice.pdf.app", hidden right-to-left characters, padded spaces.
    case deceptiveName
    /// Code or an archive appended after the end of an image.
    case hiddenPayload
    /// A PDF that runs JavaScript or launches something when opened.
    case activePDF
    /// An app that isn't properly signed, outside the Applications folder.
    case unsignedApp
    /// A program hidden behind a dot-name in a personal folder.
    case hiddenProgram
    /// A script file downloaded from the internet; opening it runs commands.
    case downloadedScript
}

public enum ThreatSeverity: Int, Codable, Sendable, Comparable {
    case low, medium, high
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct ThreatFinding: Identifiable, Hashable, Sendable {
    public var id: String { "\(kind.rawValue):\(url.path)" }
    public let url: URL
    public let kind: ThreatKind
    public let severity: ThreatSeverity
    /// Technical evidence, e.g. "Starts like a Mac program (Mach-O)".
    public let evidence: String
    public let size: Int64
    public let isDirectory: Bool
    /// Has macOS's "downloaded from the internet" flag.
    public let isFromInternet: Bool

    public init(url: URL, kind: ThreatKind, severity: ThreatSeverity, evidence: String, size: Int64,
                isDirectory: Bool = false, isFromInternet: Bool = false) {
        self.url = url
        self.kind = kind
        self.severity = severity
        self.evidence = evidence
        self.size = size
        self.isDirectory = isDirectory
        self.isFromInternet = isFromInternet
    }
}

public struct ProtectionReport: Sendable {
    public let findings: [ThreatFinding]
    public let scannedFiles: Int
    /// Folders macOS didn't let us read.
    public let lockedRoots: [URL]
    /// The file limit was reached before everything was checked.
    public let wasTruncated: Bool
    public let wasCancelled: Bool
    public let finishedAt: Date
}

/// What a file's first bytes say it really is.
public enum DetectedType: Sendable, Equatable {
    case machO, script, compiledAppleScript, elf, windowsProgram, zip, jpeg, png, gif, pdf, other

    public var isProgram: Bool { [.machO, .script, .compiledAppleScript, .elf].contains(self) }

    public var label: String {
        switch self {
        case .machO: String(localized: "a Mac program (Mach-O)", bundle: .module)
        case .script: String(localized: "a shell script (#!)", bundle: .module)
        case .compiledAppleScript: String(localized: "a compiled AppleScript", bundle: .module)
        case .elf: String(localized: "a Linux program (ELF)", bundle: .module)
        case .windowsProgram: String(localized: "a Windows program", bundle: .module)
        case .zip: String(localized: "a zip archive", bundle: .module)
        case .jpeg: String(localized: "a JPEG image", bundle: .module)
        case .png: String(localized: "a PNG image", bundle: .module)
        case .gif: String(localized: "a GIF image", bundle: .module)
        case .pdf: String(localized: "a PDF", bundle: .module)
        case .other: String(localized: "unknown data", bundle: .module)
        }
    }
}

public struct ProtectionScanner: Sendable {
    public var maxDepth = 6
    public var maxFiles = 150_000
    /// Files above this size are only checked by name.
    public var maxInspectedSize: Int64 = 80_000_000

    public init() {}

    /// Personal folders where downloaded and received files land.
    public static func defaultRoots(home: URL) -> [URL] {
        ["Downloads", "Desktop", "Documents", "Applications", "Library/Mobile Documents/com~apple~CloudDocs"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            + [URL(fileURLWithPath: "/Users/Shared", isDirectory: true)]
    }

    /// Folders that are big, rebuilt by tools, and never where a disguised download hides.
    static let skippedFolders: Set<String> = ["node_modules", ".git", ".svn", ".hg", "DerivedData", "Pods", ".build",
                                              "build", ".venv", "venv", "__pycache__", ".Trash", "Photos Library.photoslibrary"]

    public func scan(_ roots: [URL], isCancelled: @Sendable () -> Bool = { false },
                     progress: @Sendable (Int) -> Void = { _ in }) -> ProtectionReport {
        var findings: [ThreatFinding] = []
        var locked: [URL] = []
        var scanned = 0
        var truncated = false
        var cancelled = false
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey]

        rootLoop: for root in roots {
            guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else {
                if FileManager.default.fileExists(atPath: root.path) { locked.append(root) }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { cancelled = true; break rootLoop }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                let name = url.lastPathComponent
                if values.isDirectory == true && values.isPackage != true {
                    if Self.skippedFolders.contains(name) || enumerator.level >= maxDepth { enumerator.skipDescendants() }
                    // Names alone can deceive even on folders that pose as files.
                    if let finding = Self.nameFinding(url, size: 0, isDirectory: true) { findings.append(finding) }
                    continue
                }
                scanned += 1
                if scanned % 500 == 0 { progress(scanned) }
                if scanned >= maxFiles { truncated = true; break rootLoop }

                if values.isPackage == true {
                    findings += inspectBundle(url)
                } else if values.isRegularFile == true {
                    findings += inspectFile(url, size: Int64(values.fileSize ?? 0))
                }
            }
        }
        progress(scanned)
        let sorted = findings.sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.url.path < $1.url.path }
        return ProtectionReport(findings: sorted, scannedFiles: scanned, lockedRoots: locked,
                                wasTruncated: truncated, wasCancelled: cancelled, finishedAt: .now)
    }

    // MARK: Files

    static let documentExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tif", "tiff", "svg",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "csv", "odt",
        "mp3", "mp4", "m4a", "mov", "avi", "mkv", "wav",
    ]
    static let runnableExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "sh", "scpt", "scptd", "applescript", "workflow", "pkg", "mpkg", "jar", "dmg", "iso",
    ]
    static let scriptExtensions: Set<String> = ["command", "tool", "terminal", "scpt", "scptd", "applescript", "sh", "workflow"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif"]

    /// Checks one regular file. Reads at most a small header and tail (whole PDFs only when small).
    public func inspectFile(_ url: URL, size: Int64) -> [ThreatFinding] {
        var findings: [ThreatFinding] = []
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let fromInternet = Self.isFromInternet(url)
        if let finding = Self.nameFinding(url, size: size, isDirectory: false) { findings.append(finding) }

        let needsHeader = Self.documentExtensions.contains(ext) || name.hasPrefix(".")
        guard needsHeader, size > 0, size <= maxInspectedSize, let header = Self.read(url, range: .head(64)) else {
            if Self.scriptExtensions.contains(ext) && fromInternet {
                findings.append(ThreatFinding(url: url, kind: .downloadedScript, severity: .low,
                                              evidence: String(localized: "A .\(ext) file downloaded from the internet", bundle: .module), size: size,
                                              isFromInternet: true))
            }
            return findings
        }
        let detected = Self.detect(header)

        if Self.documentExtensions.contains(ext) && detected.isProgram {
            // A shebang in a text file only runs from Terminal; it matters when it's also executable.
            let isScriptText = detected == .script && ["txt", "csv", "rtf"].contains(ext)
            if !isScriptText || Self.isExecutable(url) {
                findings.append(ThreatFinding(url: url, kind: .disguisedProgram, severity: isScriptText ? .medium : .high,
                                              evidence: String(localized: "Named .\(ext) but it is \(detected.label)", bundle: .module), size: size,
                                              isFromInternet: fromInternet))
            }
        } else if name.hasPrefix(".") && [.machO, .elf, .compiledAppleScript].contains(detected) {
            findings.append(ThreatFinding(url: url, kind: .hiddenProgram, severity: .medium,
                                          evidence: String(localized: "A hidden file that is \(detected.label)", bundle: .module), size: size, isFromInternet: fromInternet))
        }

        if Self.imageExtensions.contains(ext), [.jpeg, .png, .gif].contains(detected),
           let tail = Self.read(url, range: .tail(256 * 1024)),
           let payload = Self.appendedPayload(tail, type: detected) {
            findings.append(ThreatFinding(url: url, kind: .hiddenPayload, severity: payload.isProgram ? .high : .medium,
                                          evidence: String(localized: "Hidden after the end of the image: \(payload.label)", bundle: .module),
                                          size: size, isFromInternet: fromInternet))
        }

        if ext == "pdf", detected == .pdf, let active = Self.activePDF(url, size: size) {
            findings.append(ThreatFinding(url: url, kind: .activePDF, severity: active.launches ? .high : .medium,
                                          evidence: active.evidence, size: size, isFromInternet: fromInternet))
        }
        return findings
    }

    /// Checks an app or other bundle in a personal folder.
    public func inspectBundle(_ url: URL) -> [ThreatFinding] {
        var findings: [ThreatFinding] = []
        if let finding = Self.nameFinding(url, size: 0, isDirectory: true) { findings.append(finding) }
        guard url.pathExtension.lowercased() == "app" else { return findings }
        let fromInternet = Self.isFromInternet(url)
        let evidence: String? = switch CodeSignature.status(of: url.path) {
        case .apple, .developer: nil
        case .adHoc: String(localized: "Signed only ad hoc, so nobody vouches for who made it", bundle: .module)
        case .unsigned: String(localized: "Not signed at all", bundle: .module)
        case .invalid: String(localized: "Its signature is broken: the app was changed after it was signed", bundle: .module)
        }
        if let evidence {
            let note = fromInternet ? "" : String(localized: ". Its download flag is missing, so macOS never checked it", bundle: .module)
            findings.append(ThreatFinding(url: url, kind: .unsignedApp, severity: fromInternet ? .low : .medium,
                                          evidence: evidence + note, size: DiskUsage.size(of: url),
                                          isDirectory: true, isFromInternet: fromInternet))
        }
        return findings
    }

    // MARK: Names

    /// Characters that make a name display differently from what it is.
    static let bidiControls: Set<Unicode.Scalar> = ["\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                                                    "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{200E}", "\u{200F}"]

    static func nameFinding(_ url: URL, size: Int64, isDirectory: Bool) -> ThreatFinding? {
        guard let evidence = deceptiveName(url.lastPathComponent) else { return nil }
        return ThreatFinding(url: url, kind: .deceptiveName, severity: .high, evidence: evidence, size: size,
                             isDirectory: isDirectory, isFromInternet: isFromInternet(url))
    }

    /// Why a name is misleading, or `nil` if it looks honest.
    public static func deceptiveName(_ name: String) -> String? {
        if name.unicodeScalars.contains(where: bidiControls.contains) {
            return String(localized: "The name contains hidden characters that reverse how it's displayed", bundle: .module)
        }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let last = parts[parts.count - 1].lowercased()
        guard runnableExtensions.contains(last) else { return nil }
        let previous = parts[parts.count - 2]
        if previous.hasSuffix("   ") || previous.hasSuffix("\u{00A0}\u{00A0}") {
            return String(localized: "Spaces hide the real .\(last) ending", bundle: .module)
        }
        let claimed = previous.trimmingCharacters(in: .whitespaces).lowercased()
        if documentExtensions.contains(claimed) {
            return String(localized: "Looks like a .\(claimed) file but is really a .\(last)", bundle: .module)
        }
        return nil
    }

    // MARK: Content

    public static func detect(_ header: Data) -> DetectedType {
        let bytes = [UInt8](header.prefix(16))
        func starts(_ prefix: [UInt8]) -> Bool { bytes.starts(with: prefix) }
        if starts([0xCF, 0xFA, 0xED, 0xFE]) || starts([0xCE, 0xFA, 0xED, 0xFE])
            || starts([0xFE, 0xED, 0xFA, 0xCF]) || starts([0xFE, 0xED, 0xFA, 0xCE]) { return .machO }
        // Universal binaries share CAFEBABE with Java classes; the second word tells them apart.
        if starts([0xCA, 0xFE, 0xBA, 0xBE]), bytes.count >= 8,
           (UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])) < 40 { return .machO }
        if starts(Array("#!".utf8)) { return .script }
        if starts(Array("FasdUAS".utf8)) { return .compiledAppleScript }
        if starts([0x7F, 0x45, 0x4C, 0x46]) { return .elf }
        if starts([0x4D, 0x5A]) { return .windowsProgram }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return .zip }
        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return .png }
        if starts(Array("GIF8".utf8)) { return .gif }
        if starts(Array("%PDF".utf8)) { return .pdf }
        return .other
    }

    /// What sits after an image's end marker, when it's code or an archive (not padding or a second photo).
    static func appendedPayload(_ tail: Data, type: DetectedType) -> DetectedType? {
        let bytes = [UInt8](tail)
        let end: Int?
        switch type {
        case .jpeg:
            end = lastIndex(of: [0xFF, 0xD9], in: bytes).map { $0 + 2 }
        case .png:
            end = lastIndex(of: Array("IEND".utf8), in: bytes).map { $0 + 8 }
        default:
            end = nil
        }
        if let end, end < bytes.count {
            let trailing = Data(bytes[end...])
            let kind = detect(trailing)
            if kind.isProgram || kind == .zip || kind == .windowsProgram { return kind }
        }
        // An image that is also a zip (zip directories live at the end): a classic polyglot.
        if lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: bytes) != nil { return .zip }
        return nil
    }

    struct ActivePDF {
        let javaScript: Bool
        let launches: Bool
        let runsOnOpen: Bool

        var evidence: String {
            switch (javaScript, launches, runsOnOpen) {
            case (true, true, true): String(localized: "Contains JavaScript and an action that launches a program, run when it opens", bundle: .module)
            case (true, true, false): String(localized: "Contains JavaScript and an action that launches a program", bundle: .module)
            case (true, false, true): String(localized: "Contains JavaScript that runs when it opens", bundle: .module)
            case (true, false, false): String(localized: "Contains JavaScript", bundle: .module)
            case (false, _, true): String(localized: "Contains an action that launches a program when it opens", bundle: .module)
            case (false, _, false): String(localized: "Contains an action that launches a program", bundle: .module)
            }
        }
    }

    static func activePDF(_ url: URL, size: Int64) -> ActivePDF? {
        // Look at the whole file when it's small, else its start and end, where actions usually sit.
        let data: Data? = size <= 8_000_000
            ? read(url, range: .head(Int(size)))
            : [read(url, range: .head(2_000_000)), read(url, range: .tail(2_000_000))].compactMap { $0 }.reduce(Data(), +)
        guard let data else { return nil }
        func has(_ token: String) -> Bool { data.range(of: Data(token.utf8)) != nil }
        let javaScript = has("/JavaScript") || has("/JS ") || has("/JS(") || has("/JS<")
        let launches = has("/Launch")
        guard javaScript || launches else { return nil }
        return ActivePDF(javaScript: javaScript, launches: launches, runsOnOpen: has("/OpenAction") || has("/AA"))
    }

    // MARK: Helpers

    enum ReadRange { case head(Int), tail(Int) }

    static func read(_ url: URL, range: ReadRange) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        switch range {
        case .head(let count):
            return try? handle.read(upToCount: count)
        case .tail(let count):
            guard let end = try? handle.seekToEnd() else { return nil }
            try? handle.seek(toOffset: end > UInt64(count) ? end - UInt64(count) : 0)
            return try? handle.readToEnd()
        }
    }

    static func lastIndex(of needle: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= needle.count else { return nil }
        var index = bytes.count - needle.count
        while index >= 0 {
            if bytes[index] == needle[0] && Array(bytes[index..<(index + needle.count)]) == needle { return index }
            index -= 1
        }
        return nil
    }

    /// macOS adds `com.apple.quarantine` to files downloaded by browsers, Mail and messaging apps.
    public static func isFromInternet(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}

/// Moves findings into the Restore Center (module "protection"), re-checking each one first.
public struct ThreatRemover: Sendable {
    public let store: RestoreStore
    public let home: URL

    public init(store: RestoreStore, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.store = store
        self.home = home
    }

    public func remove(_ findings: [ThreatFinding], running: RunningProcesses = .current(),
                       now: Date = .now) async throws -> CleanOutcome {
        let guardrail = SafetyGuard(home: home)
        let realHome = SafetyGuard.realPath(home)
        let shared = SafetyGuard.realPath(URL(fileURLWithPath: "/Users/Shared"))
        var moves: [PlannedMove] = []
        var skipped: [SkippedItem] = []
        var seen: Set<String> = []
        for finding in findings where seen.insert(finding.url.path).inserted {
            let url = finding.url
            let real = SafetyGuard.realPath(url)
            let mode = FileStat.lstatInfo(url).map { $0.st_mode & S_IFMT }
            let isAllowedType = finding.isDirectory ? mode == S_IFDIR : mode == S_IFREG
            // Personal folders only (iCloud Drive included); never the rest of ~/Library or the system.
            let isInside = (real.hasPrefix(realHome + "/") && !real.hasPrefix(realHome + "/Library/"))
                || real.hasPrefix(realHome + "/Library/Mobile Documents/") || real.hasPrefix(shared + "/")
            if !FileStat.exists(url) {
                skipped.append(SkippedItem(path: url.path, size: finding.size, reason: .missing))
            } else if !isInside || !isAllowedType {
                skipped.append(SkippedItem(path: url.path, size: finding.size, reason: .protectedPath))
            } else if let reason = guardrail.check(url, root: url.deletingLastPathComponent()) {
                skipped.append(SkippedItem(path: url.path, size: finding.size, reason: reason))
            } else if let name = running.program(inside: url) {
                // Moving a running program wouldn't stop it; it has to be quit first.
                skipped.append(SkippedItem(path: url.path, size: finding.size, reason: .running(name: name)))
            } else {
                moves.append(PlannedMove(url: url, ruleID: "protection." + finding.kind.rawValue, size: finding.size,
                                         isDirectory: finding.isDirectory))
            }
        }
        guard !moves.isEmpty else { return CleanOutcome(operation: nil, skipped: skipped) }
        let (record, failures) = try await store.quarantine(moves, module: "protection", now: now)
        let sizes = Dictionary(moves.map { ($0.url.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        return CleanOutcome(operation: record,
                            skipped: skipped + failures.map { SkippedItem(path: $0.path, size: sizes[$0.path] ?? 0, reason: $0.reason) })
    }
}
