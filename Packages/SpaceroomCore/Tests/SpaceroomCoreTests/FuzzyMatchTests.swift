// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import SpaceroomCore

@Suite("Fuzzy match")
struct FuzzyMatchTests {
    @Test func needsEveryLetterInOrder() {
        #expect(FuzzyMatch.score("prv", in: "Privacy") != nil)
        #expect(FuzzyMatch.score("vrp", in: "Privacy") == nil)
        #expect(FuzzyMatch.score("privacyx", in: "Privacy") == nil)
        #expect(FuzzyMatch.score("", in: "Privacy") == 0)
    }

    @Test func ignoresCaseAccentsAndSpaces() {
        #expect(FuzzyMatch.score("CAFE", in: "Café Menu") != nil)
        #expect(FuzzyMatch.score("space lens", in: "SpaceLens") != nil)
    }

    @Test func prefersPrefixesAndWordStarts() throws {
        let prefix = try #require(FuzzyMatch.score("sta", in: "Startup & Background"))
        let inner = try #require(FuzzyMatch.score("sta", in: "System Status"))
        #expect(prefix > inner)
        // "sc" hits the starts of "Smart Care" but sits inside "Disc Cleanup".
        let words = try #require(FuzzyMatch.score("sc", in: "Smart Care"))
        let middle = try #require(FuzzyMatch.score("sc", in: "Disc Cleanup"))
        #expect(words > middle)
    }

    @Test func alignsWithTheBestWordNotTheFirstLetter() throws {
        let trash = try #require(FuzzyMatch.score("tra", in: "Empty the Trash"))
        let scattered = try #require(FuzzyMatch.score("tra", in: "what is using storage"))
        #expect(trash > scattered * 2)
    }

    @Test func dropsScatteredStragglers() {
        let ranked = FuzzyMatch.rank(["Empty the Trash", "what is using storage"], query: "tra", title: { $0 })
        #expect(ranked == ["Empty the Trash"])
    }

    @Test func exactBeatsLonger() throws {
        let exact = try #require(FuzzyMatch.score("cleanup", in: "Cleanup"))
        let longer = try #require(FuzzyMatch.score("cleanup", in: "Dev Cleanup"))
        #expect(exact > longer)
    }

    @Test func ranksAndUsesKeywords() {
        let items = ["Restore Center", "Smart Care", "Cleanup", "Empty the Trash"]
        let keywords = ["Restore Center": ["undo", "quarantine"], "Empty the Trash": ["bin", "delete"]]
        let ranked = FuzzyMatch.rank(items, query: "undo", title: { $0 }, keywords: { keywords[$0] ?? [] })
        #expect(ranked == ["Restore Center"])
        #expect(FuzzyMatch.rank(items, query: "care", title: { $0 }).first == "Smart Care")
        #expect(FuzzyMatch.rank(items, query: "  ", title: { $0 }) == items)
    }
}
