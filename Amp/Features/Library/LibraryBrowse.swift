import Foundation

enum LibrarySort: String, CaseIterable, Sendable {
    case title, titleDescending, recentlyAdded, recentlyPlayed, artist, album, newestYear, oldestYear, mostPlayed

    var label: String {
        switch self {
        case .title: "Title · A–Z"
        case .titleDescending: "Title · Z–A"
        case .recentlyAdded: "Recently added"
        case .recentlyPlayed: "Recently played"
        case .artist: "Artist · A–Z"
        case .album: "Album · A–Z"
        case .newestYear: "Year · newest first"
        case .oldestYear: "Year · oldest first"
        case .mostPlayed: "Most played"
        }
    }

    var shortLabel: String {
        switch self {
        case .title: "A–Z"
        case .titleDescending: "Z–A"
        case .recentlyAdded: "Added"
        case .recentlyPlayed: "Played"
        case .artist: "Artist"
        case .album: "Album"
        case .newestYear: "Newest"
        case .oldestYear: "Oldest"
        case .mostPlayed: "Most played"
        }
    }

    static let albums: [Self] = [.title, .titleDescending, .recentlyAdded, .recentlyPlayed, .artist, .newestYear, .oldestYear, .mostPlayed]
    static let songs: [Self] = [.title, .titleDescending, .recentlyAdded, .recentlyPlayed, .artist, .album, .mostPlayed]
}

enum LibraryMood: String, CaseIterable, Sendable {
    case all, chill, highEnergy, lateNight, feelGood, party, romantic, sad, dark, focus, throwback

    var label: String {
        switch self {
        case .all: "Mood"
        case .chill: "Chill"
        case .highEnergy: "High energy"
        case .lateNight: "Late night"
        case .feelGood: "Feel-good"
        case .party: "Party"
        case .romantic: "Love songs"
        case .sad: "Sad & reflective"
        case .dark: "Dark"
        case .focus: "Focus"
        case .throwback: "Throwback"
        }
    }

    func matches(_ song: Song, currentYear: Int = Calendar.current.component(.year, from: Date())) -> Bool {
        guard self != .all else { return true }
        let track = TrackFacts(songId: song.id, title: song.title, artistId: song.artistId, artist: song.artist,
                               albumId: song.albumId, album: song.album, genre: song.genre, bpm: song.bpm,
                               durationMs: song.durationMs, isFavorite: song.isFavorite, addedAt: song.dateModified,
                               year: song.year)
        switch self {
        case .all: return true
        case .chill: return Moods.isChill(track)
        case .highEnergy: return Moods.isHighEnergy(track)
        case .lateNight: return Moods.isLateNight(track)
        case .feelGood: return Moods.isFeelGood(track)
        case .party: return Moods.isParty(track)
        case .romantic: return Moods.isRomantic(track)
        case .sad: return Moods.isSad(track)
        case .dark: return Moods.isDark(track)
        case .focus: return Moods.isFocus(track)
        case .throwback: return Moods.isThrowback(track, currentYear: currentYear)
        }
    }
}

/// Snapshots keep filtering and sorting off the UI thread, and invalidate only when inputs change.
struct AlbumBrowseRequest: Hashable, Sendable {
    var albums: [Album]
    var songs: [Song]
    var facts: [Int64: LibraryBrowseFact]
    var lastPlayed: [Int64: Int64]
    var query: String
    var sort: LibrarySort

    func results() -> [Album] {
        var albumFacts: [Int64: LibraryBrowseFact] = [:]
        for song in songs {
            let fact = facts[song.id] ?? LibraryBrowseFact(addedAt: song.dateModified)
            var aggregate = albumFacts[song.albumId, default: LibraryBrowseFact()]
            aggregate.addedAt = max(aggregate.addedAt, fact.addedAt)
            aggregate.lastPlayedAt = max(aggregate.lastPlayedAt, fact.lastPlayedAt)
            aggregate.plays += fact.plays
            albumFacts[song.albumId] = aggregate
        }
        let search = SectionSearch(query)
        let isSearching = !search.isEmpty
        return albums.compactMap { album -> BrowseEntry<Album>? in
            let relevance = isSearching ? search.score(primary: album.title, secondary: [album.artist]) : 0
            guard !isSearching || relevance > 0 else { return nil }
            let fact = albumFacts[album.id, default: LibraryBrowseFact()]
            return BrowseEntry(value: album, id: album.id, title: album.title, artist: album.artist,
                               album: album.title, year: album.year, added: fact.addedAt,
                               played: max(fact.lastPlayedAt, lastPlayed[album.id, default: 0]), plays: fact.plays,
                               relevance: relevance)
        }.sorted { BrowseEntry.precedes($0, $1, sort: sort, prioritizeRelevance: isSearching) }.map(\.value)
    }
}

