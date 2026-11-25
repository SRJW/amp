import Foundation

enum SearchType: String, CaseIterable, Identifiable {
    case all = "All", songs = "Songs", albums = "Albums", artists = "Artists", albumArtists = "Album Artists", folders = "Folders", playlists = "Playlists"
    var id: String { rawValue }
}

enum SearchTopCategory: Sendable, Equatable {
    case artists, albums, songs
}

struct LibrarySearchExtras: Sendable {
    var albumArtists: [Artist] = []
    var folders: [String] = []
    var playlists: [Playlist] = []

    static func matching(_ query: String, songs: [Song], albumArtists: [Artist], playlists: [Playlist]) -> Self {
        let prepared = PreparedSearchQuery(query)
        guard !prepared.isEmpty else { return Self() }
        let matchedArtists = albumArtists
            .compactMap { artist -> (Artist, Int)? in
                let s = SearchNormalizer.score(NormalizedSearchText(artist.name), prepared)
                return s > 0 ? (artist, s) : nil
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.name.count != b.0.name.count { return a.0.name.count < b.0.name.count }
                return a.0.id < b.0.id
            }
            .map(\.0)
        let matchedFolders = Set(songs.map { ($0.path as NSString).deletingLastPathComponent })
            .compactMap { folder -> (String, Int)? in
                let s = SearchNormalizer.score(NormalizedSearchText(folder), prepared)
                return s > 0 ? (folder, s) : nil
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0 < b.0
            }
            .map(\.0)
        let matchedPlaylists = playlists
            .compactMap { playlist -> (Playlist, Int)? in
                let s = SearchNormalizer.score(NormalizedSearchText(playlist.name), prepared)
                return s > 0 ? (playlist, s) : nil
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.name.count != b.0.name.count { return a.0.name.count < b.0.name.count }
                return a.0.id < b.0.id
            }
            .map(\.0)
        return Self(albumArtists: matchedArtists, folders: matchedFolders, playlists: matchedPlaylists)
    }

    static func matching(_ prepared: PreparedSearchQuery, index: LibrarySearchIndex) -> Self {
        guard !prepared.isEmpty else { return Self() }
        let matchedArtists = index.albumArtists
            .compactMap { entry -> (Artist, Int)? in
                let s = SearchNormalizer.score(entry.name, prepared)
                return s > 0 ? (entry.artist, s) : nil
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.name.count != b.0.name.count { return a.0.name.count < b.0.name.count }
                return a.0.id < b.0.id
            }
            .map(\.0)
        let matchedFolders = index.folders
            .compactMap { entry -> (String, Int)? in
                let s = SearchNormalizer.score(entry.text, prepared)
                return s > 0 ? (entry.path, s) : nil
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0 < b.0
            }
            .map(\.0)
        let matchedPlaylists = index.playlists
            .compactMap { entry -> (Playlist, Int)? in
                let s = SearchNormalizer.score(entry.name, prepared)
                return s > 0 ? (entry.playlist, s) : nil
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.name.count != b.0.name.count { return a.0.name.count < b.0.name.count }
                return a.0.id < b.0.id
            }
            .map(\.0)
        return Self(albumArtists: matchedArtists, folders: matchedFolders, playlists: matchedPlaylists)
    }
}

/// Pre-normalized in-memory index built once per library content revision so every keystroke
/// searches thousands of songs, albums, artists, folders, and playlists in ~1–2 ms.
struct LibrarySearchIndex: Sendable {
    struct SongEntry: Sendable {
        let song: Song
        let title: NormalizedSearchText
        let artist: NormalizedSearchText
        let album: NormalizedSearchText
        let genre: NormalizedSearchText
        let artistKeys: Set<String>
    }

    struct AlbumEntry: Sendable {
        let album: Album
        let title: NormalizedSearchText
        let baseTitle: NormalizedSearchText?
        let artist: NormalizedSearchText
    }

    struct ArtistEntry: Sendable {
        let artist: Artist
        let name: NormalizedSearchText
    }

    struct PlaylistEntry: Sendable {
        let playlist: Playlist
        let name: NormalizedSearchText
    }

    struct FolderEntry: Sendable {
        let path: String
        let text: NormalizedSearchText
    }

    let revision: Int
    let songs: [SongEntry]
    let albums: [AlbumEntry]
    let artists: [ArtistEntry]
    let albumArtists: [ArtistEntry]
    let playlists: [PlaylistEntry]
    let folders: [FolderEntry]

