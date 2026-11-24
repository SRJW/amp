import UIKit
import XCTest
@testable import Amp

final class LibraryCategoryTests: XCTestCase {
    func testHidingDoesNotLoseSavedOrderAndHiddenSectionsCanBeRestored() {
        let order = "albums,songs,playlists"
        let hidden = "albums,radio,albums,retired"
        XCTAssertEqual(LibraryCategory.hidden(hidden), [.albums, .radio])
        let visible = LibraryCategory.visible(order: order, hidden: hidden)
        XCTAssertEqual(Array(visible.prefix(2)), [.songs, .playlists])
        XCTAssertFalse(visible.contains(.albums))
        XCTAssertFalse(visible.contains(.radio))
        XCTAssertEqual(LibraryCategory.visible(order: order, hidden: "").first, .albums)
        let allHidden = LibraryCategory.allCases.map(\.rawValue).joined(separator: ",")
        XCTAssertTrue(LibraryCategory.visible(order: order, hidden: allHidden).isEmpty)
    }

    func testOldCategoryOrderRetainsEveryCategoryExactlyOnce() {
        let migrated = LibraryCategory.ordered("playlists,favorites,artists,songs,vybe,songs")
        XCTAssertEqual(Array(migrated.prefix(4)), [.playlists, .favorites, .artists, .songs])
        XCTAssertEqual(Set(migrated), Set(LibraryCategory.allCases))
        XCTAssertEqual(migrated.count, LibraryCategory.allCases.count)
    }

    func testAlphabetHandlesAccentsNumbersAndCurrentFilteredOrder() {
        let songs = [Song(id: 1, title: "Álbum", artist: "A", album: "B", durationMs: 1, path: "1.m4a"),
                     Song(id: 2, title: "Árbol", artist: "A", album: "B", durationMs: 1, path: "2.m4a"),
                     Song(id: 3, title: "3005", artist: "A", album: "B", durationMs: 1, path: "3.m4a")]
        XCTAssertEqual(SongAlphabet.anchors(songs), ["A": 1, "#": 3])
        XCTAssertEqual(SongAlphabet.anchors(Array(songs.reversed())), ["A": 2, "#": 3])
        XCTAssertEqual(SongAlphabet.anchors([songs[1]]), ["A": 2])
    }

    func testEmptyAlphabetLettersResolveToPopulatedGroupsIncludingTheEnds() {
        let anchors: [String: Int64] = ["H": 1, "Y": 2, "Z": 3]
        XCTAssertEqual(SongAlphabet.letters.first, "#", "The numeric group must match the start of the sorted song list")
        XCTAssertEqual(SongAlphabet.target(for: "A", anchors: anchors), 1)
        XCTAssertEqual(SongAlphabet.target(for: "M", anchors: anchors), 2)
        XCTAssertEqual(SongAlphabet.target(for: "Z", anchors: anchors), 3)
        XCTAssertEqual(SongAlphabet.target(for: "#", anchors: anchors), 1)
        XCTAssertNil(SongAlphabet.target(for: "A", anchors: [:]))
        XCTAssertNil(SongAlphabet.target(for: "?", anchors: anchors))
    }

    func testAdditionalSearchTypesRespectFolderPathsAndAlbumArtists() {
        let song = Song(id: 1, title: "Track", artist: "Guest", album: "Record", durationMs: 1, path: "Colección/track.m4a")
        let artist = Artist(id: 9, name: "Álvaro", songCount: 1, albumCount: 1)
        let playlist = Playlist(id: 2, name: "Colección", songCount: 1)
        let folders = LibrarySearchExtras.matching("coleccion", songs: [song], albumArtists: [artist], playlists: [playlist])
        XCTAssertEqual(folders.folders, ["Colección"])
        XCTAssertEqual(folders.playlists.map(\.id), [2])
        XCTAssertTrue(folders.albumArtists.isEmpty)
        let artists = LibrarySearchExtras.matching("alvaro", songs: [song], albumArtists: [artist], playlists: [playlist])
        XCTAssertEqual(artists.albumArtists.map(\.id), [9])
    }

    func testAlbumArtistsComeFromTheirRelationshipNotTheTrackCredit() throws {
        let database = try LibraryDatabase.inMemory()
        try database.db.execute("INSERT INTO album_artist_cross_ref (album_id, artist_id, position) VALUES (10, 9, 0), (11, 9, 0), (12, 8, 0)")
        XCTAssertEqual(try database.albumArtistAlbumIDs(), [9: Set([10, 11]), 8: Set([12])])
    }

    func testArtworkLoaderDiskCacheAndRevisionInvalidation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("amp-art-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("cover.png")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let png = renderer.pngData { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        try png.write(to: file)

        let loader = ArtworkLoader.shared
        let initialRev = loader.revision(for: file.path)
        let first = await loader.image(atPath: file.path, maxPixels: 144)
        XCTAssertNotNil(first)
        XCTAssertNotNil(loader.cachedImage(atPath: file.path, maxPixels: 144))

        loader.clearMemoryCache()
        XCTAssertNil(loader.cachedImage(atPath: file.path, maxPixels: 144))
        let fromDisk = await loader.image(atPath: file.path, maxPixels: 144)
        XCTAssertNotNil(fromDisk)

        loader.forget(path: file.path)
        XCTAssertEqual(loader.revision(for: file.path), initialRev + 1)
    }

    @MainActor func testSongAlphabetIndexAnchorsAndNegativeHashIDsInMenuAndThumbnails() {
        let negAlbumId: Int64 = -4_821_992_011
        let negArtistId: Int64 = -9_123_456_789
        let s1 = Song(id: 1, title: "  624 part1", artist: "fat jon", album: "departure", artistId: negArtistId, albumId: negAlbumId, durationMs: 180_000, path: "1.m4a")
        let s2 = Song(id: 2, title: "Álbum", artist: "fat jon", album: "departure", artistId: negArtistId, albumId: negAlbumId, durationMs: 180_000, path: "2.m4a")
        let s3 = Song(id: 3, title: "zebra", artist: "Z", album: "Z", artistId: 5, albumId: 6, durationMs: 180_000, path: "3.m4a")

        XCTAssertEqual(SongAlphabet.indexAnchors([s1, s2, s3], title: \.title), ["#": 0, "A": 1, "Z": 2])

        let album = Album(id: negAlbumId, title: "departure", artist: "fat jon", artistId: negArtistId, songCount: 2, year: 2004)
        let dedupURL = LibraryStore.thumbnailURL(for: s2, albumsById: [negAlbumId: album], albumCoverSong: [negAlbumId: s1])
        XCTAssertEqual(dedupURL, s1.url, "Negative FNV-1a album IDs must still deduplicate list thumbnails")

        let actions = SongActions(
            toggleFavorite: { _ in },
            playNext: { _ in },
            addToQueue: { _ in },
            startRadio: { _ in },
            addToPlaylist: { _ in },
            share: { _ in },
            goToAlbum: { _ in },
            goToArtist: { _ in },
            deleteFromDevice: { _ in }
        )
        let menu = makeAppleMusicSongMenu(song: s1, actions: actions)
        let flattened = menu.children.flatMap { ($0 as? UIMenu)?.children ?? [$0] }.compactMap { $0 as? UIAction }
        XCTAssertTrue(flattened.contains { $0.title == L("Go to album") && $0.subtitle == "departure" })
        XCTAssertTrue(flattened.contains { $0.title == L("Go to artist") && $0.subtitle == "fat jon" })
        XCTAssertTrue(flattened.contains { $0.title == L("Share") })
    }
}
