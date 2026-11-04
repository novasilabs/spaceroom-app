// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("Path patterns")
struct PathPatternTests {
    @Test("Valid patterns parse", arguments: [
        "~/Library/Caches/*",
        "~/.Trash/*",
        "~/.npm/_cacache",
        "~/Library/Developer/Xcode/iOS DeviceSupport/*",
        "/Library/Caches/*",
        "~/Library/Caches/com.?oo[0-9]*",
    ])
    func validPatterns(raw: String) throws {
        _ = try PathPattern(raw)
    }

    @Test("Dangerous or malformed patterns are rejected", arguments: [
        ("Library/Caches/*", PathPattern.ParseError.mustStartWithHomeOrSlash),
        ("~/*", .rootTooShallow),
        ("/Library/*", .rootTooShallow),
        ("/*", .rootTooShallow),
        ("~/Documents/*", .protectedRoot("~/Documents")),
        ("~/Library/*", .protectedRoot("~/Library")),
        ("~/Downloads/*", .protectedRoot("~/Downloads")),
        ("~/Library/*/Caches", .wildcardOutsideLeaf("*")),
        ("~/Library/Caches/**", .recursiveWildcard),
        ("~/Library/../Documents/*", .invalidComponent("..")),
        ("~/Library//Caches/*", .invalidComponent("")),
        ("~/Library/Caches/", .invalidComponent("")),
    ])
    func rejectedPatterns(raw: String, expected: PathPattern.ParseError) {
        #expect(throws: expected) { try PathPattern(raw) }
    }

    @Test func expandsWildcardWithExcludes() throws {
        let box = try Sandbox()
        try box.file("Library/Caches/com.example.app/data")
        try box.file("Library/Caches/com.apple.Safari/data")
        try box.file("Library/Caches/.hidden")

        let pattern = try PathPattern("~/Library/Caches/*")
        let names = pattern.expand(home: box.home, exclude: ["com.apple.*"]).map(\.lastPathComponent)
        #expect(names == [".hidden", "com.example.app"])
    }

    @Test func literalPatternExpandsOnlyWhenPresent() throws {
        let box = try Sandbox()
        let pattern = try PathPattern("~/.npm/_cacache")
        #expect(pattern.expand(home: box.home).isEmpty)
        try box.file(".npm/_cacache/index")
        #expect(pattern.expand(home: box.home).map(\.lastPathComponent) == ["_cacache"])
    }

    @Test func claimURL() throws {
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(try PathPattern("~/Library/Caches/Homebrew/*").claimURL(home: home).path == "/Users/test/Library/Caches/Homebrew")
        #expect(try PathPattern("~/.npm/_cacache").claimURL(home: home).path == "/Users/test/.npm/_cacache")
    }
}
