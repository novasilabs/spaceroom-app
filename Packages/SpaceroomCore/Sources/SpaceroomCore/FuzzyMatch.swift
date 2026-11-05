// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Typo-tolerant-enough matching for the command palette: the query's letters must appear in
/// order; matches at word starts, runs of consecutive letters and prefixes score higher.
public enum FuzzyMatch {
    /// `nil` when `text` doesn't contain every query letter in order. Higher is better.
    public static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(normalize(query).filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let normalizedText = normalize(text)
        let haystack = Array(normalizedText)
        // The original letters, for camelCase word starts ("SpaceLens"), when folding kept the length.
        let original = Array(text)
        let knowsCase = original.count == haystack.count
        func isWordStart(_ index: Int) -> Bool {
            index == 0 || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber)
                || (knowsCase && original[index - 1].isLowercase && original[index].isUppercase)
        }

        // Try every place the first letter occurs, so "tra" lines up with "Trash", not the t in "Empty".
        var best: Int?
        for start in haystack.indices where haystack[start] == needle[0] {
            var score = 1 + (isWordStart(start) ? 12 : 0) - min(start, 8) / 2
            var previous = start
            var matchedAll = true
            for letter in needle.dropFirst() {
                guard let found = haystack[(previous + 1)...].firstIndex(of: letter) else { matchedAll = false; break }
                score += 1
                if found == previous + 1 {
                    score += 8
                } else {
                    score += isWordStart(found) ? 6 : 0
                    score -= min(found - previous - 1, 8)
                }
                previous = found
            }
            guard matchedAll else { break } // later starts can only find fewer letters
            best = max(best ?? .min, score)
        }
        guard var score = best else { return nil }

        let query = normalize(query)
        if normalizedText == query {
            score += 100
        } else if normalizedText.hasPrefix(query) {
            score += 50
        }
        // Prefer shorter texts when everything else is equal.
        return score - haystack.count / 12
    }

    /// The best score over several texts (a title and its keywords). Keywords count a little less.
    public static func score(_ query: String, title: String, keywords: [String]) -> Int? {
        let titleScore = score(query, in: title)
        let keywordScore = keywords.compactMap { score(query, in: $0) }.max().map { $0 - 5 }
        switch (titleScore, keywordScore) {
        case let (title?, keyword?): return max(title, keyword)
        case let (title?, nil): return title
        case let (nil, keyword?): return keyword
        case (nil, nil): return nil
        }
    }

    /// Items that match, best first; ties keep their original order.
    public static func rank<Item>(_ items: [Item], query: String, title: (Item) -> String,
                                  keywords: (Item) -> [String] = { _ in [] }) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        let scored = items.enumerated()
            .compactMap { index, item in
                score(trimmed, title: title(item), keywords: keywords(item)).map { (index, item, $0) }
            }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
        guard let top = scored.first?.2 else { return [] }
        // Drop stragglers that only match by scattered letters far below the best hit.
        let cutoff = top > 0 ? top * 2 / 5 : top
        return scored.filter { $0.2 >= cutoff }.map(\.1)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
