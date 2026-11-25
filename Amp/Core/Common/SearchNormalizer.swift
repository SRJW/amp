import Foundation

/// Pre-normalized query built once per keystroke so thousands of library items
/// can be scored without repeating Unicode folding or tokenization.
struct PreparedSearchQuery: Sendable, Hashable {
    let words: String
    let packed: String
    let tokens: [String]
    let isEmpty: Bool

    init(_ raw: String) {
        let normalized = SearchNormalizer.normalizeWords(raw)
        self.words = normalized
        self.packed = normalized.replacingOccurrences(of: " ", with: "")
        self.tokens = normalized.isEmpty ? [] : normalized.split(separator: " ").map(String.init)
        self.isEmpty = normalized.isEmpty
    }
}

/// Pre-normalized searchable text cached once per library scan for sub-millisecond search.
struct NormalizedSearchText: Sendable, Hashable {
    let words: String
    let packed: String
    let tokens: [String]
    let initials: String

    init(_ raw: String) {
        let normalized = SearchNormalizer.normalizeWords(raw)
        self.words = normalized
        self.packed = normalized.replacingOccurrences(of: " ", with: "")
        let split = normalized.isEmpty ? [] : normalized.split(separator: " ").map(String.init)
        self.tokens = split
        self.initials = split.count >= 2 ? String(split.compactMap(\.first)) : ""
    }
}

/// Fast Unicode-safe search normalization and intelligent relevance scoring:
/// exact -> phrase prefix -> word-start prefix -> multi-token -> substring -> prefix-typo -> acronym -> bounded typo.
enum SearchNormalizer {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// Single-pass Unicode scalar normalizer equivalent to `[^\p{L}\p{M}\p{N}]+` without regex overhead.
    static func normalizeWords(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: posixLocale)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(folded.unicodeScalars.count)
        var lastWasSpace = true

        func appendSpace() {
            if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }

        for scalar in folded.unicodeScalars {
            switch scalar {
            case "$":
                out.append("s")
                lastWasSpace = false
            case "@":
                out.append("a")
                lastWasSpace = false
            case "&":
                appendSpace()
                out.append("a"); out.append("n"); out.append("d")
                lastWasSpace = false
                appendSpace()
            default:
                if isWordScalar(scalar) {
                    out.append(scalar)
                    lastWasSpace = false
                } else {
                    appendSpace()
                }
            }
        }
        if lastWasSpace, !out.isEmpty {
            out.removeLast()
        }
        return String(out)
    }

    @inline(__always)
    private static func isWordScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    static func normalize(_ text: String) -> String {
        normalizeWords(text).replacingOccurrences(of: " ", with: "")
    }

    static func matches(_ target: String, _ query: String) -> Bool {
        score(target, query) > 0
    }

    static func matches(_ target: NormalizedSearchText, _ query: PreparedSearchQuery) -> Bool {
        score(target, query) > 0
    }

    /// Convenience overload when scoring ad-hoc strings.
    static func score(_ target: String, _ query: String) -> Int {
        let preparedQuery = PreparedSearchQuery(query)
        guard !preparedQuery.isEmpty else { return 0 }
        return score(NormalizedSearchText(target), preparedQuery)
    }

    /// Exact names outrank phrase prefixes, word-start prefixes, multi-word matches,
    /// substrings, prefix typos while typing, acronyms, and bounded spelling corrections.
    static func score(_ target: NormalizedSearchText, _ query: PreparedSearchQuery) -> Int {
        guard !target.words.isEmpty, !query.isEmpty else { return 0 }
        if target.words == query.words || target.packed == query.packed { return 100 }
        if target.words.hasPrefix(query.words) || target.packed.hasPrefix(query.packed) { return 95 }
        if query.tokens.count == 1 {
            let needle = query.tokens[0]
            if target.tokens.contains(where: { $0.hasPrefix(needle) }) { return 90 }
            if target.words.contains(needle) || target.packed.contains(needle) { return 80 }
            if needle.count >= 3, !target.initials.isEmpty, target.initials.hasPrefix(needle) { return 66 }
            if let fuzzyScore = bestSingleTokenFuzzyScore(needle: needle, words: target.tokens) {
                return fuzzyScore
            }
            return 0
        }
        if target.words.contains(query.words) || target.packed.contains(query.packed) { return 86 }
        guard query.tokens.count <= 16 else { return 0 }
        return matchTokens(needles: query.tokens, words: target.tokens)
    }

    /// Scores a multi-field item (e.g. song title + artist + album + genre) when a user types
    /// mixed keywords like "rufus inner" or "bloom remix" across fields.
    static func multiFieldScore(primary: NormalizedSearchText, secondary: [NormalizedSearchText], query: PreparedSearchQuery) -> Int {
        guard !query.isEmpty else { return 0 }
        let directPrimary = score(primary, query)
        if directPrimary >= 95 { return directPrimary }

        var best = directPrimary
        if query.tokens.count == 1 {
            for field in secondary {
                let s = score(field, query)
                if s > 0 {
                    // Secondary field match (artist / album / genre) is valuable, slightly below a title match of the same tier.
                    best = max(best, max(1, s - 12))
                }
            }
            return best
        }

        // Multi-token cross-field match: every query token must match somewhere in primary or secondary.
        guard query.tokens.count <= 16 else { return best }
        var matchedPrimaryCount = 0
        var anyFuzzy = false
        var allPrefixOrExact = true
        for needle in query.tokens {
            if let hit = bestTokenHit(needle: needle, in: primary) {
                matchedPrimaryCount += 1
                if hit.isFuzzy { anyFuzzy = true }
                if !hit.isPrefixOrExact { allPrefixOrExact = false }
                continue
            }
            var foundSecondary: TokenHit?
            for field in secondary {
                if let hit = bestTokenHit(needle: needle, in: field) {
                    if foundSecondary == nil || hit.quality > foundSecondary!.quality {
                        foundSecondary = hit
                    }
                }
            }
            guard let hit = foundSecondary else { return best }
            if hit.isFuzzy { anyFuzzy = true }
            if !hit.isPrefixOrExact { allPrefixOrExact = false }
        }

        let crossScore: Int
        if matchedPrimaryCount > 0 {
            if anyFuzzy {
                crossScore = 70
            } else if allPrefixOrExact {
                crossScore = matchedPrimaryCount == query.tokens.count ? 92 : 89
            } else {
                crossScore = 82
            }
        } else {
            crossScore = anyFuzzy ? 56 : (allPrefixOrExact ? 74 : 68)
        }
        return max(best, crossScore)
    }

    private struct TokenHit {
        let quality: Int
        let isPrefixOrExact: Bool
        let isFuzzy: Bool
    }

    private static func bestTokenHit(needle: String, in text: NormalizedSearchText) -> TokenHit? {
        guard !text.words.isEmpty else { return nil }
        if text.tokens.contains(where: { $0 == needle }) {
            return TokenHit(quality: 100, isPrefixOrExact: true, isFuzzy: false)
        }
        if text.tokens.contains(where: { $0.hasPrefix(needle) }) {
            return TokenHit(quality: 92, isPrefixOrExact: true, isFuzzy: false)
        }
        if text.words.contains(needle) || text.packed.contains(needle) {
            return TokenHit(quality: 80, isPrefixOrExact: false, isFuzzy: false)
        }
        if let fuzzy = bestSingleTokenFuzzyScore(needle: needle, words: text.tokens) {
            return TokenHit(quality: fuzzy, isPrefixOrExact: false, isFuzzy: true)
        }
        return nil
    }

    private static func matchTokens(needles: [String], words: [String]) -> Int {
        var unused = Set(words.indices)
        var fuzzy = false
        var allPrefix = true
        for needle in needles {
            if let index = unused.sorted().first(where: { words[$0] == needle || words[$0].hasPrefix(needle) }) {
                unused.remove(index)
                continue
            }
            if needle.count >= 3, let index = unused.sorted().first(where: { words[$0].contains(needle) }) {
                unused.remove(index)
                allPrefix = false
                continue
            }
            if let index = bestFuzzyWordIndex(needle: needle, words: words, unused: unused) {
                unused.remove(index)
                fuzzy = true
                allPrefix = false
                continue
            }
            return 0
        }
        if fuzzy { return 60 }
        return allPrefix ? 84 : 76
    }

    private static func bestFuzzyWordIndex(needle: String, words: [String], unused: Set<Int>) -> Int? {
        let limit = allowedEdits(needle)
        guard limit > 0 else { return nil }
        let candidates = unused.sorted()
        if let exactFuzzy = candidates.first(where: { editDistance(needle, words[$0], limit: limit) <= limit }) {
            return exactFuzzy
        }
        if needle.count >= 4 {
            return candidates.first { matchesPrefixFuzzy(needle: needle, word: words[$0]) }
        }
        return nil
    }

    private static func bestSingleTokenFuzzyScore(needle: String, words: [String]) -> Int? {
        let limit = allowedEdits(needle)
        guard limit > 0 else { return nil }
        var bestFullDistance: Int?
        for word in words {
            let d = editDistance(needle, word, limit: limit)
            if d <= limit {
                if bestFullDistance == nil || d < bestFullDistance! {
                    bestFullDistance = d
                }
                if d == 1 { break }
            }
        }
        if let d = bestFullDistance {
            return d <= 1 ? 70 : 64
        }
        if needle.count >= 4 {
            for word in words where matchesPrefixFuzzy(needle: needle, word: word) {
                return 62
            }
        }
        return nil
    }

    /// Allows 1 typo against the leading prefix of a longer word while typing (e.g. "inerb" or "innner" -> "innerbloom"),
    /// requiring the leading characters to anchor cleanly so unrelated words never match.
    private static func matchesPrefixFuzzy(needle: String, word: String) -> Bool {
        let nCount = needle.count
        let wCount = word.count
        guard nCount >= 4, wCount > nCount else { return false }
        let nChars = Array(needle)
        let wChars = Array(word)
        let anchored = nChars[0] == wChars[0] || (wChars.count >= 2 && nChars[0] == wChars[1] && nChars[1] == wChars[0])
        guard anchored else { return false }
        let sameLenEndMatches = nCount >= 6
            || nChars[nCount - 1] == wChars[nCount - 1]
            || (nChars[nCount - 1] == wChars[nCount - 2] && nChars[nCount - 2] == wChars[nCount - 1])
        if sameLenEndMatches {
            let sameLenPrefix = String(wChars.prefix(nCount))
            if editDistance(needle, sameLenPrefix, limit: 1) <= 1 { return true }
        }
        if wCount >= nCount + 1, nChars[nCount - 1] == wChars[nCount] {
            let extendedPrefix = String(wChars.prefix(nCount + 1))
            if editDistance(needle, extendedPrefix, limit: 1) <= 1 { return true }
        }
        if nCount >= 5, nChars[nCount - 1] == wChars[nCount - 2] {
            let shorterPrefix = String(wChars.prefix(nCount - 1))
            if editDistance(needle, shorterPrefix, limit: 1) <= 1 { return true }
        }
        return false
    }

    static func allowedEdits(_ word: String) -> Int {
        if word.contains(where: \.isNumber) { return 0 }
        return word.count >= 8 ? 2 : word.count >= 4 ? 1 : 0
    }

    /// Damerau-Levenshtein: a swapped adjacent pair counts as one typing error.
    static func editDistance(_ first: String, _ second: String, limit: Int) -> Int {
        let a = Array(first), b = Array(second)
        guard abs(a.count - b.count) <= limit, max(a.count, b.count) <= 80 else { return limit + 1 }
        var before = Array(0...b.count), previous = before
        for i in a.indices {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            var rowMin = current[0]
            for j in b.indices {
                var cost = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (a[i] == b[j] ? 0 : 1))
                if i > 0 && j > 0 && a[i] == b[j - 1] && a[i - 1] == b[j] {
                    cost = min(cost, before[j - 1] + 1)
                }
                current[j + 1] = cost
                if cost < rowMin { rowMin = cost }
            }
            if rowMin > limit { return limit + 1 }
            before = previous; previous = current
        }
        return previous.last ?? limit + 1
    }
}
