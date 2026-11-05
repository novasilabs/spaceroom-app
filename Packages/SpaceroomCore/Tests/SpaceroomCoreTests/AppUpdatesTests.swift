// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import SpaceroomCore

@Suite("App updates")
struct AppUpdatesTests {
    /// Answers from a fixed table and records every request, so no test touches the network.
    final class FakeFetcher: UpdateFetching, @unchecked Sendable {
        var responses: [String: Data] = [:]
        private(set) var requested: [URL] = []
        private let lock = NSLock()

        func data(from url: URL) async throws -> Data {
            lock.withLock { requested.append(url) }
            let key = url.absoluteString.hasPrefix("https://itunes.apple.com/lookup") ? "store" : url.absoluteString
            guard let data = responses[key] else { throw URLError(.notConnectedToInternet) }
            return data
        }
    }

    static let macOS14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 8, patchVersion: 0)

    static func appcast(_ items: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><title>Example</title>\(items)</channel>
        </rss>
        """.utf8)
    }

    private func bundle(in box: Sandbox, name: String, short: String, build: String, feed: String?) throws -> InstalledApp {
        let url = box.home.appendingPathComponent("Applications/\(name).app")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleShortVersionString": short, "CFBundleVersion": build, "CFBundleIdentifier": "com.example.\(name)"]
        if let feed { plist["SUFeedURL"] = feed }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        return InstalledApp(url: url, name: name, bundleID: "com.example.\(name)", version: short, source: .developer, lastUsed: nil)
    }

    @Test("Version comparison", arguments: [
        ("1.10", "1.9", ComparisonResult.orderedDescending), ("2.0", "2.0.0", .orderedSame), ("1.2b3", "1.2", .orderedAscending),
        ("1.2.1", "1.2b", .orderedDescending), ("10", "9.9.9", .orderedDescending), ("1.0 (45)", "1.0 (44)", .orderedDescending),
        ("3.1.0", "3.1.0", .orderedSame), ("1.0rc1", "1.0beta2", .orderedDescending),
    ])
    func versions(a: String, b: String, expected: ComparisonResult) {
        #expect(AppVersion.compare(a, b) == expected)
    }

    @Test("Appcast: newest compatible release, ignoring beta channels and newer-macOS builds")
    func appcast() throws {
        let data = Self.appcast("""
        <item><title>2.0</title><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion><enclosure url="https://x/2.zip"/></item>
        <item><title>1.9 beta</title><sparkle:channel>beta</sparkle:channel><enclosure url="https://x/b.zip" sparkle:version="195"/></item>
        <item><title>1.8</title><sparkle:releaseNotesLink>https://example.com/1.8</sparkle:releaseNotesLink>
          <enclosure url="https://x/1.8.zip" sparkle:version="180" sparkle:shortVersionString="1.8"/></item>
        <item><title>1.7</title><enclosure url="https://x/1.7.zip" sparkle:version="170" sparkle:shortVersionString="1.7"/></item>
        """)
        let latest = try #require(Appcast.latest(in: data, systemVersion: Self.macOS14))
        #expect(latest.version == "180")
        #expect(latest.shortVersion == "1.8")
        #expect(latest.releaseNotes == URL(string: "https://example.com/1.8"))
        #expect(Appcast.latest(in: Data("not xml".utf8), systemVersion: Self.macOS14) == nil)
    }

    @Test("Sparkle apps: newer build found; same build, plain-HTTP feeds and failures handled")
    func sparkle() async throws {
        let box = try Sandbox()
        let old = try bundle(in: box, name: "Old", short: "1.7", build: "170", feed: "https://example.com/old.xml")
        let current = try bundle(in: box, name: "Current", short: "1.8", build: "180", feed: "https://example.com/current.xml")
        let insecure = try bundle(in: box, name: "Insecure", short: "1.0", build: "1", feed: "http://example.com/feed.xml")
        let offline = try bundle(in: box, name: "Offline", short: "1.0", build: "1", feed: "https://example.com/offline.xml")
        let noFeed = try bundle(in: box, name: "NoFeed", short: "1.0", build: "1", feed: nil)
        let fetcher = FakeFetcher()
        let feed = Self.appcast("<item><enclosure url=\"https://x\" sparkle:version=\"180\" sparkle:shortVersionString=\"1.8\"/></item>")
        fetcher.responses["https://example.com/old.xml"] = feed
        fetcher.responses["https://example.com/current.xml"] = feed

        let result = await AppUpdateChecker(fetcher: fetcher, systemVersion: Self.macOS14)
            .check([old, current, insecure, offline, noFeed])
        #expect(result.updates.map(\.app.name) == ["Old"])
        #expect(result.updates.first?.installedVersion == "1.7")
        #expect(result.updates.first?.availableVersion == "1.8")
        #expect(result.checked == 4)
        #expect(result.failed == 2)
        // The plain-HTTP feed is never requested.
        #expect(!fetcher.requested.contains { $0.scheme == "http" })
    }

    @Test("App Store apps: one lookup with bundle IDs only; Apple's apps are never checked")
    func appStore() async throws {
        let box = try Sandbox()
        let notes = InstalledApp(url: box.home.appendingPathComponent("Notes.app"), name: "Noted", bundleID: "com.example.noted",
                                 version: "3.1", source: .appStore, lastUsed: nil)
        let fresh = InstalledApp(url: box.home.appendingPathComponent("Fresh.app"), name: "Fresh", bundleID: "com.example.fresh",
                                 version: "2.0", source: .appStore, lastUsed: nil)
        let apple = InstalledApp(url: URL(fileURLWithPath: "/Applications/Pages.app"), name: "Pages", bundleID: "com.apple.iWork.Pages",
                                 version: "1.0", source: .appStore, lastUsed: nil)
        let fetcher = FakeFetcher()
        fetcher.responses["store"] = Data("""
        {"resultCount":2,"results":[
          {"bundleId":"com.example.noted","version":"3.2","trackViewUrl":"https://apps.apple.com/app/id1","minimumOsVersion":"13.0"},
          {"bundleId":"com.example.fresh","version":"2.0","trackViewUrl":"https://apps.apple.com/app/id2"}]}
        """.utf8)
        let result = await AppUpdateChecker(fetcher: fetcher, systemVersion: Self.macOS14, country: "id").check([notes, fresh, apple])
        #expect(result.updates.map(\.app.name) == ["Noted"])
        #expect(result.updates.first?.channel == .appStore(page: URL(string: "macappstore://apps.apple.com/app/id1")!))
        #expect(fetcher.requested.count == 1)
        let query = try #require(fetcher.requested.first?.query)
        #expect(query.contains("com.example.noted") && query.contains("com.example.fresh") && !query.contains("com.apple"))
    }
}
