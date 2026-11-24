import SwiftUI
import UIKit

/// Songs keeps amp's theme, with collection-wide play, focused tools and explicit bulk actions.
struct AllSongsView: View {
    var folderPath: String? = nil
    var category: LibraryCategory = .songs
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @AppStorage private var sort: String
    @State private var selecting = false
    @State private var selected = Set<Int64>()
    @State private var pendingDeletion: [Song] = []
    @State private var confirmsDeletion = false
    @State private var query = ""
    @State private var showsSearch = false
    @State private var showsFilters = false
    @State private var added = SongAddedPeriod.any
    @State private var genre = ""
    @State private var mood = LibraryMood.all
    @State private var format = ""
    @State private var results: [Song]?
    @State private var genres: [String] = []
    @State private var formats: [String] = []
    @FocusState private var searchFocused: Bool

    init(folderPath: String? = nil, category: LibraryCategory = .songs) {
        self.folderPath = folderPath
        self.category = category
        let key = category == .songs ? "library.songs.sort" : "library.\(category.rawValue).sort"
        _sort = AppStorage(wrappedValue: category.defaultSort.rawValue, key)
    }

    private var scopedSongs: [Song] {
        guard let folderPath else {
            switch category {
            case .favorites: return library.favorites
            case .mostPlayed: return library.songs.filter { (library.browseFacts[$0.id]?.plays ?? 0) > 0 }
            case .recentlyPlayed: return library.songs.filter { (library.browseFacts[$0.id]?.lastPlayedAt ?? 0) > 0 }
            default: return library.songs
            }
        }
        return library.songs.filter { ($0.path as NSString).deletingLastPathComponent == folderPath }
    }
    private var title: String {
        guard let folderPath else { return category.title }
        let name = (folderPath as NSString).lastPathComponent
        return name.isEmpty ? "Music folder" : name
    }
    private var hasFilters: Bool { added != .any || !genre.isEmpty || mood != .all || !format.isEmpty }
    private var request: SongBrowseRequest {
        let now = LibraryDatabase.now()
        let facts = library.browseFacts
        let songs = added == .any ? scopedSongs : scopedSongs.filter { added.contains(facts[$0.id]?.addedAt ?? $0.dateModified, now: now) }
        return SongBrowseRequest(songs: songs, facts: facts, query: query,
                                 sort: LibrarySort(rawValue: sort) ?? .title, genre: genre, mood: mood, format: format)
    }
    private var selectedSongs: [Song] {
        SongBrowseRequest(songs: scopedSongs.filter { selected.contains($0.id) }, facts: library.browseFacts,
                          query: "", sort: LibrarySort(rawValue: sort) ?? .title).results()
    }

    private var alphabetKey: (Song) -> String {
        switch LibrarySort(rawValue: sort) {
        case .artist: \.artist
        case .album: \.album
        default: \.title
        }
    }

    private struct BrowseTaskKey: Equatable {
        let contentRevision: Int
        let statsRevision: Int
        let folderPath: String?
        let category: LibraryCategory
        let sort: String
        let query: String
        let added: SongAddedPeriod
        let genre: String
        let mood: LibraryMood
        let format: String
    }

    private var browseTaskKey: BrowseTaskKey {
        let needsStats = category == .mostPlayed || category == .recentlyPlayed
            || sort == LibrarySort.recentlyAdded.rawValue
            || sort == LibrarySort.recentlyPlayed.rawValue
            || sort == LibrarySort.mostPlayed.rawValue
            || added != .any
        return BrowseTaskKey(
            contentRevision: library.contentRevision,
            statsRevision: needsStats ? library.statsRevision : 0,
            folderPath: folderPath,
            category: category,
            sort: sort,
            query: query,
            added: added,
            genre: genre,
            mood: mood,
            format: format
        )
    }

