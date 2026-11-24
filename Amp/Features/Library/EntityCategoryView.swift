import SwiftUI

/// Existing album/artist/playlist cards live inside one category scaffold.
struct EntityCategoryView: View {
    let category: LibraryCategory
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @AppStorage private var sort: String
    @State private var query = ""
    @State private var showsSearch = false
    @State private var selecting = false
    @State private var selected = Set<Int64>()
    @State private var alphabetTarget: String?
    @State private var resolvedAlbums: [Album] = []
    @State private var resolvedArtists: [Artist] = []
    @State private var resolvedPlaylists: [Playlist] = []
    @State private var resolvedFolders: [String] = []
    @State private var resolvedSongs: [Song] = []
    @State private var resolvedAnchors: [String: String] = [:]
    @State private var loaded = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = [GridItem(.adaptive(minimum: ArtworkSize.gridMin), spacing: Spacing.lg, alignment: .top)]

    init(category: LibraryCategory) {
        self.category = category
        _sort = AppStorage(wrappedValue: LibrarySort.title.rawValue, "library.\(category.rawValue).sort")
    }

    private struct LoadKey: Equatable {
        let contentRevision: Int
        let statsRevision: Int
        let category: LibraryCategory
        let sort: String
        let query: String
        let selecting: Bool
    }

    private var loadKey: LoadKey {
        LoadKey(
            contentRevision: library.contentRevision,
            statsRevision: library.statsRevision,
            category: category,
            sort: sort,
            query: query,
            selecting: selecting
        )
    }