    private static let editionRegex = Regex16(#"\s*[(\[][^)\]]*(?:deluxe|expanded|anniversary|edition)[^)\]]*[)\]]"#, ignoreCase: true)

    init(revision: Int = 0, songs: [Song], albums: [Album], artists: [Artist], albumArtists: [Artist] = [], playlists: [Playlist] = []) {
        self.revision = revision
        var folderSet = Set<String>()
        self.songs = songs.map { song in
            let folder = (song.path as NSString).deletingLastPathComponent
            folderSet.insert(folder)
            let artistKeys = Set(MusicQueryIntent.artists(song.artist).map { SearchNormalizer.normalize($0) })
            return SongEntry(
                song: song,
                title: NormalizedSearchText(song.title),
                artist: NormalizedSearchText(song.artist),
                album: NormalizedSearchText(song.album),
                genre: NormalizedSearchText(song.genre ?? ""),
                artistKeys: artistKeys
            )
        }
        self.albums = albums.map { album in
            let stripped = Self.editionRegex.replacing(in: album.title, with: "")
            let base = stripped != album.title ? NormalizedSearchText(stripped) : nil
            return AlbumEntry(
                album: album,
                title: NormalizedSearchText(album.title),
                baseTitle: base,
                artist: NormalizedSearchText(album.artist)
            )
        }
        self.artists = artists.map { ArtistEntry(artist: $0, name: NormalizedSearchText($0.name)) }
        self.albumArtists = albumArtists.map { ArtistEntry(artist: $0, name: NormalizedSearchText($0.name)) }
        self.playlists = playlists.map { PlaylistEntry(playlist: $0, name: NormalizedSearchText($0.name)) }
        self.folders = folderSet.sorted().map { FolderEntry(path: $0, text: NormalizedSearchText($0)) }
    }
}

/// Ranked results across artists, albums, and songs, preserving strong matches across every category
/// while surfacing the highest-confidence category first.
struct LibrarySearchResults: Sendable {
    var artists: [Artist] = []
    var albums: [Album] = []
    var songs: [Song] = []
    var topCategory: SearchTopCategory = .songs
}

enum LibrarySearch {
    static func results(_ query: String, songs: [Song], albums: [Album], artists: [Artist]) -> LibrarySearchResults {
        let prepared = PreparedSearchQuery(query)
        guard !prepared.isEmpty else { return LibrarySearchResults() }
        let index = LibrarySearchIndex(songs: songs, albums: albums, artists: artists)
        return results(prepared, index: index)
    }

    static func results(_ prepared: PreparedSearchQuery, index: LibrarySearchIndex) -> LibrarySearchResults {
        guard !prepared.isEmpty else { return LibrarySearchResults() }

        // 1. Score all artists
        var rankedArtists: [(LibrarySearchIndex.ArtistEntry, Int)] = []
        for entry in index.artists {
            let s = SearchNormalizer.score(entry.name, prepared)
            if s > 0 { rankedArtists.append((entry, s)) }
        }
        rankedArtists.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.artist.name.count != b.0.artist.name.count { return a.0.artist.name.count < b.0.artist.name.count }
            return a.0.artist.id < b.0.artist.id
        }

        // 2. Score all albums (title, stripped edition title, and multi-token title+artist)
        var rankedAlbums: [(LibrarySearchIndex.AlbumEntry, Int)] = []
        for entry in index.albums {
            let titleScore = SearchNormalizer.score(entry.title, prepared)
            let editionScore = entry.baseTitle.map { SearchNormalizer.score($0, prepared) >= 100 ? 98 : 0 } ?? 0
            let crossScore = prepared.tokens.count >= 2
                ? SearchNormalizer.multiFieldScore(primary: entry.title, secondary: [entry.artist], query: prepared)
                : 0
            let best = max(titleScore, editionScore, crossScore)
            if best > 0 { rankedAlbums.append((entry, best)) }
        }
        rankedAlbums.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.album.title.count != b.0.album.title.count { return a.0.album.title.count < b.0.album.title.count }
            return a.0.album.id < b.0.album.id
        }

