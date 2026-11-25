import Foundation
import Observation

/// The library as the screens see it, reloaded whenever the database changes (Android's
/// LibraryRepository flows). Scans run off the main thread.
@MainActor
@Observable
final class LibraryStore {
    private(set) var songs: [Song] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var albumArtistAlbums: [Int64: Set<Int64>] = [:]
    var albumArtists: [Artist] { artists.filter { albumArtistAlbums[$0.id] != nil } }
    private(set) var playlists: [Playlist] = []
    private(set) var browseFacts: [Int64: LibraryBrowseFact] = [:]
    private(set) var albumLastPlayed: [Int64: Int64] = [:]
    private(set) var favorites: [Song] = []
    private(set) var recentAlbums: [Album] = []
    private(set) var recentlyAddedAlbums: [Album] = []
    private(set) var recentPlaylists: [Playlist] = []
    private(set) var featuredAlbums: [Album] = []
    /// Each album's cover comes from its first song's embedded art.
    private(set) var albumCoverSong: [Int64: Song] = [:]
    /// Lightweight monotonically increasing tokens for O(1) `.task(id:)` invalidation (avoids O(N) array equality on MainActor).
    private(set) var contentRevision = 0
    private(set) var statsRevision = 0
    private(set) var scanProgress: ScanProgress?
    private(set) var errorMessage: String?
    var isShowingError = false

    let database: LibraryDatabase
    struct CachedAllSongs: Sendable {
        let sortRaw: String
        let songs: [Song]
        let rows: [NativeSongRow]
        let anchors: [String: Int]
    }

    struct CachedEntityGrid: Sendable {
        let items: [NativeEntityItem]
        let anchors: [String: Int]
        let songs: [Song]
    }

    private(set) var precomputedAllSongs: CachedAllSongs?
    @ObservationIgnored private var allSongsCache: [String: CachedAllSongs] = [:]
    @ObservationIgnored private var entityGridCache: [String: CachedEntityGrid] = [:]
    @ObservationIgnored private var albumsById: [Int64: Album] = [:]
    @ObservationIgnored private var artistsById: [Int64: Artist] = [:]
    @ObservationIgnored private var playlistsById: [Int64: Playlist] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var folderWatcher: MusicFolderWatcher?
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored private var forcedRescanRequested = false
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var pendingNeedsCatalog = false
    @ObservationIgnored private var reloadGeneration: UInt64 = 0

    var isScanning: Bool { scanProgress != nil }

    /// The Recently Played shelves' length.
    static let recentShelfLimit = 12
    /// The Library home screen's Recently Added album grid length.
    static let recentlyAddedAlbumLimit = 24

    private static let catalogTables: Set<String> = ["songs", "albums", "artists", "playlists", "playlist_song_cross_ref", "artist_artwork", "library_imports"]
    private static let allWatchedTables: Set<String> = catalogTables.union(["recently_played", "listening_stats"])

    func album(_ id: Int64) -> Album? { albumsById[id] }
    func artist(_ id: Int64) -> Artist? { artistsById[id] }
    func playlist(_ id: Int64) -> Playlist? { playlistsById[id] }

    func cachedAllSongs(for sort: LibrarySort) -> CachedAllSongs? {
        if let pre = precomputedAllSongs, pre.sortRaw == sort.rawValue { return pre }
        return allSongsCache[sort.rawValue]
    }

    func storeCachedAllSongs(_ cached: CachedAllSongs) {
        allSongsCache[cached.sortRaw] = cached
    }

    func cachedEntityGrid(category: LibraryCategory, sortRaw: String) -> CachedEntityGrid? {
        entityGridCache["\(category.rawValue)|\(sortRaw)"]
    }

    func storeCachedEntityGrid(_ cached: CachedEntityGrid, category: LibraryCategory, sortRaw: String) {
        entityGridCache["\(category.rawValue)|\(sortRaw)"] = cached
    }