    var body: some View {
        let tracks = resolvedSongs
        let anchors = resolvedAnchors
        let showsAlphabetIndex = category != .radio && anchors.count > 1
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    CategoryHeader(title: category.title, icon: category.icon, count: tracks.count, selecting: selecting,
                                   shuffle: { remember(); actions.playShuffled(tracks) }, play: { remember(); actions.playInOrder(tracks) },
                                   search: { showsSearch = true; focused = true },
                                   select: { selecting.toggle(); if !selecting { selected.removeAll() } }) {
                        Picker("Sort by", selection: $sort) {
                            ForEach(category == .albums ? LibrarySort.albums : [.title, .titleDescending], id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                        }
                        if category == .playlists { Button("New playlist", systemImage: "plus") { router.showsNewPlaylist = true } }
                        Button("Import music", systemImage: "plus") { router.showsImporter = true }
                    }
                    if showsSearch {
                        GlassSearchField(text: $query, prompt: "Search \(category.title.lowercased())", focused: $focused,
                                         close: { focused = false; showsSearch = false; query = "" },
                                         historyScope: "browse." + category.title.lowercased())
                            .padding(.horizontal, Spacing.gutter)
                        if query.trimmed.isEmpty {
                            RecentSearchesView(scope: "browse." + category.title.lowercased()) { query = $0; focused = true }
                                .padding(.horizontal, Spacing.gutter)
                        }
                    }
                    if selecting {
                        SongSelectionBar(songs: tracks, selected: $selected)
                        SongList(songs: tracks, emptyMessage: "No songs in this category.", emptyIcon: category.icon,
                                 selection: $selected, showsFileDetails: true)
                    } else if loaded {
                        entities
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                }.padding(.vertical, Spacing.sm)
            }
            .scrollIndicators(showsAlphabetIndex ? .hidden : .automatic)
            .padding(.trailing, showsAlphabetIndex ? SongAlphabetMetrics.width : 0)
            .overlay(alignment: .bottomTrailing) {
                if showsAlphabetIndex {
                    AlphabetIndexView(anchors: anchors) { id in
                        alphabetTarget = id
                        withAnimation(reduceMotion ? nil : .easeOut(duration: SongAlphabetMetrics.scrollDuration)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .padding(.bottom, SongAlphabetMetrics.bottomPadding)
                }
            }
            .task(id: alphabetTarget) {
                guard let id = alphabetTarget else { return }
                do {
                    try await Task.sleep(for: .seconds(SongAlphabetMetrics.scrollDuration))
                    try Task.checkCancellation()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: SongAlphabetMetrics.scrollDuration)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                } catch {}
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .refreshable { library.scan() }
        .task(id: loadKey) {
            await computeEntities()
        }
    }

    private func computeEntities() async {
        let category = self.category
        let sortRaw = self.sort
        let query = self.query
        let selecting = self.selecting
        if !query.isEmpty { try? await Task.sleep(for: .milliseconds(90)) }
        guard !Task.isCancelled else { return }

        let allAlbums = library.albums
        let allSongs = library.songs
        let allArtists = category == .albumArtists ? library.albumArtists : library.artists
        let albumArtistAlbums = library.albumArtistAlbums
        let allPlaylists = library.playlists
        let facts = library.browseFacts
        let lastPlayed = library.albumLastPlayed
        let albumCovers = library.albumCoverSong
        let database = library.database

        let computed = await Task.detached(priority: .userInitiated) { () -> ([Album], [Artist], [Playlist], [String], [Song], [String: String]) in
            let match = SectionSearch(query)
            var albums: [Album] = []
            var artists: [Artist] = []
            var playlists: [Playlist] = []
            var folders: [String] = []
            var songs: [Song] = []

            switch category {
            case .albums:
                albums = AlbumBrowseRequest(albums: allAlbums, songs: allSongs, facts: facts,
                                            lastPlayed: lastPlayed, query: query, sort: LibrarySort(rawValue: sortRaw) ?? .title).results()
                let ids = Set(albums.map(\.id))
                songs = allSongs.filter { ids.contains($0.albumId) }
            case .artists:
                let sorted = allArtists.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                artists = sortRaw == LibrarySort.titleDescending.rawValue ? Array(sorted.reversed()) : sorted
                let ids = Set(artists.map(\.id))
                songs = allSongs.filter { ids.contains($0.artistId) }
            case .albumArtists:
                let sorted = allArtists.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                artists = sortRaw == LibrarySort.titleDescending.rawValue ? Array(sorted.reversed()) : sorted
                let ids = artists.reduce(into: Set<Int64>()) { $0.formUnion(albumArtistAlbums[$1.id] ?? []) }
                songs = allSongs.filter { ids.contains($0.albumId) }
            case .playlists:
                let sorted = allPlaylists.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                playlists = sortRaw == LibrarySort.titleDescending.rawValue ? Array(sorted.reversed()) : sorted
                let ids = Set(playlists.flatMap { (try? database.playlistEntries($0.id))?.map(\.song.id) ?? [] })
                songs = allSongs.filter { ids.contains($0.id) }
            case .folders:
                let sorted = Set(allSongs.map { ($0.path as NSString).deletingLastPathComponent }).filter { match.matches([$0]) }.sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
                folders = sortRaw == LibrarySort.titleDescending.rawValue ? Array(sorted.reversed()) : sorted
                let paths = Set(folders)
                songs = allSongs.filter { paths.contains(($0.path as NSString).deletingLastPathComponent) }
            default:
                songs = allSongs.filter { match.matches([$0.title, $0.artist, $0.album]) }
            }

            let anchors: [String: String]
            if selecting {
                anchors = SongAlphabet.anchors(songs, id: \.listScrollAnchor, title: \.title)
            } else {
                switch category {
                case .albums:
                    anchors = SongAlphabet.anchors(albums, id: { "amp-entity-album-\($0.id)" },
                                                   title: { sortRaw == LibrarySort.artist.rawValue ? $0.artist : $0.title })
                case .artists, .albumArtists:
                    anchors = SongAlphabet.anchors(artists, id: { "amp-entity-artist-\($0.id)" }, title: \.name)
                case .playlists:
                    anchors = SongAlphabet.anchors(playlists, id: { "amp-entity-playlist-\($0.id)" }, title: \.name)
                case .folders:
                    anchors = SongAlphabet.anchors(folders, id: { "amp-entity-folder-\($0)" }) { folder in
                        let name = (folder as NSString).lastPathComponent
                        return name.isEmpty ? "Music folder" : name
                    }
                default:
                    anchors = [:]
                }
            }
            return (albums, artists, playlists, folders, songs, anchors)
        }.value

        guard !Task.isCancelled else { return }
        resolvedAlbums = computed.0
        resolvedArtists = computed.1
        resolvedPlaylists = computed.2
        resolvedFolders = computed.3
        resolvedSongs = computed.4
        resolvedAnchors = computed.5
        loaded = true

        // Warm the initial viewport's artwork at low priority.
        switch category {
        case .albums:
            let urls = computed.0.prefix(16).compactMap { albumCovers[$0.id]?.url }
            ArtworkLoader.shared.prefetch(urls: urls, maxPixels: 320)
        case .artists, .albumArtists:
            let paths = computed.1.prefix(16).compactMap { $0.artworkPath.map(LibraryPaths.resolveImage) }
            ArtworkLoader.shared.prefetchFiles(paths: paths, maxPixels: 320)
        case .playlists:
            let paths = computed.2.prefix(16).compactMap { $0.artworkPath.map(LibraryPaths.resolveImage) }
            ArtworkLoader.shared.prefetchFiles(paths: paths, maxPixels: 320)
        default:
            break
        }
    }

    @ViewBuilder private var entities: some View {
        switch category {
        case .albums:
            if query.trimmed.isEmpty, !library.featuredAlbums.isEmpty {
                Shelf(title: "Featured Albums") {
                    ForEach(library.featuredAlbums) { album in AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: ArtworkSize.shelf) }
                }
            }
            if resolvedAlbums.isEmpty { empty }
            grid {
                ForEach(Array(resolvedAlbums.enumerated()), id: \.element.id) { index, album in
                    AlbumTile(album: album) { remember(); router.open(.album(album.id)) }
                        .id("amp-entity-album-\(album.id)")
                        .onAppear { prefetchAlbums(after: index) }
                }
            }
        case .artists, .albumArtists:
            if resolvedArtists.isEmpty { empty }
            grid {
                ForEach(Array(resolvedArtists.enumerated()), id: \.element.id) { index, artist in
                    ArtistTile(artist: artist) { remember(); router.open(.artist(artist.id)) }
                        .id("amp-entity-artist-\(artist.id)")
                        .onAppear { prefetchArtists(after: index) }
                }
            }
        case .playlists:
            if resolvedPlaylists.isEmpty { empty }
            grid {
                ForEach(resolvedPlaylists) { playlist in
                    PlaylistTile(playlist: playlist) { remember(); router.open(.playlist(playlist.id)) }
                        .id("amp-entity-playlist-\(playlist.id)")
                }
            }
        case .folders:
            if resolvedFolders.isEmpty { empty }
            ForEach(resolvedFolders, id: \.self) { folder in
                Button { remember(); router.open(.songFolder(folder)) } label: {
                    Label(folder.isEmpty ? "Music folder" : folder, systemImage: "folder")
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, Spacing.gutter)
                }
                .buttonStyle(.plain)
                .id("amp-entity-folder-\(folder)")
            }
        case .radio:
            if library.songs.isEmpty { empty } else { RadioStationShelf() }
        default: EmptyView()
        }
    }