        // 3. Score all songs directly on title (and multi-word across title + artist + album + genre)
        var directSongs: [(entry: LibrarySearchIndex.SongEntry, score: Int, titleScore: Int)] = []
        for entry in index.songs {
            let titleScore = SearchNormalizer.score(entry.title, prepared)
            let crossScore: Int
            if prepared.tokens.count >= 2 {
                crossScore = SearchNormalizer.multiFieldScore(
                    primary: entry.title,
                    secondary: [entry.artist, entry.album, entry.genre],
                    query: prepared
                )
            } else {
                crossScore = 0
            }
            let best = max(titleScore, crossScore)
            if best > 0 { directSongs.append((entry, best, titleScore)) }
        }
        directSongs.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.titleScore != b.titleScore { return a.titleScore > b.titleScore }
            if a.entry.song.title.count != b.entry.song.title.count { return a.entry.song.title.count < b.entry.song.title.count }
            return a.entry.song.id < b.entry.song.id
        }

        let artistScore = rankedArtists.first?.1 ?? 0
        let albumScore = rankedAlbums.first?.1 ?? 0
        let songScore = directSongs.first?.score ?? 0
        guard max(artistScore, albumScore, songScore) > 0 else { return LibrarySearchResults() }

        func orderedByTrack(_ items: [Song]) -> [Song] {
            items.sorted {
                if $0.albumId != $1.albumId { return $0.albumId < $1.albumId }
                if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
                if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
                return $0.id < $1.id
            }
        }

        let topCategory: SearchTopCategory
        if artistScore == 100 || (artistScore > songScore && artistScore >= albumScore) {
            topCategory = .artists
        } else if albumScore >= 98 || (albumScore > songScore && albumScore > artistScore) {
            topCategory = .albums
        } else {
            topCategory = .songs
        }

        // Collect all matched artists (never erasing lower-tier real matches)
        let matchedArtists = rankedArtists.map(\.0.artist)

        // Expand songs belonging to directly matched artists and directly matched albums
        let matchedArtistIDs = Set(matchedArtists.map(\.id))
        let matchedArtistKeys = Set(rankedArtists.map(\.0.name.packed))
        let directAlbumIDs = Set(rankedAlbums.map(\.0.album.id))

        let artistRelatedSongs: [Song] = matchedArtists.isEmpty ? [] : orderedByTrack(
            index.songs.compactMap { entry in
                if matchedArtistIDs.contains(entry.song.artistId) || !entry.artistKeys.isDisjoint(with: matchedArtistKeys) {
                    return entry.song
                }
                return nil
            }
        )

        let albumRelatedSongs: [Song] = directAlbumIDs.isEmpty ? [] : orderedByTrack(
            index.songs.compactMap { entry in
                directAlbumIDs.contains(entry.song.albumId) ? entry.song : nil
            }
        )

        // Merge songs cleanly without duplicates:
        // - Direct song title matches (prefix/exact) stay visible at the top of Songs even when an artist or album also matched.
        // - Pure artist/album queries (no song title match) keep expanded tracks in clean disc/track order.
        var seenSongIDs = Set<Int64>()
        var combinedSongs: [Song] = []
        func appendUnique(_ list: [Song]) {
            for song in list where seenSongIDs.insert(song.id).inserted {
                combinedSongs.append(song)
            }
        }

        let strongTitleSongs = directSongs.filter { $0.titleScore >= 90 }.map(\.entry.song)
        let allDirectSongs = directSongs.map(\.entry.song)

        if topCategory == .songs {
            appendUnique(allDirectSongs)
            appendUnique(artistRelatedSongs)
            appendUnique(albumRelatedSongs)
        } else if topCategory == .artists {
            appendUnique(strongTitleSongs)
            appendUnique(artistRelatedSongs)
            appendUnique(allDirectSongs)
            appendUnique(albumRelatedSongs)
        } else {
            appendUnique(strongTitleSongs)
            appendUnique(albumRelatedSongs)
            appendUnique(allDirectSongs)
            appendUnique(artistRelatedSongs)
        }

        // Merge albums cleanly without duplicates:
        // Directly matched albums first, then albums of matched artists, then parent albums of direct song matches.
        let albumsByID = Dictionary(uniqueKeysWithValues: index.albums.map { ($0.album.id, $0.album) })
        var seenAlbumIDs = Set<Int64>()
        var combinedAlbums: [Album] = []
        func appendAlbum(_ album: Album) {
            if seenAlbumIDs.insert(album.id).inserted {
                combinedAlbums.append(album)
            }
        }
        for (entry, _) in rankedAlbums { appendAlbum(entry.album) }
        for song in artistRelatedSongs {
            if let album = albumsByID[song.albumId] { appendAlbum(album) }
        }
        for item in directSongs {
            if let album = albumsByID[item.entry.song.albumId] { appendAlbum(album) }
        }

        return LibrarySearchResults(
            artists: matchedArtists,
            albums: combinedAlbums,
            songs: combinedSongs,
            topCategory: topCategory
        )
    }
}