struct SongBrowseRequest: Hashable, Sendable {
    var songs: [Song]
    var facts: [Int64: LibraryBrowseFact]
    var query: String
    var sort: LibrarySort
    /// Empty means all genres; the sentinel represents songs with no usable genre tag.
    var genre = ""
    var mood = LibraryMood.all
    /// Empty means all formats; `LibraryBrowse.losslessFormat` matches lossless tracks; otherwise an uppercase format key (e.g. "MP3", "FLAC", "ALAC", "AAC").
    var format = ""

    func results() -> [Song] {
        let search = SectionSearch(query)
        let isSearching = !search.isEmpty
        return songs.compactMap { song -> BrowseEntry<Song>? in
            let genres = Genres.parse(song.genre)
            let matchesGenre = genre.isEmpty || (genre == LibraryBrowse.untaggedGenre ? genres.isEmpty : genres.contains { SectionSearch.key($0) == genre })
            guard matchesGenre else { return nil }
            let matchesFormat = format.isEmpty
                || (format == LibraryBrowse.losslessFormat ? song.isLossless : LibraryBrowse.formatKey(for: song) == format)
            guard matchesFormat && mood.matches(song) else { return nil }
            let relevance = isSearching ? search.score(primary: song.title, secondary: [song.artist, song.album, song.genre ?? ""]) : 0
            guard !isSearching || relevance > 0 else { return nil }
            let fact = facts[song.id] ?? LibraryBrowseFact(addedAt: song.dateModified)
            return BrowseEntry(value: song, id: song.id, title: song.title, artist: song.artist, album: song.album,
                               year: song.year, added: fact.addedAt, played: fact.lastPlayedAt, plays: fact.plays,
                               relevance: relevance)
        }.sorted { BrowseEntry.precedes($0, $1, sort: sort, prioritizeRelevance: isSearching) }.map(\.value)
    }
}

enum LibraryBrowse {
    static let untaggedGenre = "\u{0}"
    static let losslessFormat = "\u{1}"

