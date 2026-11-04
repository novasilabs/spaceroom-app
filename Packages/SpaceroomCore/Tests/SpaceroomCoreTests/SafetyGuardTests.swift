// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Safety guard")
struct SafetyGuardTests {
    @Test func allowsDirectChildOfRoot() throws {
        let box = try Sandbox()
        let item = try box.file("Library/Caches/com.example/data").deletingLastPathComponent()
        let root = box.home.appendingPathComponent("Library/Caches")
        #expect(SafetyGuard(home: box.home).check(item, root: root) == nil)
    }

    @Test func refusesItemOutsideRoot() throws {
        let box = try Sandbox()
        let item = try box.folder("Library/Logs/thing")
        let root = box.home.appendingPathComponent("Library/Caches")
        #expect(SafetyGuard(home: box.home).check(item, root: root) == .outsideRoot)
    }

    @Test func refusesEscapeThroughSymlinkedFolder() throws {
        let box = try Sandbox()
        let secret = try box.file("Documents/secret.txt")
        let caches = try box.folder("Library/Caches")
        try FileManager.default.createSymbolicLink(
            at: caches.appendingPathComponent("evil"), withDestinationURL: secret.deletingLastPathComponent())

        let throughLink = caches.appendingPathComponent("evil/secret.txt")
        #expect(SafetyGuard(home: box.home).check(throughLink, root: caches) == .outsideRoot)
    }

    @Test func allowsMovingASymlinkItself() throws {
        // Moving a link moves the link, not its target.
        let box = try Sandbox()
        let target = try box.folder("Documents")
        let caches = try box.folder("Library/Caches")
        let link = caches.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(SafetyGuard(home: box.home).check(link, root: caches) == nil)
    }

    @Test func refusesProtectedUserFolders() throws {
        let box = try Sandbox()
        let documents = try box.folder("Documents")
        // Even a (hypothetical) rule rooted at home must not take Documents.
        #expect(SafetyGuard(home: box.home).check(documents, root: box.home) == .protectedPath)
    }

    @Test func refusesItemsContainingProtectedFolders() throws {
        let box = try Sandbox()
        try box.folder("Documents")
        let parentOfHome = box.home.deletingLastPathComponent()
        #expect(SafetyGuard(home: box.home).check(box.home, root: parentOfHome) == .protectedPath)
    }

    @Test("System folders are always refused", arguments: ["/System/Library", "/usr/lib", "/bin/ls", "/etc/hosts"])
    func refusesSystemPaths(path: String) {
        let url = URL(fileURLWithPath: path)
        let guardrail = SafetyGuard(home: URL(fileURLWithPath: "/Users/nobody"))
        #expect(guardrail.check(url, root: url.deletingLastPathComponent()) == .protectedPath)
    }

    @Test func refusesDotDotTricks() {
        let guardrail = SafetyGuard(home: URL(fileURLWithPath: "/Users/nobody"))
        let root = URL(fileURLWithPath: "/Users/nobody/Library/Caches")
        let sneaky = URL(fileURLWithPath: "/Users/nobody/Library/Caches/../../Documents")
        #expect(guardrail.check(sneaky, root: root) != nil)
    }
}