    /// Starts kernel-level folder monitoring so files added via Files, AirDrop, or Finder appear live.
    func startWatchingMusicFolder() {
        if folderWatcher == nil {
            folderWatcher = MusicFolderWatcher { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scan()
                }
            }
        }
        folderWatcher?.start()
    }

    func stopWatchingMusicFolder() {
        folderWatcher?.stop()
    }

    /// Deduplicates list thumbnails by album cover when a track belongs to a non-compilation album,
    /// reducing RAM, disk reads, and JPEG decodes by ~10-15x during fast scrolling while keeping
    /// per-track artwork for compilations, unknown albums, and Now Playing.
    func listThumbnailURL(for song: Song) -> URL {
        Self.thumbnailURL(for: song, albumsById: albumsById, albumCoverSong: albumCoverSong)
    }

    nonisolated static func thumbnailURL(for song: Song, albumsById: [Int64: Album], albumCoverSong: [Int64: Song]) -> URL {
        if song.albumId != 0,
           let album = albumsById[song.albumId],
           !album.isCompilation,
           !song.album.isBlank,
           song.album != unknownAlbum,
           let coverSong = albumCoverSong[song.albumId] {
            return coverSong.url
        }
        return song.url
    }

    init(database: LibraryDatabase) {
        self.database = database
        reload()
        observer = NotificationCenter.default.addObserver(forName: SQLiteDatabase.didChange, object: database.db, queue: .main) { [weak self] note in
            guard SQLiteDatabase.affects(note, tables: Self.allWatchedTables) else { return }
            let catalogChanged = SQLiteDatabase.affects(note, tables: Self.catalogTables)
            MainActor.assumeIsolated { self?.scheduleReload(catalogChanged: catalogChanged) }
        }
    }

    private struct CatalogSnapshot: Sendable {
        let songs: [Song]
        let albums: [Album]
        let artists: [Artist]
        let albumArtistAlbums: [Int64: Set<Int64>]
        let playlists: [Playlist]
        let favorites: [Song]
        let albumCoverSong: [Int64: Song]
        let albumsById: [Int64: Album]
        let artistsById: [Int64: Artist]
        let playlistsById: [Int64: Playlist]
    }

    private struct StatsSnapshot: Sendable {
        let browseFacts: [Int64: LibraryBrowseFact]
        let albumLastPlayed: [Int64: Int64]
        let recentAlbums: [Album]
        let recentlyAddedAlbums: [Album]
        let recentPlaylists: [Playlist]
        let featuredAlbums: [Album]
    }

    nonisolated static func buildCachedAllSongs(
        songs: [Song],
        facts: [Int64: LibraryBrowseFact],
        albumsById: [Int64: Album],
        albumCoverSong: [Int64: Song],
        sort: LibrarySort
    ) -> CachedAllSongs {
        let sorted = SongBrowseRequest(songs: songs, facts: facts, query: "", sort: sort).results()
        let rows = sorted.map { song in
            let thumb = thumbnailURL(for: song, albumsById: albumsById, albumCoverSong: albumCoverSong)
            return NativeSongRow.build(song: song, thumbnailURL: thumb)
        }
        let anchors: [String: Int]
        switch sort {
        case .artist: anchors = SongAlphabet.indexAnchors(sorted, title: \.artist)
        case .album: anchors = SongAlphabet.indexAnchors(sorted, title: \.album)
        default: anchors = SongAlphabet.indexAnchors(sorted, title: \.title)
        }
        return CachedAllSongs(sortRaw: sort.rawValue, songs: sorted, rows: rows, anchors: anchors)
    }

    private nonisolated static func computeRecentlyAddedAlbums(
        albums: [Album],
        songs: [Song],
        facts: [Int64: LibraryBrowseFact]
    ) -> [Album] {
        guard !albums.isEmpty else { return [] }
        var latestByAlbum: [Int64: Int64] = [:]
        latestByAlbum.reserveCapacity(albums.count)
        for song in songs {
            let added = facts[song.id]?.addedAt ?? song.dateModified
            if let existing = latestByAlbum[song.albumId] {
                if added > existing { latestByAlbum[song.albumId] = added }
            } else {
                latestByAlbum[song.albumId] = added
            }
        }
        let sorted = albums.sorted { a, b in
            let aa = latestByAlbum[a.id] ?? 0
            let ab = latestByAlbum[b.id] ?? 0
            if aa != ab { return aa > ab }
            let cmp = a.title.localizedStandardCompare(b.title)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return a.id < b.id
        }
        return Array(sorted.prefix(Self.recentlyAddedAlbumLimit))
    }

    private nonisolated static func readCatalog(from database: LibraryDatabase) throws -> CatalogSnapshot {
        let songs = try database.allSongs()
        let albums = try database.allAlbums()
        let artists = try database.allArtists()
        let albumArtistAlbums = try database.albumArtistAlbumIDs()
        let playlists = try database.playlists()
        let favorites = try database.favoriteSongs()
        var covers: [Int64: Song] = [:]
        covers.reserveCapacity(albums.count)
        for song in songs.sorted(by: { ($0.discNumber, $0.trackNumber, $0.id) < ($1.discNumber, $1.trackNumber, $1.id) })
        where covers[song.albumId] == nil {
            covers[song.albumId] = song
        }
        let albumsById = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let artistsById = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let playlistsById = Dictionary(playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return CatalogSnapshot(
            songs: songs, albums: albums, artists: artists,
            albumArtistAlbums: albumArtistAlbums, playlists: playlists, favorites: favorites,
            albumCoverSong: covers, albumsById: albumsById, artistsById: artistsById, playlistsById: playlistsById
        )
    }

    private nonisolated static func readStats(from database: LibraryDatabase, albums: [Album], songs: [Song]) throws -> StatsSnapshot {
        let browseFacts = try database.libraryBrowseFacts()
        let albumLastPlayed = try database.albumPlaybackTimes()
        let recentAlbums = try database.recentAlbums(limit: Self.recentShelfLimit)
        let recentlyAddedAlbums = computeRecentlyAddedAlbums(albums: albums, songs: songs, facts: browseFacts)
        let recentPlaylists = try database.recentPlaylists(limit: Self.recentShelfLimit)
        let epochDay = Int64(floor(Date().timeIntervalSince1970 / 86_400))
        let tracks = try database.trackFacts()
        let plays = try database.monthlyPlays()
        let featuredAlbums = FeaturedAlbums.select(albums: albums, tracks: tracks, plays: plays,
                                                   exclude: Set(recentAlbums.map(\.id)), epochDay: epochDay)
        return StatsSnapshot(
            browseFacts: browseFacts, albumLastPlayed: albumLastPlayed,
            recentAlbums: recentAlbums, recentlyAddedAlbums: recentlyAddedAlbums,
            recentPlaylists: recentPlaylists, featuredAlbums: featuredAlbums
        )
    }

    private func apply(catalog: CatalogSnapshot?, stats: StatsSnapshot, precomputed: CachedAllSongs? = nil,
                       precomputedRecent: CachedAllSongs? = nil) {
        var catalogDidChange = false
        if let catalog {
            albumsById = catalog.albumsById
            artistsById = catalog.artistsById
            playlistsById = catalog.playlistsById
            if songs != catalog.songs { songs = catalog.songs; catalogDidChange = true }
            if albums != catalog.albums { albums = catalog.albums; catalogDidChange = true }
            if artists != catalog.artists { artists = catalog.artists; catalogDidChange = true }
            if albumArtistAlbums != catalog.albumArtistAlbums { albumArtistAlbums = catalog.albumArtistAlbums; catalogDidChange = true }
            if playlists != catalog.playlists { playlists = catalog.playlists; catalogDidChange = true }
            if favorites != catalog.favorites { favorites = catalog.favorites; catalogDidChange = true }
            if albumCoverSong != catalog.albumCoverSong { albumCoverSong = catalog.albumCoverSong; catalogDidChange = true }
            if catalogDidChange {
                allSongsCache.removeAll()
                entityGridCache.removeAll()
                contentRevision &+= 1
            }
        }
        var statsDidChange = false
        var recentAddedChanged = false
        if browseFacts != stats.browseFacts { browseFacts = stats.browseFacts; statsDidChange = true }
        if albumLastPlayed != stats.albumLastPlayed { albumLastPlayed = stats.albumLastPlayed; statsDidChange = true }
        if recentAlbums != stats.recentAlbums { recentAlbums = stats.recentAlbums; statsDidChange = true }
        if recentlyAddedAlbums != stats.recentlyAddedAlbums {
            recentlyAddedAlbums = stats.recentlyAddedAlbums
            statsDidChange = true
            recentAddedChanged = true
        }
        if recentPlaylists != stats.recentPlaylists { recentPlaylists = stats.recentPlaylists; statsDidChange = true }
        if featuredAlbums != stats.featuredAlbums { featuredAlbums = stats.featuredAlbums; statsDidChange = true }
        if statsDidChange {
            // Only clear stats-sensitive sorts when stats change.
            allSongsCache.removeValue(forKey: LibrarySort.recentlyAdded.rawValue)
            allSongsCache.removeValue(forKey: LibrarySort.recentlyPlayed.rawValue)
            allSongsCache.removeValue(forKey: LibrarySort.mostPlayed.rawValue)
            entityGridCache.removeAll()
            statsRevision &+= 1
        }
        if let precomputed {
            precomputedAllSongs = precomputed
            allSongsCache[precomputed.sortRaw] = precomputed
        } else if catalogDidChange {
            precomputedAllSongs = nil
        }
        if let precomputedRecent {
            allSongsCache[precomputedRecent.sortRaw] = precomputedRecent
        }
        if recentAddedChanged || catalogDidChange {
            let coverURLs = recentlyAddedAlbums.compactMap { albumCoverSong[$0.id]?.url }
            if !coverURLs.isEmpty {
                ArtworkLoader.shared.prefetch(urls: coverURLs, maxPixels: 320)
            }
        }
    }

    /// Synchronous reload (used at launch and by deterministic unit tests).
    func reload() {
        pendingReload?.cancel()
        pendingReload = nil
        pendingNeedsCatalog = false
        reloadGeneration &+= 1
        do {
            let catalog = try Self.readCatalog(from: database)
            let stats = try Self.readStats(from: database, albums: catalog.albums, songs: catalog.songs)
            apply(catalog: catalog, stats: stats)
            // Warm the active All Songs sort and Recently Added off the main thread immediately after launch.
            let activeSort = ContinuousPlayback.currentSort()
            let songs = catalog.songs
            let facts = stats.browseFacts
            let albumsMap = catalog.albumsById
            let covers = catalog.albumCoverSong
            let expectedRev = contentRevision
            Task.detached(priority: .userInitiated) { [weak self] in
                let warmed = Self.buildCachedAllSongs(songs: songs, facts: facts, albumsById: albumsMap, albumCoverSong: covers, sort: activeSort)
                let warmedRecent = activeSort == .recentlyAdded
                    ? warmed
                    : Self.buildCachedAllSongs(songs: songs, facts: facts, albumsById: albumsMap, albumCoverSong: covers, sort: .recentlyAdded)
                await MainActor.run {
                    guard let self, self.contentRevision == expectedRev else { return }
                    self.precomputedAllSongs = warmed
                    self.allSongsCache[warmed.sortRaw] = warmed
                    self.allSongsCache[warmedRecent.sortRaw] = warmedRecent
                }
            }
        } catch {
            report("Couldn't read the library: \(error)")
        }
    }

    /// Coalesced off-main-thread reload triggered by database notifications so playback stats
    /// checkpoints and background scans never stall 60/120 Hz scrolling.
    private func scheduleReload(catalogChanged: Bool) {
        pendingNeedsCatalog = pendingNeedsCatalog || catalogChanged
        pendingReload?.cancel()
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let database = self.database
        let cachedAlbums = self.albums
        let cachedSongs = self.songs
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled, let self, self.reloadGeneration == generation else { return }
            let needsCatalog = self.pendingNeedsCatalog
            self.pendingNeedsCatalog = false
            let activeSort = ContinuousPlayback.currentSort()
            do {
                let result: (CatalogSnapshot?, StatsSnapshot, CachedAllSongs?, CachedAllSongs?) = try await Task.detached(priority: .userInitiated) {
                    if needsCatalog {
                        let catalog = try Self.readCatalog(from: database)
                        let stats = try Self.readStats(from: database, albums: catalog.albums, songs: catalog.songs)
                        let warmed = Self.buildCachedAllSongs(
                            songs: catalog.songs, facts: stats.browseFacts,
                            albumsById: catalog.albumsById, albumCoverSong: catalog.albumCoverSong, sort: activeSort
                        )
                        let warmedRecent = activeSort == .recentlyAdded
                            ? warmed
                            : Self.buildCachedAllSongs(
                                songs: catalog.songs, facts: stats.browseFacts,
                                albumsById: catalog.albumsById, albumCoverSong: catalog.albumCoverSong, sort: .recentlyAdded
                            )
                        return (catalog, stats, warmed, warmedRecent)
                    } else {
                        let stats = try Self.readStats(from: database, albums: cachedAlbums, songs: cachedSongs)
                        return (nil, stats, nil, nil)
                    }
                }.value
                guard !Task.isCancelled, self.reloadGeneration == generation else { return }
                self.pendingReload = nil
                self.apply(catalog: result.0, stats: result.1, precomputed: result.2, precomputedRecent: result.3)
            } catch {
                guard !Task.isCancelled, self.reloadGeneration == generation else { return }
                self.pendingReload = nil
                self.report("Couldn't read the library: \(error)")
            }
        }
    }

    /// Rescans the music folder. A request during a scan runs once more after it, so a change is never missed.
    func scan(force: Bool = false) {
        guard scanProgress == nil else {
            rescanRequested = true
            if force { forcedRescanRequested = true }
            return
        }
        scanProgress = ScanProgress()
        let scanner = LibraryScanner(database: database)
        let store = self
        Task.detached(priority: .userInitiated) {
            var didChange = force
            do {
                let summary = try scanner.scan(forceRewrite: force) { progress in
                    Task { @MainActor in store.updateProgress(progress) }
                }
                if summary.upserted > 0 || summary.removed > 0 {
                    didChange = true
                }
            } catch {
                let message = "The library scan failed: \(error)"
                await store.report(message)
            }
            await store.scanFinished(didChange: didChange)
        }
    }

    private func updateProgress(_ progress: ScanProgress) {
        if scanProgress != nil { scanProgress = progress }
    }

    private func scanFinished(didChange: Bool) {
        scanProgress = nil
        // SQLiteDatabase.didChange already schedules a reload when the scan writes; avoid cancelling
        // and restarting an in-flight reload, and skip reloading altogether on fast no-op scans.
        if didChange && pendingReload == nil {
            scheduleReload(catalogChanged: true)
        }
        if rescanRequested {
            let nextForce = forcedRescanRequested
            rescanRequested = false
            forcedRescanRequested = false
            scan(force: nextForce)
        }
    }

    /// Copies files picked in the document picker into the music folder, then rescans.
    func importFiles(_ urls: [URL]) {
        let folder = LibraryPaths.musicFolder
        let store = self
        Task.detached(priority: .userInitiated) {
            var failed: [String] = []
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let destination = uniqueDestination(for: url.lastPathComponent, in: folder)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                } catch {
                    failed.append(url.lastPathComponent)
                }
            }
            let failures = failed
            await MainActor.run {
                if !failures.isEmpty { store.report("Couldn't import: \(failures.joined(separator: ", "))") }
                store.scan()
            }
        }
    }

    func report(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}

