import XCTest
@testable import Amp

final class LibrarySearchTests: XCTestCase {
    private let artists: [Artist] = [
        Artist(id: 1, name: "Cults", songCount: 1, albumCount: 1),
        Artist(id: 2, name: "The Marías", songCount: 1, albumCount: 1),
        Artist(id: 3, name: "Drake", songCount: 2, albumCount: 1),
        Artist(id: 4, name: "王富贵", songCount: 1, albumCount: 1),
        Artist(id: 5, name: "김지수", songCount: 1, albumCount: 1),
        Artist(id: 6, name: "¥$", songCount: 1, albumCount: 1)
    ]
    private let albums: [Album] = [
        Album(id: 1, title: "Static", artist: "Cults", artistId: 1, songCount: 1, year: 2013),
        Album(id: 2, title: "Submarine", artist: "The Marías", artistId: 2, songCount: 1, year: 2024),
        Album(id: 3, title: "Take Care (Deluxe)", artist: "Drake", artistId: 3, songCount: 2, year: 2011),
        Album(id: 4, title: "生而平凡", artist: "王富贵", artistId: 4, songCount: 1, year: 2025),
        Album(id: 5, title: "The Trunk (Soundtrack)", artist: "김지수", artistId: 5, songCount: 1, year: 2025),
        Album(id: 6, title: "SKY CITY", artist: "¥$", artistId: 6, songCount: 1, year: 2025)
    ]
    private var songs: [Song] {
        let entries: [(Int64, String, Int)] = [(1, "Always Forever", 1), (2, "No One Noticed", 2), (3, "Headlines", 3), (4, "Over My Dead Body", 3),
         (5, "生而平凡", 4), (6, "Milonga with Lover", 5), (7, "SKY CITY", 6)]
        return entries.map { id, title, albumID in
            let album = albums[albumID - 1]
            return Song(id: Int64(id), title: title, artist: album.artist, album: album.title, artistId: album.artistId,
                        albumId: album.id, durationMs: 180_000, path: "\(id).mp3")
        }
    }
    private func find(_ query: String) -> LibrarySearchResults {
        LibrarySearch.results(query, songs: songs, albums: albums, artists: artists)
    }

    func testReportedAlbumQueriesNeverIncludeUnrelatedNonLatinArtistsOrTracks() {
        for (query, album, song) in [("Static", Int64(1), Int64(1)), ("Submarine", 2, 2), ("sttaic", 1, 1), ("submarien", 2, 2)] {
            let result = find(query)
            XCTAssertTrue(result.artists.isEmpty, query)
            XCTAssertEqual(result.albums.map(\.id), [album], query)
            XCTAssertEqual(result.songs.map(\.id), [song], query)
        }
        XCTAssertEqual(find("Take care").songs.map(\.id), [3, 4])
    }

    func testArtistQueriesExpandOnlyThatArtistsAlbumsAndSongs() {
        for query in ["Drake", "Drkae", "The Marias"] {
            let result = find(query)
            let id: Int64 = query == "The Marias" ? 2 : 3
            XCTAssertEqual(result.artists.map(\.id), [id])
            XCTAssertEqual(result.albums.map(\.id), [id])
            XCTAssertEqual(result.songs.map(\.id), id == 2 ? [2] : [3, 4])
        }
    }

    func testSongQueryShowsItsAlbumWithoutExpandingTheOtherTracks() {
        for query in ["Headlines", "Hedlines", "headlines drkae"] {
            let result = find(query)
            XCTAssertTrue(result.artists.isEmpty)
            XCTAssertEqual(result.albums.map(\.id), [3], query)
            XCTAssertEqual(result.songs.map(\.id), [3], query)
        }
    }

    func testUnicodeAndNumbersArePreservedAndEmptyNamesNeverMatch() {
        XCTAssertEqual(find("王富贵").artists.map(\.id), [4])
        XCTAssertEqual(find("김지수").songs.map(\.id), [6])
        XCTAssertFalse(SearchNormalizer.matches("王富贵", "static"))
        XCTAssertFalse(SearchNormalizer.matches("¥$", "submarine"))
        XCTAssertFalse(SearchNormalizer.matches("", "anything"))
        XCTAssertFalse(SearchNormalizer.matches("2021", "2020"))
        XCTAssertTrue(SearchNormalizer.matches("$ome $exy $ongs 4 U", "some sexy"))
        XCTAssertTrue(find("!!!").songs.isEmpty)
    }

