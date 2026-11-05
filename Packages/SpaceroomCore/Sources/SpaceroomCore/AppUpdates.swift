// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A newer version of an installed app.
public struct AppUpdate: Sendable, Identifiable, Hashable {
    public enum Channel: Sendable, Hashable {
        /// The app updates itself with Sparkle; opening it lets its own updater install the update,
        /// which checks the developer's signature.
        case sparkle(releaseNotes: URL?)
        case appStore(page: URL)
    }

    public var id: String { app.id }
    public let app: InstalledApp
    public let installedVersion: String
    public let availableVersion: String
    public let channel: Channel

    public init(app: InstalledApp, installedVersion: String, availableVersion: String, channel: Channel) {
        self.app = app
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.channel = channel
    }
}

public struct UpdateCheckResult: Sendable {
    public var updates: [AppUpdate]
    /// Apps that publish an update feed or are from the App Store, i.e. could be checked.
    public var checked: Int
    /// Feeds that couldn't be read (offline, moved, not HTTPS).
    public var failed: Int

    public init(updates: [AppUpdate], checked: Int, failed: Int) {
        self.updates = updates
        self.checked = checked
        self.failed = failed
    }
}

/// Fetches update information. Replaceable so tests never touch the network.
public protocol UpdateFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// An ephemeral session: no cookies, no cache, no credentials, a short timeout.
public struct URLSessionFetcher: UpdateFetching {
    public init() {}

    public func data(from url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "Spaceroom update check"]
        let (data, response) = try await URLSession(configuration: configuration).data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Checks for app updates only when asked. It contacts each app's own Sparkle feed (HTTPS
/// only) and Apple's App Store lookup for App Store apps, sending nothing but the feed request
/// and the bundle IDs. It never downloads or installs anything itself.
public struct AppUpdateChecker: Sendable {
    public let fetcher: any UpdateFetching
    public let systemVersion: OperatingSystemVersion
    public let country: String

    public init(fetcher: any UpdateFetching = URLSessionFetcher(),
                systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                country: String = (Locale.current.region?.identifier ?? "US").lowercased()) {
        self.fetcher = fetcher
        self.systemVersion = systemVersion
        self.country = country
    }

    public func check(_ apps: [InstalledApp]) async -> UpdateCheckResult {
        let candidates = apps.filter { !$0.isProtected }
        let store = candidates.filter { $0.source == .appStore }
        let sparkle = candidates.compactMap { app -> (InstalledApp, BundleVersions)? in
            guard app.source != .appStore, let versions = BundleVersions(bundle: app.url), versions.feed != nil else { return nil }
            return (app, versions)
        }
        var result = UpdateCheckResult(updates: [], checked: store.count + sparkle.count, failed: 0)

        await withTaskGroup(of: (AppUpdate?, Bool).self) { group in
            var pending = sparkle[...]
            func add() {
                guard let (app, versions) = pending.popFirst() else { return }
                group.addTask { await checkSparkle(app, versions) }
            }
            for _ in 0..<6 { add() }
            while let (update, failed) = await group.next() {
                if let update { result.updates.append(update) }
                if failed { result.failed += 1 }
                add()
            }
        }

        for batch in stride(from: 0, to: store.count, by: 50).map({ Array(store[$0..<min($0 + 50, store.count)]) }) {
            let (updates, failed) = await checkAppStore(batch)
            result.updates += updates
            if failed { result.failed += batch.count }
        }
        result.updates.sort { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        return result
    }

    func checkSparkle(_ app: InstalledApp, _ versions: BundleVersions) async -> (AppUpdate?, Bool) {
        guard let feed = versions.feed, feed.scheme?.lowercased() == "https",
              let data = try? await fetcher.data(from: feed) else { return (nil, true) }
        guard let latest = Appcast.latest(in: data, systemVersion: systemVersion) else { return (nil, false) }
        // Compare build numbers when both are known (that's what Sparkle compares), else versions.
        let isNewer: Bool
        if let build = latest.version, let installedBuild = versions.build {
            isNewer = AppVersion.compare(build, installedBuild) == .orderedDescending
        } else if let short = latest.shortVersion ?? latest.version, let installed = versions.short {
            isNewer = AppVersion.compare(short, installed) == .orderedDescending
        } else {
            isNewer = false
        }
        guard isNewer else { return (nil, false) }
        return (AppUpdate(app: app, installedVersion: versions.short ?? versions.build ?? "?",
                          availableVersion: latest.shortVersion ?? latest.version ?? "?",
                          channel: .sparkle(releaseNotes: latest.releaseNotes)), false)
    }

    func checkAppStore(_ apps: [InstalledApp]) async -> ([AppUpdate], Bool) {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: apps.map(\.bundleID).joined(separator: ",")),
            URLQueryItem(name: "entity", value: "macSoftware"),
            URLQueryItem(name: "country", value: country),
        ]
        guard let url = components.url, let data = try? await fetcher.data(from: url),
              let lookup = try? JSONDecoder().decode(StoreLookup.self, from: data) else { return ([], true) }
        var updates: [AppUpdate] = []
        for app in apps {
            guard let entry = lookup.results.first(where: { $0.bundleId == app.bundleID }),
                  let installed = app.version ?? BundleVersions(bundle: app.url)?.short,
                  AppVersion.compare(entry.version, installed) == .orderedDescending else { continue }
            if let minimum = entry.minimumOsVersion, AppVersion.compare(minimum, Self.string(systemVersion)) == .orderedDescending {
                continue
            }
            let page = entry.trackViewUrl.flatMap { URL(string: $0.replacingOccurrences(of: "https://", with: "macappstore://")) }
                ?? URL(string: "macappstore://apps.apple.com")!
            updates.append(AppUpdate(app: app, installedVersion: installed, availableVersion: entry.version,
                                     channel: .appStore(page: page)))
        }
        return (updates, false)
    }