    static func genres(in songs: [Song]) -> [String] {
        var values: [String: String] = [:]
        for song in songs {
            for genre in Genres.parse(song.genre) {
                let key = SectionSearch.key(genre)
                if values[key] == nil { values[key] = genre }
            }
        }
        return values.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func formatKey(for song: Song) -> String {
        let ext = (song.path as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let codec = song.codec?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if codec == "ALAC" { return "ALAC" }
        if codec == "AAC" || codec.hasPrefix("HE-AAC") { return "AAC" }
        if !ext.isEmpty { return ext }
        return codec
    }

    static func formats(in songs: [Song]) -> [String] {
        Set(songs.map(formatKey).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// Keep every script, including combining marks. ASCII-only normalization loses Hindi/Arabic titles.
struct SectionSearch: Sendable {
    private let prepared: PreparedSearchQuery
    var isEmpty: Bool { prepared.isEmpty }

    init(_ query: String) {
        self.prepared = PreparedSearchQuery(query)
    }

    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased().replacingOccurrences(of: "$", with: "s")
    }

    func matches(_ fields: [String]) -> Bool {
        guard !prepared.isEmpty else { return true }
        return score(fields) > 0
    }

    func score(_ fields: [String]) -> Int {
        guard !prepared.isEmpty else { return 0 }
        guard let first = fields.first else { return 0 }
        return score(primary: first, secondary: Array(fields.dropFirst()))
    }

    func score(primary: String, secondary: [String] = []) -> Int {
        guard !prepared.isEmpty else { return 0 }
        let primaryText = NormalizedSearchText(primary)
        if secondary.isEmpty {
            return SearchNormalizer.score(primaryText, prepared)
        }
        let secondaryTexts = secondary.compactMap { $0.isEmpty ? nil : NormalizedSearchText($0) }
        return SearchNormalizer.multiFieldScore(primary: primaryText, secondary: secondaryTexts, query: prepared)
    }
}

private struct BrowseEntry<Value> {
    let value: Value
    let id: Int64
    let title: String
    let artist: String
    let album: String
    let year: Int
    let added: Int64
    let played: Int64
    let plays: Int
    let relevance: Int

    init(value: Value, id: Int64, title: String, artist: String, album: String, year: Int,
         added: Int64, played: Int64, plays: Int, relevance: Int = 0) {
        self.value = value; self.id = id
        self.title = SectionSearch.key(title); self.artist = SectionSearch.key(artist); self.album = SectionSearch.key(album)
        self.year = year; self.added = added; self.played = played; self.plays = plays
        self.relevance = relevance
    }

    static func precedes(_ a: Self, _ b: Self, sort: LibrarySort, prioritizeRelevance: Bool = false) -> Bool {
        if prioritizeRelevance {
            if a.relevance != b.relevance { return a.relevance > b.relevance }
            if a.title.count != b.title.count { return a.title.count < b.title.count }
        }
        switch sort {
        case .recentlyAdded: if a.added != b.added { return a.added > b.added }
        case .recentlyPlayed: if a.played != b.played { return a.played > b.played }
        case .mostPlayed: if a.plays != b.plays { return a.plays > b.plays }
        case .newestYear, .oldestYear:
            if (a.year > 0) != (b.year > 0) { return a.year > 0 }
            if a.year != b.year { return sort == .newestYear ? a.year > b.year : a.year < b.year }
        case .artist: if a.artist != b.artist { return compare(a.artist, b.artist) }
        case .album:
            if a.album != b.album { return compare(a.album, b.album) }
            if a.artist != b.artist { return compare(a.artist, b.artist) }
        case .titleDescending: if a.title != b.title { return compare(b.title, a.title) }
        case .title: break
        }
        if a.title != b.title { return compare(a.title, b.title) }
        if a.artist != b.artist { return compare(a.artist, b.artist) }
        return a.id < b.id
    }

    private static func compare(_ a: String, _ b: String) -> Bool {
        // Numeric order places "2" before "10". A literal tie-break keeps ordering strict.
        let result = a.compare(b, options: .numeric)
        return result == .orderedSame ? a < b : result == .orderedAscending
    }
}

/// Resolves Poweramp-style continuous playback from a song picked in Search into All Songs,
/// respecting the user's All Songs sort order as well as shuffle / repeat modes.
enum ContinuousPlayback {
    static let allSongsSortKey = "library.songs.sort"

    static func currentSort(defaults: UserDefaults = .standard) -> LibrarySort {
        let raw = defaults.string(forKey: allSongsSortKey) ?? LibraryCategory.songs.defaultSort.rawValue
        return LibrarySort(rawValue: raw) ?? .title
    }

    static func orderedAllSongs(allSongs: [Song], facts: [Int64: LibraryBrowseFact], sort: LibrarySort) -> [Song] {
        SongBrowseRequest(songs: allSongs, facts: facts, query: "", sort: sort).results()
    }

    /// Returns the full sorted All Songs list and the exact index of [selected] within it.
    static func queue(startingAt selected: Song, allSongs: [Song], facts: [Int64: LibraryBrowseFact],
                      sort: LibrarySort? = nil) -> (songs: [Song], startIndex: Int) {
        let ordered = orderedAllSongs(allSongs: allSongs, facts: facts, sort: sort ?? currentSort())
        if let index = ordered.firstIndex(where: { $0.id == selected.id }) {
            return (ordered, index)
        }
        return ([selected], 0)
    }

    /// Remaining tracks after [song] in sorted All Songs (used if a short queue reaches its end while
    /// Continuous Playback is enabled).
    static func remaining(after song: Song, in allSongs: [Song], facts: [Int64: LibraryBrowseFact],
                          excluding existingIds: Set<Int64> = [], shuffled: Bool, sort: LibrarySort? = nil) -> [Song] {
        let ordered = orderedAllSongs(allSongs: allSongs, facts: facts, sort: sort ?? currentSort())
        if shuffled {
            return ordered.filter { $0.id != song.id && !existingIds.contains($0.id) }.shuffled()
        }
        guard let index = ordered.firstIndex(where: { $0.id == song.id }) else { return [] }
        let nextIndex = index + 1
        guard nextIndex < ordered.count else { return [] }
        return ordered[nextIndex...].filter { !existingIds.contains($0.id) }
    }
}