    var body: some View {
        PlayerSongReveal(destination: folderPath.map(Route.songFolder) ?? (category == .songs ? .allSongs : .category(category)),
                         songs: results ?? [], alphabetEnabled: true, alphabetKey: alphabetKey) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    if showsFilters { filters }
                    if showsSearch {
                        VStack(spacing: Spacing.sm) {
                            GlassSearchField(text: $query, prompt: L("Search songs"), focused: $searchFocused,
                                             close: closeSearch, identifier: "sectionSearchField", historyScope: "songs")
                            if query.trimmed.isEmpty {
                                RecentSearchesView(scope: "songs") { query = $0; searchFocused = true }
                            }
                        }
                        .padding(.horizontal, Spacing.gutter)
                        .task { searchFocused = true }
                    }
                    if selecting { selectionActions }
                    if category == .recentlyPlayed { recentCollections }
                    if let results {
                        if hasFilters || !query.trimmed.isEmpty {
                            Text(results.count == 1 ? L("1 match") : L("%d matches", results.count)).font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, Spacing.gutter)
                        }
                        SongList(songs: results, emptyMessage: scopedSongs.isEmpty ? L("No songs found.") : L("No songs match these filters."),
                                 emptyIcon: "music.note", source: playbackSource, selection: selecting ? $selected : nil, showsFileDetails: true,
                                 continuousFromSearch: !query.trimmed.isEmpty,
                                 onPlay: { dismissSearchKeyboard(); SearchHistoryStore.shared.remember(query, in: "songs") })
                    } else { ProgressView().frame(maxWidth: .infinity).padding() }
                }.padding(.top, Spacing.sm)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("songsPage")
        }
        .tracksLibraryScrolling()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: router.showsNowPlaying) { _, shown in if shown { dismissSearchKeyboard() } }
        .task(id: browseTaskKey) {
            let snapshot = request
            if !snapshot.query.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            let updated = await Task.detached(priority: .userInitiated) {
                (snapshot.results(), LibraryBrowse.genres(in: snapshot.songs), LibraryBrowse.formats(in: snapshot.songs))
            }.value
            guard !Task.isCancelled else { return }
            results = updated.0; genres = updated.1; formats = updated.2
            let initialURLs = updated.0.prefix(20).map { library.listThumbnailURL(for: $0) }
            ArtworkLoader.shared.prefetch(urls: initialURLs, maxPixels: 144)
        }
        .refreshable { library.scan() }
        .onChange(of: library.songs) { _, songs in selected.formIntersection(Set(songs.map(\.id))) }
        .alert("Delete \(countLabel(pendingDeletion.count, "song")) from device?", isPresented: $confirmsDeletion) {
            Button(L("Delete from device"), role: .destructive) {
                let deleted = actions.deleteFromDevice(pendingDeletion)
                selected.subtract(deleted)
                pendingDeletion = []
                if selected.isEmpty { selecting = false }
            }
            Button(L("Cancel"), role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("This permanently removes the selected audio files from amp, Files, the library and playlists. It cannot be undone. Separate copies elsewhere are kept.")
        }
    }

    private var playbackSource: PlaybackSource {
        switch category {
        case .favorites: .favorites
        case .mostPlayed: .smartPlaylist(SmartPlaylist.mostPlayed.rawValue)
        case .recentlyPlayed: .smartPlaylist(SmartPlaylist.recentlyPlayed.rawValue)
        case .recentlyAdded: .smartPlaylist(SmartPlaylist.recentlyAdded.rawValue)
        default: .library
        }
    }

    private var header: some View {
        CategoryHeader(title: title, icon: folderPath == nil ? category.icon : "folder", count: (results ?? scopedSongs).count,
                       selecting: selecting,
                       shuffle: { dismissSearchKeyboard(); actions.playShuffled(results ?? [], source: playbackSource) },
                       play: { dismissSearchKeyboard(); actions.playInOrder(results ?? [], source: playbackSource) },
                       search: { showsSearch = true; searchFocused = true },
                       select: { selecting.toggle(); if !selecting { selected.removeAll() } }) {
            Picker(L("Sort by"), selection: $sort) {
                ForEach(LibrarySort.songs, id: \.rawValue) { Text(L($0.label)).tag($0.rawValue) }
            }
            Button(showsFilters ? L("Hide filters") : L("Show filters"), systemImage: "line.3.horizontal.decrease") { showsFilters.toggle() }
            Button(L("Import music"), systemImage: "plus") { router.showsImporter = true }
        }
    }

    @ViewBuilder private var recentCollections: some View {
        if !library.recentAlbums.isEmpty {
            Shelf(title: "Recently played albums") {
                ForEach(library.recentAlbums) { album in
                    AlbumTile(album: album) { router.open(.album(album.id)) }.frame(width: ArtworkSize.shelf)
                }
            }
        }
        if !library.recentPlaylists.isEmpty {
            Shelf(title: "Recently played playlists") {
                ForEach(library.recentPlaylists) { playlist in
                    PlaylistTile(playlist: playlist) { router.open(.playlist(playlist.id)) }.frame(width: ArtworkSize.shelf)
                }
            }
        }
    }

    private var filters: some View {
        let columns = [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)]
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            GlassGroup(spacing: Spacing.sm, enabled: settings.glassEnabled) {
                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    Menu {
                        Picker(L("Date added"), selection: $added) {
                            ForEach(SongAddedPeriod.allCases) { Text($0.description).tag($0) }
                        }
                    } label: { SongsFilterLabel(title: added.label, symbol: "calendar.badge.clock", active: added != .any) }
                    Menu {
                        Picker(L("Format"), selection: $format) {
                            Text(L("All formats")).tag("")
                            Text(L("Lossless")).tag(LibraryBrowse.losslessFormat)
                            ForEach(formats, id: \.self) { Text($0).tag($0) }
                        }
                    } label: { SongsFilterLabel(title: formatTitle, symbol: "waveform", active: !format.isEmpty) }
                    .accessibilityIdentifier("songsFormatFilter")
                    Menu {
                        Picker(L("Genre"), selection: $genre) {
                            Text(L("All genres")).tag("")
                            Text(L("Untagged")).tag(LibraryBrowse.untaggedGenre)
                            ForEach(genres, id: \.self) { Text($0).tag(SectionSearch.key($0)) }
                        }
                    } label: { SongsFilterLabel(title: genreTitle, symbol: "guitars", active: !genre.isEmpty) }
                    Menu {
                        Picker(L("Mood"), selection: $mood) {
                            ForEach(LibraryMood.allCases, id: \.rawValue) { Text($0 == .all ? L("All moods") : $0.label).tag($0) }
                        }
                    } label: { SongsFilterLabel(title: mood == .all ? L("Mood") : mood.label, symbol: "sparkles", active: mood != .all) }
                }
            }
            if hasFilters {
                Button(L("Clear filters")) { added = .any; genre = ""; mood = .all; format = "" }
                    .font(.caption).frame(minHeight: 44)
            }
        }.padding(.horizontal, Spacing.gutter)
    }

    private var genreTitle: String {
        genre.isEmpty ? L("Genre") : genre == LibraryBrowse.untaggedGenre ? L("Untagged")
            : genres.first { SectionSearch.key($0) == genre } ?? L("Genre")
    }

    private var formatTitle: String {
        format.isEmpty ? L("Format") : format == LibraryBrowse.losslessFormat ? L("Lossless") : format
    }

    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("\(selected.count) selected").font(.headline)
            HStack {
                Button("Select all") { selected.formUnion((results ?? []).map(\.id)) }
                Button("Clear") { selected.removeAll() }
            }.buttonStyle(.bordered)
            HStack {
                Button {
                    SearchHistoryStore.shared.remember(query, in: "songs")
                    router.songsForPlaylist = selectedSongs
                } label: { Label("Add to playlist", systemImage: "text.badge.plus") }
                .accessibilityIdentifier("songsAddToPlaylist")
                Button(role: .destructive) {
                    pendingDeletion = selectedSongs
                    confirmsDeletion = true
                } label: { Label("Delete", systemImage: "trash") }
                .accessibilityIdentifier("songsDeleteSelected")
            }.buttonStyle(.bordered).disabled(selectedSongs.isEmpty)
        }.padding(.horizontal, Spacing.gutter)
    }

    private func dismissSearchKeyboard() {
        searchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func closeSearch() { dismissSearchKeyboard(); query = ""; showsSearch = false }
}
