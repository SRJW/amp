import SwiftUI

/// Existing album/artist/playlist cards live inside one category scaffold.
struct EntityCategoryView: View {
    let category: LibraryCategory
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @AppStorage private var sort: String
    @State private var query = ""
    @State private var showsSearch = false
    @State private var selecting = false
    @State private var selected = Set<Int64>()
    @State private var resolvedGridItems: [NativeEntityItem] = []
    @State private var resolvedGridAnchors: [String: Int] = [:]
    @State private var resolvedFolders: [String] = []
    @State private var resolvedSongs: [Song] = []
    @State private var resolvedAnchors: [String: String] = [:]
    @State private var loaded = false
    @State private var scrollHandle = NativeScrollHandle()
    @FocusState private var focused: Bool

    init(category: LibraryCategory) {
        self.category = category
        _sort = AppStorage(wrappedValue: LibrarySort.title.rawValue, "library.\(category.rawValue).sort")
    }

    private var usesNativeGrid: Bool {
        !selecting && (category == .albums || category == .artists || category == .albumArtists || category == .playlists)
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

    private var cachedGrid: LibraryStore.CachedEntityGrid? {
        guard usesNativeGrid, query.trimmed.isEmpty else { return nil }
        return library.cachedEntityGrid(category: category, sortRaw: sort)
    }

    var body: some View {
        let precomputed = cachedGrid
        let tracks = !resolvedSongs.isEmpty ? resolvedSongs : (precomputed?.songs ?? [])
        Group {
            if usesNativeGrid {
                let effectiveItems = !resolvedGridItems.isEmpty ? resolvedGridItems : (precomputed?.items ?? [])
                let effectiveAnchors = !resolvedGridAnchors.isEmpty ? resolvedGridAnchors : (precomputed?.anchors ?? [:])
                let showsAlphabet = effectiveAnchors.count > 1
                ZStack(alignment: .bottomTrailing) {
                    NativeEntityGridView(
                        items: effectiveItems,
                        showsAlphabetPadding: showsAlphabet,
                        emptyMessage: "No \(category.title.lowercased()) found.",
                        emptyIcon: category.icon,
                        isLoading: !loaded && precomputed == nil,
                        palette: palette,
                        artworkChangeVersion: ArtworkChangeBroker.shared.version,
                        scrollHandle: scrollHandle,
                        onSelect: { item in
                            remember()
                            switch category {
                            case .albums: router.open(.album(item.id))
                            case .artists, .albumArtists: router.open(.artist(item.id))
                            case .playlists: router.open(.playlist(item.id))
                            default: break
                            }
                        },
                        onRefresh: { library.scan() }
                    ) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            headerSection(tracks: tracks)
                            if category == .albums, query.trimmed.isEmpty, !library.featuredAlbums.isEmpty {
                                Shelf(title: "Featured Albums") {
                                    ForEach(library.featuredAlbums) { album in
                                        AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: ArtworkSize.shelf)
                                    }
                                }
                            }
                        }
                        .padding(.top, Spacing.sm)
                    }
                    .ignoresSafeArea()

                    if showsAlphabet {
                        AlphabetIndexView(anchors: effectiveAnchors) { idx in
                            scrollHandle.scrollToGridItem?(idx, false)
                        }
                        .padding(.bottom, SongAlphabetMetrics.bottomPadding)
                    }
                }
            } else {
                let anchors = resolvedAnchors
                let showsAlphabetIndex = category != .radio && anchors.count > 1
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            headerSection(tracks: tracks)
                            if selecting {
                                SongSelectionBar(songs: tracks, selected: $selected)
                                SongList(songs: tracks, emptyMessage: "No songs in this category.", emptyIcon: category.icon,
                                         selection: $selected, showsFileDetails: true)
                            } else if loaded {
                                nonGridEntities
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
                                proxy.scrollTo(id, anchor: .top)
                            }
                            .padding(.bottom, SongAlphabetMetrics.bottomPadding)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { library.scan() }
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .task(id: loadKey) {
            await computeEntities()
        }
    }