    private func prefetchAlbums(after index: Int) {
        guard index % 4 == 0, index + 1 < resolvedAlbums.count else { return }
        let end = min(index + 17, resolvedAlbums.count)
        let urls = resolvedAlbums[(index + 1)..<end].compactMap { library.albumCoverSong[$0.id]?.url }
        ArtworkLoader.shared.prefetch(urls: urls, maxPixels: 320)
    }

    private func prefetchArtists(after index: Int) {
        guard index % 4 == 0, index + 1 < resolvedArtists.count else { return }
        let end = min(index + 17, resolvedArtists.count)
        let paths = resolvedArtists[(index + 1)..<end].compactMap { $0.artworkPath.map(LibraryPaths.resolveImage) }
        ArtworkLoader.shared.prefetchFiles(paths: paths, maxPixels: 320)
    }

    private var empty: some View { EmptyState(message: "No \(category.title.lowercased()) found.", systemImage: category.icon) }
    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.xl, content: content).padding(.horizontal, Spacing.gutter)
    }
    private func remember() { SearchHistoryStore.shared.remember(query, in: "browse." + category.title.lowercased()) }
}

struct SongSelectionBar: View {
    let songs: [Song]
    @Binding var selected: Set<Int64>
    @Environment(AppRouter.self) private var router
    @Environment(LibraryActions.self) private var actions
    @State private var pendingDeletion: [Song] = []
    @State private var confirmsDeletion = false
    private var selectedSongs: [Song] { songs.filter { selected.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("\(selectedSongs.count) selected").font(.headline)
            HStack {
                Button("Select all") { selected = Set(songs.map(\.id)) }
                Button("Clear") { selected.removeAll() }
            }
            HStack {
                Button("Add to playlist", systemImage: "text.badge.plus") { router.songsForPlaylist = selectedSongs }
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = selectedSongs; confirmsDeletion = true }
            }.disabled(selectedSongs.isEmpty)
        }
        .buttonStyle(.bordered).padding(.horizontal, Spacing.gutter)
        .onChange(of: songs) { _, songs in selected.formIntersection(songs.map(\.id)) }
        .alert("Delete \(countLabel(pendingDeletion.count, "song")) from device?", isPresented: $confirmsDeletion) {
            Button("Delete from device", role: .destructive) { selected.subtract(actions.deleteFromDevice(pendingDeletion)); pendingDeletion = [] }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: { Text("This permanently removes the selected audio files from amp, Files, the library and playlists. It cannot be undone. Separate copies elsewhere are kept.") }
    }
}
