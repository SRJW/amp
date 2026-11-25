import PhotosUI
import SwiftUI
import UIKit

/// The shared top of a collection page: big cover, title, subtitle, facts, Play / Shuffle.
struct CollectionHeader<Cover: View>: View {
    let title: String
    let subtitle: String?
    let facts: String
    var note: String?
    var coverShape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    var coverInset: CGFloat = 64
    let canPlay: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @ViewBuilder let cover: () -> Cover
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { cover() }
                .clipShape(coverShape)
                .frame(maxWidth: ArtworkSize.heroMax)
                .padding(.horizontal, coverInset)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .padding(.bottom, Spacing.lg)
            Text(title).font(.title.weight(.bold)).multilineTextAlignment(.center).lineLimit(2)
            if let subtitle { Text(subtitle).font(.headline).foregroundStyle(palette.onSurface).lineLimit(1) }
            if let note { Text(note).font(.caption).foregroundStyle(palette.onSurfaceVariant).multilineTextAlignment(.center) }
            Text(facts).font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            HStack(spacing: Spacing.sm) {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity).foregroundStyle(palette.onFilledButton)
                }
                .modifier(PaletteFilledButton())
                .tint(palette.filledButton)
                Button(action: onShuffle) {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .disabled(!canPlay)
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.md)
        }
        .padding(.horizontal, Spacing.heroGutter)
        .padding(.top, Spacing.sm)
    }
}

/// "2018 · 12 songs · 43 min"; unknown parts are left out.
func collectionFacts(year: Int? = nil, songs: [Song]) -> String {
    let minutes = songs.reduce(Int64(0)) { $0 + $1.durationMs } / 60_000
    let duration: String? = minutes <= 0 ? nil : minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    let yearText = year.flatMap { (1900...2099).contains($0) ? String($0) : nil }
    return [yearText, countLabel(songs.count, "song"), duration].compactMap { $0 }.joined(separator: " · ")
}

/// An album: centered cover, title/artist/genre·year, Shuffle / Play / Add controls,
/// numbered hairline-divided tracks, footer summary, and Transition Studio.
struct AlbumDetailView: View {
    @Environment(\.radioAvailable) private var radioAvailable
    let albumId: Int64
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var artworkTarget: ArtworkTarget?
    @State private var pendingAlbumDeletion = false