    func testPrefixQueryNeverDropsInnerbloomBehindCompetingArtistsAlbumsOrExactSongs() {
        let testArtists = [
            Artist(id: 10, name: "Inner City", songCount: 1, albumCount: 1),
            Artist(id: 11, name: "RÜFÜS DU SOL", songCount: 1, albumCount: 1)
        ]
        let testAlbums = [
            Album(id: 10, title: "Inner World", artist: "Inner City", artistId: 10, songCount: 1, year: 2019),
            Album(id: 11, title: "Bloom", artist: "RÜFÜS DU SOL", artistId: 11, songCount: 1, year: 2016)
        ]
        let testSongs = [
            Song(id: 10, title: "Inner", artist: "Inner City", album: "Inner World", artistId: 10, albumId: 10, durationMs: 200_000, path: "10.mp3"),
            Song(id: 11, title: "Innerbloom", artist: "RÜFÜS DU SOL", album: "Bloom", artistId: 11, albumId: 11, durationMs: 578_000, path: "11.mp3"),
            Song(id: 12, title: "A Winner", artist: "Inner City", album: "Inner World", artistId: 10, albumId: 10, durationMs: 180_000, path: "12.mp3")
        ]

        let result = LibrarySearch.results("inner", songs: testSongs, albums: testAlbums, artists: testArtists)
        XCTAssertEqual(result.songs.prefix(2).map(\.id), [10, 11], "Both exact 'Inner' and prefix 'Innerbloom' must appear immediately for 'inner'")
        XCTAssertEqual(result.artists.map(\.id), [10])
        XCTAssertTrue(result.albums.map(\.id).contains(10))
        XCTAssertTrue(result.albums.map(\.id).contains(11))
        XCTAssertEqual(result.topCategory, .songs)

        // Even with a single competing artist/album prefix match and no exact song, Innerbloom is #1
        let withoutExact = LibrarySearch.results("inner", songs: [testSongs[1], testSongs[2]], albums: testAlbums, artists: testArtists)
        XCTAssertEqual(withoutExact.songs.first?.id, 11)
        XCTAssertEqual(withoutExact.topCategory, .songs)
    }

    func testPrefixTyposCrossFieldQueriesAndAcronyms() {
        let testArtists = [
            Artist(id: 11, name: "RÜFÜS DU SOL", songCount: 1, albumCount: 1),
            Artist(id: 12, name: "Other", songCount: 1, albumCount: 1)
        ]
        let testAlbums = [
            Album(id: 11, title: "Bloom", artist: "RÜFÜS DU SOL", artistId: 11, songCount: 1, year: 2016),
            Album(id: 12, title: "Fire", artist: "Other", artistId: 12, songCount: 1, year: 2020)
        ]
        let testSongs = [
            Song(id: 11, title: "Innerbloom", artist: "RÜFÜS DU SOL", album: "Bloom", artistId: 11, albumId: 11, durationMs: 578_000, path: "11.mp3"),
            Song(id: 12, title: "Hellfire", artist: "Other", album: "Fire", artistId: 12, albumId: 12, durationMs: 200_000, path: "12.mp3")
        ]

        // Prefix typos while typing ("inerb", "innner") find Innerbloom
        XCTAssertEqual(LibrarySearch.results("inerb", songs: testSongs, albums: testAlbums, artists: testArtists).songs.first?.id, 11)
        XCTAssertEqual(LibrarySearch.results("innner", songs: testSongs, albums: testAlbums, artists: testArtists).songs.first?.id, 11)
        // Guard against false trailing-letter prefix matches ("hello" must not match "Hellfire")
        XCTAssertFalse(SearchNormalizer.matches("Hellfire", "hello"))

        // Multi-word cross-field search ("rufus inner", "bloom rufus")
        XCTAssertEqual(LibrarySearch.results("rufus inner", songs: testSongs, albums: testAlbums, artists: testArtists).songs.first?.id, 11)
        XCTAssertEqual(LibrarySearch.results("bloom rufus", songs: testSongs, albums: testAlbums, artists: testArtists).songs.first?.id, 11)

        // Acronym / initials matching ("omdb" -> "Over My Dead Body")
        XCTAssertEqual(find("omdb").songs.first?.id, 4)
    }

    func testSongBrowseRequestRanksPrefixMatchesAboveAlphabeticallyEarlierSubstrings() {
        let tracks = [
            Song(id: 1, title: "A Winner", artist: "Alpha", album: "Album", albumId: 1, durationMs: 180_000, path: "1.mp3"),
            Song(id: 2, title: "Innerbloom", artist: "RÜFÜS DU SOL", album: "Bloom", albumId: 2, durationMs: 578_000, path: "2.mp3"),
            Song(id: 3, title: "Dinner Time", artist: "Beta", album: "Album", albumId: 3, durationMs: 180_000, path: "3.mp3")
        ]
        let results = SongBrowseRequest(songs: tracks, facts: [:], query: "inner", sort: .title).results()
        XCTAssertEqual(results.first?.id, 2, "Prefix match 'Innerbloom' should rank ahead of substring matches like 'A Winner'")
    }
}