/// `folder/name`, or `folder/name 2.ext`, `3`, … if that name is taken.
func uniqueDestination(for fileName: String, in folder: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var candidate = folder.appendingPathComponent(fileName)
    var counter = 2
    while exists(candidate) {
        candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
        counter += 1
    }
    return candidate
}

/// The home screen's Featured Albums: albums already in the library, chosen locally and
/// deterministically: the most played, then those holding favourites, then a daily rotation of
/// the rest (fuller albums first). Albums on the Recently Played shelf come last, only to fill.
enum FeaturedAlbums {
    static let limit = 5
    /// Below this many songs an album is likely a single; rotation prefers fuller albums.
    private static let minRotationSongs = 3

    static func select(albums: [Album], tracks: [TrackFacts], plays: [MonthlyPlays], exclude: Set<Int64>, epochDay: Int64,
                       limit: Int = limit) -> [Album] {
        let inLibrary = albums.filter { $0.songCount > 0 }.distinct(by: \.id)
        let candidates = inLibrary.filter { !exclude.contains($0.id) }
        let albumOfSong = Dictionary(tracks.map { ($0.songId, $0.albumId) }, uniquingKeysWith: { a, _ in a })
        var playsByAlbum: [Int64: Int] = [:]
        for p in plays { if let album = albumOfSong[p.songId] { playsByAlbum[album, default: 0] += p.plays } }
        var favouritesByAlbum: [Int64: Int] = [:]
        for t in tracks where t.isFavorite { favouritesByAlbum[t.albumId, default: 0] += 1 }

        let played = candidates.filter { playsByAlbum[$0.id, default: 0] > 0 }.sorted { a, b in
            let pa = playsByAlbum[a.id, default: 0], pb = playsByAlbum[b.id, default: 0]
            if pa != pb { return pa > pb }
            let fa = favouritesByAlbum[a.id, default: 0], fb = favouritesByAlbum[b.id, default: 0]
            return fa != fb ? fa > fb : a.id < b.id
        }
        let loved = candidates.filter { playsByAlbum[$0.id, default: 0] == 0 && favouritesByAlbum[$0.id, default: 0] > 0 }.sorted { a, b in
            let fa = favouritesByAlbum[a.id, default: 0], fb = favouritesByAlbum[b.id, default: 0]
            return fa != fb ? fa > fb : a.id < b.id
        }
        let chosen = Array((played + loved).prefix(limit))
        let taken = Set(chosen.map(\.id))
        func daily(_ a: Album, _ b: Album) -> Bool {
            let ra = dailyRank(a.id, epochDay), rb = dailyRank(b.id, epochDay)
            return ra != rb ? ra < rb : a.id < b.id
        }
        let rest = candidates.filter { !taken.contains($0.id) }
        let fuller = rest.filter { $0.songCount >= minRotationSongs }.sorted(by: daily)
        let smaller = rest.filter { $0.songCount < minRotationSongs }.sorted(by: daily)
        let recent = inLibrary.filter { exclude.contains($0.id) && !taken.contains($0.id) }.sorted(by: daily)
        return chosen + (fuller + smaller + recent).prefix(max(limit - chosen.count, 0))
    }

    /// A stable pseudo-random rank of [albumId] for [epochDay] (SplitMix64 mixing).
    static func dailyRank(_ albumId: Int64, _ epochDay: Int64) -> Int64 {
        var z = albumId &* Int64(bitPattern: 0x9E37_79B9_7F4A_7C15) &+ epochDay
        z = (z ^ Int64(bitPattern: UInt64(bitPattern: z) >> 30)) &* Int64(bitPattern: 0xBF58_476D_1CE4_E5B9)
        z = (z ^ Int64(bitPattern: UInt64(bitPattern: z) >> 27)) &* Int64(bitPattern: 0x94D0_49BB_1331_11EB)
        return z ^ Int64(bitPattern: UInt64(bitPattern: z) >> 31)
    }
}