    var body: some View {
        let origin = CollectionRef.album(albumId)
        PlayerSongReveal(destination: .album(albumId), songs: songs) {
            ScrollView {
                if let album = library.album(albumId) {
                    VStack(alignment: .leading, spacing: 0) {
                        AlbumHeroHeader(
                            album: album,
                            songs: songs,
                            canPlay: !songs.isEmpty,
                            isFavorite: settings.isAlbumFavorite(albumId),
                            onPlay: { actions.playInOrder(songs, origin: origin) },
                            onShuffle: { actions.playShuffled(songs, origin: origin) },
                            onToggleFavorite: { settings.toggleFavoriteAlbum(albumId) },
                            onOpenArtist: album.artistId != 0 ? { router.open(.artist(album.artistId)) } : nil
                        )
                        ScopedTagRepairSummary(songs: songs)
                        CollectionTransitionTrackList(
                            collection: origin,
                            tracks: songs.map { StudioTrack(song: $0, occurrence: TrackOccurrence($0.id)) },
                            showTrackNumbers: true,
                            albumStyle: true
                        )
                        AlbumFooterSummary(album: album, songs: songs)
                            .padding(.bottom, Spacing.md)
                    }
                } else {
                    EmptyState(message: "This album is no longer in your library.", systemImage: "square.stack")
                }
            }
        }
        .tracksLibraryScrolling()
        .toolbarBackground(.hidden, for: .navigationBar)
        .modifier(CollectionTopEdgeEffect())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { songs.reversed().forEach { actions.playNext($0) } } label: { Label(L("Play next"), systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { songs.forEach { actions.addToQueue($0) } } label: { Label(L("Add to queue"), systemImage: "text.badge.plus") }
                if radioAvailable { Button { router.open(.radio(.album(albumId))) } label: { Label(L("Browse radio"), systemImage: "dot.radiowaves.left.and.right") } }
                Button { router.songsForPlaylist = songs } label: { Label(L("Add to playlist"), systemImage: "music.note.list") }
                Button { actions.fixTags(songs) } label: {
                    Label(L("Fix tags online"), systemImage: "wand.and.stars")
                }
                if let album = library.album(albumId) {
                    Button { artworkTarget = .album(album) } label: { Label(L("Find a cover"), systemImage: "photo") }
                }
                if !songs.isEmpty {
                    Divider()
                    Button(role: .destructive) { pendingAlbumDeletion = true } label: {
                        Label(L("Delete from device"), systemImage: "trash")
                    }
                }
            } label: { Image(systemName: "ellipsis") }
            .accessibilityLabel("Album options")
        }
        .confirmationDialog(
            L("Delete album from device?"),
            isPresented: $pendingAlbumDeletion,
            titleVisibility: .visible
        ) {
            Button(L("Delete from device"), role: .destructive) {
                let targetSongs = songs
                let deleted = actions.deleteFromDevice(targetSongs)
                if deleted.count == targetSongs.count && !deleted.isEmpty {
                    dismiss()
                }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            let albumTitle = library.album(albumId).map { CollectionDisplayTitle.normalized($0.title) } ?? ""
            Text(L("Permanently delete %d songs from “%@” from amp's folder in Files, the library and playlists? This cannot be undone.", songs.count, albumTitle))
        }
        .sheet(item: $artworkTarget) { ArtworkPickerSheet(target: $0) }
        .task(id: library.songs) { songs = (try? library.database.songsOfAlbum(albumId)) ?? [] }
        .background { AlbumPageBackground() }
        .collectionArtworkTheme(.track(library.albumCoverSong[albumId]?.url), alwaysFollowArtwork: true)
    }
}

private struct AlbumPageBackground: View {
    @Environment(\.palette) private var palette
    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            LinearGradient(
                colors: [palette.surface.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

private struct AlbumHeroHeader: View {
    let album: Album
    let songs: [Song]
    let canPlay: Bool
    let isFavorite: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void
    let onToggleFavorite: () -> Void
    let onOpenArtist: (() -> Void)?
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metadataLine: String {
        let genre = songs.compactMap { $0.genre?.trimmed }.first(where: { !$0.isEmpty })
        let resolvedYear = (1900...2099).contains(album.year)
            ? album.year
            : songs.map(\.year).first(where: { (1900...2099).contains($0) })
        let yearText = resolvedYear.map(String.init)
        let lossless = songs.contains(where: \.isLossless) ? "Lossless" : nil
        return [genre, yearText, lossless].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { AlbumArtworkView(albumId: album.id, maxPixels: 1200) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 256)
                .shadow(color: .black.opacity(0.34), radius: 18, y: 10)
                .padding(.top, Spacing.sm)

            VStack(spacing: 5) {
                Text(CollectionDisplayTitle.normalized(album.title))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityIdentifier("collectionHeroTitle")

                if let onOpenArtist, !album.artist.isBlank {
                    Button(action: onOpenArtist) {
                        Text(album.artist)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(palette.onSurface.opacity(0.88))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else if !album.artist.isBlank {
                    Text(album.artist)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(palette.onSurface.opacity(0.88))
                        .lineLimit(1)
                }

                if !metadataLine.isEmpty {
                    Text(metadataLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, Spacing.heroGutter)
            .padding(.top, 18)

            HStack(spacing: 14) {
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(palette.onSurface.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(FloatingControlPressStyle())
                .accessibilityLabel(L("Shuffle"))

                Button(action: onPlay) {
                    Label(L("Play"), systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.onFilledButton)
                        .frame(minWidth: 168, minHeight: 48)
                        .padding(.horizontal, Spacing.lg)
                        .background(Capsule().fill(palette.filledButton))
                        .contentShape(Capsule())
                }
                .buttonStyle(FloatingControlPressStyle())

                AppleMusicFavoriteButton(
                    itemID: album.id,
                    isFavorite: isFavorite,
                    iconSize: 19,
                    hitSize: 48,
                    ink: palette.onSurface,
                    reduceMotion: reduceMotion,
                    addLabel: L("Favorite album"),
                    removeLabel: L("Remove album from favorites"),
                    action: onToggleFavorite
                )
                .background(Circle().fill(palette.onSurface.opacity(isFavorite ? 0.22 : 0.14)))
                .contentShape(Circle())
            }
            .disabled(!canPlay)
            .opacity(canPlay ? 1 : 0.4)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AlbumFooterSummary: View {
    let album: Album
    let songs: [Song]
    @Environment(\.palette) private var palette

    private var summaryLine: String {
        let totalMs = songs.reduce(Int64(0)) { $0 + $1.durationMs }
        let totalMinutes = totalMs > 0 ? max(1, Int((totalMs + 30_000) / 60_000)) : 0
        let duration: String?
        if totalMinutes <= 0 {
            duration = nil
        } else if totalMinutes < 60 {
            duration = "\(totalMinutes) \(totalMinutes == 1 ? "minute" : "minutes")"
        } else {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            let hText = "\(hours) \(hours == 1 ? "hour" : "hours")"
            duration = mins > 0 ? "\(hText), \(mins) \(mins == 1 ? "minute" : "minutes")" : hText
        }
        return [countLabel(songs.count, "song"), duration].compactMap { $0 }.joined(separator: ", ")
    }

    private var detailsLine: String? {
        let resolvedYear = (1900...2099).contains(album.year)
            ? album.year
            : songs.map(\.year).first(where: { (1900...2099).contains($0) })
        let codec = songs.compactMap { $0.codec?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })?.uppercased()
        let parts = [resolvedYear.map(String.init), codec].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(summaryLine)
                if let detailsLine {
                    Text(detailsLine)
                }
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(palette.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
    }
}

/// Organizes an artist's discography and tracks into Apple Music–style editorial sections.
enum ArtistPageOrganizer {
    struct Sections {
        let topSongs: [Song]
        let featuredAlbum: Album?
        let essentialAlbums: [Album]
        let fullAlbums: [Album]
        let singlesAndEPs: [Album]
    }

    static func organize(albums: [Album], songs: [Song], facts: [Int64: LibraryBrowseFact]) -> Sections {
        let sortedSongs = songs.sorted { a, b in
            let playsA = facts[a.id]?.plays ?? 0
            let playsB = facts[b.id]?.plays ?? 0
            if playsA != playsB { return playsA > playsB }
            if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
            if a.year != b.year { return a.year > b.year }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        let topSongs = Array(sortedSongs.prefix(5))

        var playsByAlbum: [Int64: Int] = [:]
        for song in songs {
            playsByAlbum[song.albumId, default: 0] += facts[song.id]?.plays ?? 0
        }

        let chronologicalAlbums = albums.sorted { a, b in
            if a.year != b.year { return a.year > b.year }
            if a.songCount != b.songCount { return a.songCount > b.songCount }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        let featuredAlbum = chronologicalAlbums.first

        let fullAlbums = chronologicalAlbums.filter { $0.songCount >= 7 }
        let singlesAndEPs = chronologicalAlbums.filter { $0.songCount < 7 }

        let essentialPool = fullAlbums.isEmpty ? chronologicalAlbums : fullAlbums
        let essentialAlbums = Array(essentialPool.sorted { a, b in
            let pA = playsByAlbum[a.id, default: 0]
            let pB = playsByAlbum[b.id, default: 0]
            if pA != pB { return pA > pB }
            if a.songCount != b.songCount { return a.songCount > b.songCount }
            return a.year > b.year
        }.prefix(3))

        return Sections(
            topSongs: topSongs,
            featuredAlbum: featuredAlbum,
            essentialAlbums: essentialAlbums,
            fullAlbums: fullAlbums,
            singlesAndEPs: singlesAndEPs
        )
    }
}

/// Editorial Apple Music–style artist page: full-bleed artist portrait dissolving into a rich
/// photo-tinted canvas, centered Info / Play / Favorite actions, Featured Release card,
/// Top Songs, Essential Albums, and Albums horizontal carousel.
struct ArtistDetailView: View {
    @Environment(\.radioAvailable) private var radioAvailable
    let artistId: Int64
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var albums: [Album] = []
    @State private var primary: [Song] = []
    @State private var featured: [Song] = []
    @State private var unverified: [Song] = []
    @State private var artworkTarget: ArtworkTarget?
    @State private var showsInfoSheet = false
    @State private var showsAllSongsSheet = false
    @State private var artworkPalette = ArtworkPaletteState()
    @State private var artworkRevision = 0

    private var allArtistSongs: [Song] { primary.isEmpty ? featured : primary }

    private func paletteSource(for artist: Artist?) -> ArtworkPaletteSource {
        if let path = artist?.artworkPath {
            return .image(URL(fileURLWithPath: LibraryPaths.resolveImage(path)))
        }
        if let firstAlbum = albums.sorted(by: { $0.year > $1.year }).first,
           let coverURL = library.albumCoverSong[firstAlbum.id]?.url {
            return .track(coverURL)
        }
        return .track(allArtistSongs.first?.url)
    }

    var body: some View {
        let artist = library.artist(artistId)
        let source = paletteSource(for: artist)
        let sampled = artworkPalette.palette(for: source).forScheme(.dark)
        let colors = LyricsColors(sampled)
        let baseTone = colors.gradient.first ?? colors.surface
        let midTone = colors.surface
        let deepTone = colors.gradient.last ?? colors.surface
        let allSongs = allArtistSongs
        let sections = ArtistPageOrganizer.organize(albums: albums, songs: allSongs, facts: library.browseFacts)
        let songActions = router.songActions(actions, source: .artist(artistId))
        let isPlayingArtist = player.state.isPlaying && allSongs.contains(where: { $0.id == player.currentSongID })

        GeometryReader { geo in
            let width = geo.size.width
            // Tall seamless portrait backdrop that dissolves smoothly behind BOTH the artist name
            // and the i / Play / Star controls — zero hard horizontal cut line anywhere.
            let heroBackdropHeight = min(max(width * 1.28, 470), 545)
            let nameTopSpacer = min(max(width * 0.80, 305), 350)
            ScrollView {
                if let artist {
                    ZStack(alignment: .top) {
                        ArtistScrollPortrait(hasPhoto: artist.artworkPath != nil) {
                            ArtistArtworkView(artist: artist, fontSize: 112, maxPixels: 1200)
                        }
                        .frame(width: width, height: heroBackdropHeight)

                        // Layer 2: Foreground editorial content matching Apple Music (IMG_1683.PNG) vertical rhythm.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Color.clear
                                .frame(height: nameTopSpacer)
                                .allowsHitTesting(false)

                            Text(artist.name)
                                .font(.system(size: 34, weight: .bold))
                                .tracking(-0.4)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.24), radius: 10, y: 2)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 16)
                                .accessibilityIdentifier("collectionHeroTitle")

                            // Centered 3-button Apple Music action row: Info (i) · Play (white circle) · Star (favorite).
                            HStack(spacing: 26) {
                                Button { showsInfoSheet = true } label: {
                                    Image(systemName: "info")
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .background(Circle().fill(Color.white.opacity(0.15)))
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                                }
                                .buttonStyle(FloatingControlPressStyle())
                                .accessibilityLabel(L("Artist info"))
                                .accessibilityIdentifier("artistInfo")

                                Button {
                                    if isPlayingArtist {
                                        player.togglePlayPause()
                                    } else if !allSongs.isEmpty {
                                        actions.playInOrder(sections.topSongs + allSongs.filter { s in !sections.topSongs.contains(where: { $0.id == s.id }) }, source: .artist(artistId))
                                    }
                                } label: {
                                    Image(systemName: isPlayingArtist ? "pause.fill" : "play.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(baseTone)
                                        .offset(x: isPlayingArtist ? 0 : 2)
                                        .frame(width: 70, height: 70)
                                        .background(Circle().fill(Color.white))
                                        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                                }
                                .buttonStyle(FloatingControlPressStyle())
                                .disabled(allSongs.isEmpty)
                                .opacity(allSongs.isEmpty ? 0.45 : 1)
                                .accessibilityLabel(isPlayingArtist ? L("Pause") : L("Play"))
                                .accessibilityIdentifier("artistPlayPause")

                                let isFav = settings.isArtistFavorite(artistId)
                                AppleMusicFavoriteButton(
                                    itemID: artistId,
                                    isFavorite: isFav,
                                    iconSize: 20,
                                    hitSize: 48,
                                    ink: .white,
                                    reduceMotion: reduceMotion,
                                    addLabel: L("Favorite artist"),
                                    removeLabel: L("Remove artist from favorites")
                                ) {
                                    settings.toggleFavoriteArtist(artistId)
                                }
                                .background(Circle().fill(Color.white.opacity(isFav ? 0.24 : 0.15)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 22)

                            // Featured / Latest Release frosted glass card (matching Apple Music IMG_1683.PNG).
                            if let featuredAlbum = sections.featuredAlbum {
                                Button { router.open(.album(featuredAlbum.id)) } label: {
                                    HStack(spacing: 14) {
                                        AlbumArtworkView(albumId: featuredAlbum.id, maxPixels: 320)
                                            .frame(width: 92, height: 92)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(featuredEyebrow(featuredAlbum))
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundStyle(Color.white.opacity(0.76))
                                                .lineLimit(1)
                                            Text(featuredAlbum.title)
                                                .font(.system(size: 16.5, weight: .bold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(featuredSubtitle(featuredAlbum))
                                                .font(.system(size: 13.5, weight: .regular))
                                                .foregroundStyle(Color.white.opacity(0.76))
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(13)
                                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.11)))
                                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                                }
                                .buttonStyle(PressScaleStyle())
                                .padding(.horizontal, 20)
                                .padding(.bottom, 22)
                            }

                        // Top Songs >
                        if !sections.topSongs.isEmpty {
                            Button { showsAllSongsSheet = true } label: {
                                HStack(spacing: 5) {
                                    Text(L("Top Songs"))
                                        .font(.system(size: 21, weight: .bold))
                                        .foregroundStyle(.white)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.62))
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            ForEach(Array(sections.topSongs.enumerated()), id: \.element.id) { index, song in
                                artistSongRow(song: song, list: sections.topSongs, index: index, songActions: songActions,
                                              showsDivider: index < sections.topSongs.count - 1)
                            }
                        }

                        // Essential Albums (vertical 96×96 feature cards when the artist has full albums).
                        if !sections.fullAlbums.isEmpty && !sections.essentialAlbums.isEmpty {
                            Text(L("Essential Albums"))
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.top, 28)
                                .padding(.bottom, 14)

                            VStack(spacing: 16) {
                                ForEach(sections.essentialAlbums) { album in
                                    Button { router.open(.album(album.id)) } label: {
                                        HStack(spacing: 14) {
                                            AlbumArtworkView(albumId: album.id, maxPixels: 320)
                                                .frame(width: 96, height: 96)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(album.title)
                                                    .font(.system(size: 16.5, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                Text(albumDescription(album))
                                                    .font(.system(size: 13.5, weight: .regular))
                                                    .foregroundStyle(Color.white.opacity(0.72))
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            Spacer(minLength: 4)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.white.opacity(0.48))
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressScaleStyle())
                                    .padding(.horizontal, 20)
                                }
                            }
                        }

                        // Albums horizontal carousel (full albums, or all releases if none are >= 7 tracks).
                        let carouselAlbums = sections.fullAlbums.isEmpty ? albums.sorted(by: { $0.year > $1.year }) : sections.fullAlbums
                        if !carouselAlbums.isEmpty {
                            artistAlbumCarousel(title: sections.fullAlbums.isEmpty ? L("Singles & EPs") : L("Albums"), items: carouselAlbums)
                        }

                        // Singles & EPs horizontal carousel (shown separately when full albums also exist).
                        if !sections.fullAlbums.isEmpty && !sections.singlesAndEPs.isEmpty {
                            artistAlbumCarousel(title: L("Singles & EPs"), items: sections.singlesAndEPs)
                        }

                        // Features & Credited sections (if present).
                        if !featured.isEmpty {
                            Text(L("Features"))
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.top, 28)
                                .padding(.bottom, 10)
                            ForEach(Array(featured.prefix(10).enumerated()), id: \.element.id) { index, song in
                                artistSongRow(song: song, list: featured, index: index, songActions: songActions,
                                              showsDivider: index < min(featured.count, 10) - 1)
                            }
                        }

                        if !unverified.isEmpty {
                            Text(L("Credited"))
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.top, 28)
                                .padding(.bottom, 10)
                            ForEach(Array(unverified.prefix(10).enumerated()), id: \.element.id) { index, song in
                                artistSongRow(song: song, list: unverified, index: index, songActions: songActions,
                                              showsDivider: index < min(unverified.count, 10) - 1)
                            }
                        }

                        if primary.isEmpty && featured.isEmpty {
                            EmptyState(message: "No tracks found for this artist.")
                                .padding(.top, 24)
                        }

                        Color.clear.frame(height: AppNavigationMetrics.reservedHeight + 28)
                        }
                        .frame(width: width)
                    }
                    .frame(width: width)
                } else {
                    EmptyState(message: "This artist is no longer in your library.", systemImage: "person")
                        .padding(.top, 120)
                }
            }
            .coordinateSpace(name: ArtistScrollPortrait<EmptyView>.coordinateSpace)
            .accessibilityIdentifier("artistPage")
            .scrollIndicators(.hidden)
        }
        .tracksLibraryScrolling()
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .modifier(CollectionTopEdgeEffect())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let shareSong = sections.topSongs.first ?? allSongs.first {
                    Button { router.share(shareSong, actions: actions) } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L("Share"))
                }
                Menu {
                    Button { actions.playShuffled(allSongs, source: .artist(artistId)) } label: {
                        Label(L("Shuffle"), systemImage: "shuffle")
                    }
                    .disabled(allSongs.isEmpty)
                    Button { allSongs.reversed().forEach { actions.playNext($0) } } label: {
                        Label(L("Play next"), systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .disabled(allSongs.isEmpty)
                    Button { allSongs.forEach { actions.addToQueue($0) } } label: {
                        Label(L("Add to queue"), systemImage: "text.badge.plus")
                    }
                    .disabled(allSongs.isEmpty)
                    Divider()
                    Button { actions.fixTags(primary + featured + unverified) } label: {
                        Label(L("Fix tags online"), systemImage: "wand.and.stars")
                    }
                    if radioAvailable {
                        Button { router.open(.radio(.artist(artistId))) } label: {
                            Label(L("Browse radio"), systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                    if let artist = library.artist(artistId) {
                        Button { artworkTarget = .artist(artist) } label: {
                            Label(L("Find a photo"), systemImage: "person.crop.square")
                        }
                        if artist.artworkPath != nil {
                            Button(role: .destructive) { AppServices.shared.artwork.removePhoto(artist) } label: {
                                Label(L("Remove photo"), systemImage: "trash")
                            }
                        }
                    }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Artist options")
            }
        }
        .sheet(item: $artworkTarget) { ArtworkPickerSheet(target: $0) }
        .sheet(isPresented: $showsInfoSheet) {
            if let artist = library.artist(artistId) {
                ArtistInfoSheet(
                    artist: artist,
                    songs: allSongs,
                    albums: albums,
                    facts: library.browseFacts,
                    radioAvailable: radioAvailable,
                    onFindPhoto: {
                        showsInfoSheet = false
                        artworkTarget = .artist(artist)
                    },
                    onFixTags: {
                        showsInfoSheet = false
                        actions.fixTags(primary + featured + unverified)
                    },
                    onBrowseRadio: {
                        showsInfoSheet = false
                        router.open(.radio(.artist(artistId)))
                    }
                )
            }
        }
        .sheet(isPresented: $showsAllSongsSheet) {
            if let artist = library.artist(artistId) {
                ArtistAllSongsSheet(
                    artistName: artist.name,
                    songs: allSongs,
                    artistId: artistId,
                    songActions: songActions
                )
            }
        }
        .task(id: library.songs) { load() }
        .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { _ in artworkRevision += 1 }
        .task(id: "\(source.isImage)|\(source.url?.path ?? "")|\(artworkRevision)") {
            guard let url = source.url else { return }
            let revision = ArtworkLoader.shared.revision(for: url.path)
            let next = await LyricsPaletteCache.shared.palette(for: source)
            guard !Task.isCancelled else { return }
            artworkPalette.set(next, for: source, revision: revision)
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [baseTone, midTone, deepTone],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Color.white.opacity(0.05)
            }
            .ignoresSafeArea()
        }
    }

    private func load() {
        let db = library.database
        albums = (try? db.albumsOfArtist(artistId)) ?? []
        primary = (try? db.songsOfArtist(artistId, role: .primary)) ?? []
        featured = (try? db.songsOfArtist(artistId, role: .featured)) ?? []
        if let key = library.artist(artistId)?.artistKey, !key.isEmpty {
            unverified = (try? db.unverifiedSongs(artistKey: key)) ?? []
        }
    }

    private func featuredEyebrow(_ album: Album) -> String {
        if (1900...2099).contains(album.year) {
            return String(album.year)
        }
        return L("Latest Release")
    }

    private func featuredSubtitle(_ album: Album) -> String {
        let albumSongs = (primary + featured).filter { $0.albumId == album.id }
        return countLabel(max(album.songCount, albumSongs.count), "song")
    }

    private func albumDescription(_ album: Album) -> String {
        let albumSongs = (primary + featured).filter { $0.albumId == album.id }
        let baseFacts = albumSongs.isEmpty
            ? [((1900...2099).contains(album.year) ? String(album.year) : nil), countLabel(album.songCount, "song")].compactMap { $0 }.joined(separator: " · ")
            : collectionFacts(year: album.year, songs: albumSongs)
        let genres = Array(Set(albumSongs.compactMap { $0.genre?.nonBlank })).sorted().prefix(2).joined(separator: ", ")
        return genres.isEmpty ? baseFacts : "\(baseFacts) · \(genres)"
    }

    private func artistSongRow(song: Song, list: [Song], index: Int, songActions: SongActions, showsDivider: Bool) -> some View {
        let isCurrent = player.currentSongID == song.id
        let subtitleParts: [String] = [
            song.album.nonBlank,
            (1900...2099).contains(song.year) ? String(song.year) : nil,
        ].compactMap { $0 }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    actions.play(list, startIndex: index, origin: nil, source: .artist(artistId))
                    router.openPlayer()
                } label: {
                    HStack(spacing: 12) {
                        SongArtworkView(song: song, maxPixels: 160)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(song.title)
                                    .font(.system(size: 16, weight: isCurrent ? .bold : .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if isCurrent {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.9))
                                }
                            }
                            if !subtitleParts.isEmpty {
                                Text(subtitleParts.joined(separator: " · "))
                                    .font(.system(size: 13.5, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.68))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    SongActionItems(song: song, actions: songActions)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel(L("Song options"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contextMenu {
                SongActionItems(song: song, actions: songActions)
            }

            if showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 0.5)
                    .padding(.leading, 78)
                    .padding(.trailing, 20)
            }
        }
    }

    private func artistAlbumCarousel(title: String, items: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { album in
                        Button { router.open(.album(album.id)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AlbumArtworkView(albumId: album.id, maxPixels: 360)
                                    .frame(width: 168, height: 168)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                                Text(album.title)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if (1900...2099).contains(album.year) {
                                    Text(String(album.year))
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Color.white.opacity(0.68))
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 168, alignment: .leading)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 28)
    }
}

private struct ArtistInfoSheet: View {
    let artist: Artist
    let songs: [Song]
    let albums: [Album]
    let facts: [Int64: LibraryBrowseFact]
    let radioAvailable: Bool
    let onFindPhoto: () -> Void
    let onFixTags: () -> Void
    let onBrowseRadio: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let totalPlays = songs.reduce(0) { $0 + (facts[$1.id]?.plays ?? 0) }
        let genres = Array(Set(songs.compactMap { $0.genre?.nonBlank })).sorted()
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ArtistArtworkView(artist: artist, fontSize: 28, maxPixels: 240)
                            .frame(width: 68, height: 68)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.name).font(.title3.weight(.bold))
                            Text(collectionFacts(songs: songs))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(L("Library summary")) {
                    LabeledContent(L("Songs"), value: "\(songs.count)")
                    LabeledContent(L("Albums"), value: "\(albums.count)")
                    LabeledContent(L("Total plays"), value: "\(totalPlays)")
                    if !genres.isEmpty {
                        LabeledContent(L("Genres"), value: genres.prefix(4).joined(separator: ", "))
                    }
                }
                Section {
                    Button(action: onFindPhoto) { Label(L("Find a photo"), systemImage: "person.crop.square") }
                    Button(action: onFixTags) { Label(L("Fix tags online"), systemImage: "wand.and.stars") }
                    if radioAvailable {
                        Button(action: onBrowseRadio) { Label(L("Browse radio"), systemImage: "dot.radiowaves.left.and.right") }
                    }
                }
            }
            .navigationTitle(L("Artist info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ArtistAllSongsSheet: View {
    let artistName: String
    let songs: [Song]
    let artistId: Int64
    let songActions: SongActions
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    HStack(spacing: Spacing.md) {
                        Button {
                            actions.playInOrder(songs, source: .artist(artistId))
                            dismiss()
                            router.openPlayer()
                        } label: {
                            Label(L("Play"), systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            actions.playShuffled(songs, source: .artist(artistId))
                            dismiss()
                            router.openPlayer()
                        } label: {
                            Label(L("Shuffle"), systemImage: "shuffle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)

                    SongList(songs: songs, source: .artist(artistId))
                }
            }
            .navigationTitle(artistName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}

/// A playlist: cover, facts, Play / Shuffle, its songs; rename, delete, remove a song.
struct PlaylistDetailView: View {
    @Environment(\.radioAvailable) private var radioAvailable
    let playlistId: Int64
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PlaylistEntry] = []
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var coverItem: PhotosPickerItem?
    @State private var choosingCover = false

    var body: some View {
        let origin = CollectionRef.playlist(playlistId)
        let songs = entries.map(\.song)
        let slots = entries.map(\.position)
        let songActions = playlistSongActions()
        PlayerSongReveal(destination: .playlist(playlistId), songs: songs, alphabetEnabled: true) {
            ScrollView {
                if let playlist = library.playlist(playlistId) {
                    LazyVStack(spacing: 0) {
                        CollectionHeader(title: playlist.name, subtitle: nil, facts: collectionFacts(songs: songs), canPlay: !songs.isEmpty,
                                         onPlay: { actions.playInOrder(songs, origin: origin, slots: slots) },
                                         onShuffle: { actions.playShuffled(songs, origin: origin, slots: slots) }) { PlaylistCoverView(playlist: playlist) }
                        if songs.count > 1 { TransitionStudioRow(collection: origin).padding(.bottom, Spacing.sm) }
                        if songs.isEmpty {
                            EmptyState(message: "This playlist is empty. Add songs from any song's menu.", systemImage: "music.note.list")
                        }
                        ScopedTagRepairSummary(songs: songs)
                        CollectionTransitionTrackList(collection: origin,
                            tracks: entries.map { StudioTrack(song: $0.song, occurrence: TrackOccurrence($0.song.id, $0.position)) },
                            songActions: songActions)
                    }
                } else {
                    EmptyState(message: "This playlist no longer exists.", systemImage: "music.note.list")
                }
            }
        }
        .tracksLibraryScrolling()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                if radioAvailable {
                    Button { router.open(.radio(.song(songs.first?.id ?? 0))) } label: { Label("Browse radio", systemImage: "dot.radiowaves.left.and.right") }
                        .disabled(songs.isEmpty)
                }
                Button {
                    newName = library.playlist(playlistId)?.name ?? ""
                    renaming = true
                } label: { Label("Rename", systemImage: "pencil") }
                Button { actions.fixTags(songs) } label: { Label("Fix tags online", systemImage: "wand.and.stars") }
                Button { choosingCover = true } label: { Label("Choose cover", systemImage: "photo") }
                if let playlist = library.playlist(playlistId), playlist.artworkPath != nil {
                    Button { AppServices.shared.artwork.removePlaylistCover(playlist) } label: { Label("Remove cover", systemImage: "photo.badge.minus") }
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete playlist", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Playlist options")
        }
        .photosPicker(isPresented: $choosingCover, selection: $coverItem, matching: .images)
        .onChange(of: coverItem) { _, item in
            guard let item, let playlist = library.playlist(playlistId) else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    do {
                        try AppServices.shared.artwork.setPlaylistCover(data, playlist: playlist)
                    } catch {
                        actions.show("Couldn't save the cover: \(error.localizedDescription)")
                    }
                }
                coverItem = nil
            }
        }
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = newName.trimmed
                guard !trimmed.isEmpty else { return }
                try? library.database.renamePlaylist(playlistId, name: trimmed)
            }
        }
        .confirmationDialog("Delete this playlist?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let oldCover = library.playlist(playlistId)?.artworkPath
                try? library.database.deletePlaylist(playlistId)
                if let old = oldCover, !old.hasPrefix("/") {
                    try? FileManager.default.removeItem(atPath: LibraryPaths.resolveImage(old))
                }
                dismiss()
            }
        } message: {
            Text("The songs stay in your library.")
        }
        .task(id: library.playlists) { entries = (try? library.database.playlistEntries(playlistId)) ?? [] }
        .task(id: library.songs) { entries = (try? library.database.playlistEntries(playlistId)) ?? [] }
    }

    private func playlistSongActions() -> SongActions {
        var songActions = router.songActions(actions, source: .playlist(playlistId))
        songActions.removeFromPlaylist = { remove($0) }
        return songActions
    }

    private func remove(_ song: Song) {
        try? library.database.removeSong(song.id, fromPlaylist: playlistId)
    }
}