    static func string(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    struct StoreLookup: Decodable {
        struct Entry: Decodable {
            let bundleId: String
            let version: String
            let trackViewUrl: String?
            let minimumOsVersion: String?
        }
        let results: [Entry]
    }
}

/// Versions and Sparkle feed from an app's Info.plist.
struct BundleVersions {
    let short: String?
    let build: String?
    let feed: URL?

    init?(bundle: URL) {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        short = plist["CFBundleShortVersionString"] as? String
        build = plist["CFBundleVersion"] as? String
        feed = (plist["SUFeedURL"] as? String).flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
    }
}

// MARK: - Appcast

/// The newest release in a Sparkle appcast that runs on this macOS. Beta channels and
/// delta-only entries are ignored.
enum Appcast {
    struct Item: Equatable {
        var version: String?
        var shortVersion: String?
        var minimumSystemVersion: String?
        var releaseNotes: URL?
        var channel: String?
        var hasEnclosure = false
    }

    static func latest(in data: Data, systemVersion: OperatingSystemVersion) -> Item? {
        let parser = Parser(data: data)
        let system = AppUpdateChecker.string(systemVersion)
        let usable = parser.items().filter { item in
            guard item.channel == nil, item.hasEnclosure, item.version != nil || item.shortVersion != nil else { return false }
            if let minimum = item.minimumSystemVersion { return AppVersion.compare(minimum, system) != .orderedDescending }
            return true
        }
        return usable.max { a, b in
            AppVersion.compare(a.version ?? a.shortVersion ?? "0", b.version ?? b.shortVersion ?? "0") == .orderedAscending
        }
    }

    final class Parser: NSObject, XMLParserDelegate {
        private let parser: XMLParser
        private var result: [Item] = []
        private var current: Item?
        private var text = ""

        init(data: Data) {
            parser = XMLParser(data: data)
            super.init()
            parser.shouldResolveExternalEntities = false
            parser.delegate = self
        }

        func items() -> [Item] {
            parser.parse()
            return result
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            if name == "item" { current = Item() }
            guard current != nil else { return }
            if name == "enclosure", var item = current {
                item.hasEnclosure = true
                item.version = item.version ?? attributes["sparkle:version"]
                item.shortVersion = item.shortVersion ?? attributes["sparkle:shortVersionString"]
                current = item
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "item":
                if let current { result.append(current) }
                current = nil
            case "sparkle:version" where !value.isEmpty: current?.version = value
            case "sparkle:shortVersionString" where !value.isEmpty: current?.shortVersion = value
            case "sparkle:minimumSystemVersion" where !value.isEmpty: current?.minimumSystemVersion = value
            case "sparkle:releaseNotesLink" where !value.isEmpty:
                if let url = URL(string: value), url.scheme == "https" { current?.releaseNotes = url }
            case "sparkle:channel" where !value.isEmpty: current?.channel = value
            default: break
            }
            text = ""
        }
    }
}

// MARK: - Versions

/// Compares version strings the way people expect: "1.10" > "1.9", "2.0" == "2.0.0",
/// "1.2b3" < "1.2".
public enum AppVersion {
    enum Token: Equatable {
        case number(Int)
        case word(String)
    }

    static func tokens(_ version: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var isNumber = false
        func flush() {
            guard !buffer.isEmpty else { return }
            tokens.append(isNumber ? .number(Int(buffer.prefix(18)) ?? 0) : .word(buffer.lowercased()))
            buffer = ""
        }
        for character in version {
            if character.isNumber {
                if !isNumber { flush() }
                isNumber = true
                buffer.append(character)
            } else if character.isLetter {
                if isNumber { flush() }
                isNumber = false
                buffer.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let left = tokens(a), right = tokens(b)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : nil
            let r = index < right.count ? right[index] : nil
            switch (l, r) {
            case let (.number(x)?, .number(y)?):
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
            case let (.word(x)?, .word(y)?):
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
            // A number beats a word ("1.2.1" > "1.2b"); a word means a pre-release ("1.2b" < "1.2").
            case (.number?, .word?): return .orderedDescending
            case (.word?, .number?): return .orderedAscending
            case (.word?, nil): return .orderedAscending
            case (nil, .word?): return .orderedDescending
            case (.number(let x)?, nil): if x != 0 { return .orderedDescending }
            case (nil, .number(let y)?): if y != 0 { return .orderedAscending }
            case (nil, nil): break
            }
        }
        return .orderedSame
    }
}