    @ViewBuilder
    private func headerSection(tracks: [Song]) -> some View {
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

        let computed = await Task.detached(priority: .userInitiated) { () -> ([NativeEntityItem], [String: Int], [String], [Song], [String: String]) in
            let match = SectionSearch(query)
            var gridItems: [NativeEntityItem] = []
            var gridAnchors: [String: Int] = [:]
            var folders: [String] = []
            var songs: [Song] = []

            switch category {
            case .albums:
                let albums = AlbumBrowseRequest(albums: allAlbums, songs: allSongs, facts: facts,
                                                lastPlayed: lastPlayed, query: query, sort: LibrarySort(rawValue: sortRaw) ?? .title).results()
                let ids = Set(albums.map(\.id))
                songs = allSongs.filter { ids.contains($0.albumId) }
                gridItems = albums.map { album in
                    NativeEntityItem(
                        id: album.id,
                        title: album.title,
                        subtitle: album.artist,
                        audioArtworkURL: albumCovers[album.id]?.url,
                        fileArtworkPath: nil,
                        circular: false,
                        monogram: nil,
                        placeholderSymbol: "square.stack"
                    )
                }
                gridAnchors = SongAlphabet.indexAnchors(albums) {
                    sortRaw == LibrarySort.artist.rawValue ? $0.artist : $0.title
                }
            case .artists:
                let sorted = allArtists.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let artists = sortRaw == LibrarySort.titleDescending.rawValue ? Array(sorted.reversed()) : sorted
                let ids = Set(artists.map(\.id))
                songs = allSongs.filter { ids.contains($0.artistId) }
                gridItems = artists.map { artist in
                    let letter = artist.name.trimmed.first.map { String($0).uppercased() } ?? "?"
                    return NativeEntityItem(
                        id: artist.id,
                        title: artist.name,
                        subtitle: countLabel(artist.songCount, "song"),
                        audioArtworkURL: nil,
                        fileArtworkPath: artist.artworkPath.map(LibraryPaths.resolveImage),
                        circular: true,
                        monogram: letter,
                        placeholderSymbol: "person"
                    )
                }
                gridAnchors = SongAlphabet.indexAnchors(artists, title: \.name)
            case .albumArtists:
                let sorted = allArtists.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let artists = sortRaw == LibrarySort.titleDescending.rawValue ? Array(sorted.reversed()) : sorted
                let ids = artists.reduce(into: Set<Int64>()) { $0.formUnion(albumArtistAlbums[$1.id] ?? []) }
                songs = allSongs.filter { ids.contains($0.albumId) }
                gridItems = artists.map { artist in
                    let letter = artist.name.trimmed.first.map { String($0).uppercased() } ?? "?"
                    return NativeEntityItem(
                        id: artist.id,
                        title: artist.name,
                        subtitle: countLabel(artist.songCount, "song"),
                        audioArtworkURL: nil,
                        fileArtworkPath: artist.artworkPath.map(LibraryPaths.resolveImage),
                        circular: true,
                        monogram: letter,
                        placeholderSymbol: "person"
                    )
                }
                gridAnchors = SongAlphabet.indexAnchors(artists, title: \.name)
            case .playlists:
                let sorted = allPlaylists.filter { match.matches([$0.name]) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let playlists = sortRaw == LibrarySort.titleDescending.rawValue ? Array(sorted.reversed()) : sorted
                let ids = Set(playlists.flatMap { (try? database.playlistEntries($0.id))?.map(\.song.id) ?? [] })
                songs = allSongs.filter { ids.contains($0.id) }
                gridItems = playlists.map { playlist in
                    NativeEntityItem(
                        id: playlist.id,
                        title: playlist.name,
                        subtitle: countLabel(playlist.songCount, "song"),
                        audioArtworkURL: nil,
                        fileArtworkPath: playlist.artworkPath.map(LibraryPaths.resolveImage),
                        circular: false,
                        monogram: nil,
                        placeholderSymbol: "music.note.list"
                    )
                }
                gridAnchors = SongAlphabet.indexAnchors(playlists, title: \.name)
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
            } else if category == .folders {
                anchors = SongAlphabet.anchors(folders, id: { "amp-entity-folder-\($0)" }) { folder in
                    let name = (folder as NSString).lastPathComponent
                    return name.isEmpty ? "Music folder" : name
                }
            } else {
                anchors = [:]
            }
            return (gridItems, gridAnchors, folders, songs, anchors)
        }.value

        guard !Task.isCancelled else { return }
        resolvedGridItems = computed.0
        resolvedGridAnchors = computed.1
        resolvedFolders = computed.2
        resolvedSongs = computed.3
        resolvedAnchors = computed.4
        loaded = true

        if usesNativeGrid && query.trimmed.isEmpty {
            library.storeCachedEntityGrid(
                .init(items: computed.0, anchors: computed.1, songs: computed.3),
                category: category,
                sortRaw: sortRaw
            )
        }

        // Warm the initial viewport's artwork at low priority.
        let initialURLs = computed.0.prefix(16).compactMap(\.audioArtworkURL)
        if !initialURLs.isEmpty { ArtworkLoader.shared.prefetch(urls: initialURLs, maxPixels: 320) }
        let initialPaths = computed.0.prefix(16).compactMap(\.fileArtworkPath)
        if !initialPaths.isEmpty { ArtworkLoader.shared.prefetchFiles(paths: initialPaths, maxPixels: 320) }
    }

    @ViewBuilder private var nonGridEntities: some View {
        switch category {
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

    private var empty: some View { EmptyState(message: "No \(category.title.lowercased()) found.", systemImage: category.icon) }
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
