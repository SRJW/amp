import SwiftUI

/// What can be done with a song from any list (Android's SongActions).
struct SongActions {
    var toggleFavorite: (Song) -> Void
    var playNext: (Song) -> Void
    var addToQueue: (Song) -> Void
    var startRadio: (Song) -> Void
    var addToPlaylist: (Song) -> Void
    var share: ((Song) -> Void)? = nil
    var goToAlbum: ((Song) -> Void)? = nil
    var goToArtist: ((Song) -> Void)? = nil
    var viewDetails: ((Song) -> Void)?
    var editTags: ((Song) -> Void)?
    var fixTags: ((Song) -> Void)?
    /// Playlist pages only.
    var removeFromPlaylist: ((Song) -> Void)?
    var deleteFromDevice: ((Song) -> Void)?
}

/// The song actions as menu items (a row's "…" button and its long-press menu),
/// styled after Apple Music's compact action sheet.
struct SongActionItems: View {
    let song: Song
    let actions: SongActions

    private var hasInfoMenu: Bool {
        actions.viewDetails != nil || actions.editTags != nil || actions.fixTags != nil
    }

    var body: some View {
        ControlGroup {
            Button { actions.toggleFavorite(song) } label: {
                Label(song.isFavorite ? L("Remove from favorites") : L("Add to favorites"),
                      systemImage: song.isFavorite ? "heart.slash" : "heart")
            }
            if let share = actions.share {
                Button { share(song) } label: {
                    Label(L("Share"), systemImage: "square.and.arrow.up")
                }
            }
        }
        Section {
            Button { actions.addToPlaylist(song) } label: { Label(L("Add to playlist"), systemImage: "text.badge.plus") }
        }
        Section {
            Button { actions.playNext(song) } label: { Label(L("Play next"), systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { actions.addToQueue(song) } label: { Label(L("Add to queue"), systemImage: "text.append") }
        }
        if (actions.goToAlbum != nil && song.albumId != 0) || (actions.goToArtist != nil && song.artistId != 0) {
            Section {
                if let goToAlbum = actions.goToAlbum, song.albumId != 0 {
                    Button { goToAlbum(song) } label: {
                        Text(L("Go to album"))
                        if !song.album.isBlank { Text(song.album) }
                        Image(systemName: "square.stack")
                    }
                }
                if let goToArtist = actions.goToArtist, song.artistId != 0 {
                    Button { goToArtist(song) } label: {
                        Text(L("Go to artist"))
                        if !song.artist.isBlank { Text(song.artist) }
                        Image(systemName: "person")
                    }
                }
            }
        }
        if hasInfoMenu {
            Menu {
                if let view = actions.viewDetails {
                    Button { view(song) } label: { Label(L("View metadata"), systemImage: "info.circle") }
                }
                if let edit = actions.editTags {
                    Button { edit(song) } label: { Label(L("Edit tags"), systemImage: "pencil") }
                }
                if let fix = actions.fixTags {
                    Button { fix(song) } label: { Label(L("Fix tags online"), systemImage: "wand.and.stars") }
                }
            } label: {
                Label(L("Info & tags"), systemImage: "info.circle")
            }
        }
        if actions.removeFromPlaylist != nil || actions.deleteFromDevice != nil {
            Section {
                if let remove = actions.removeFromPlaylist {
                    Button(role: .destructive) { remove(song) } label: { Label(L("Remove from playlist"), systemImage: "minus.circle") }
                }
                if let delete = actions.deleteFromDevice {
                    Button(role: .destructive) { delete(song) } label: { Label(L("Delete from device"), systemImage: "trash") }
                }
            }
        }
    }
}

enum SongRowText {
    static func fileDetails(_ song: Song) -> String {
        let ext = (song.path as NSString).pathExtension.lowercased()
        let codec = song.codec?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let format: String
        if codec == "ALAC" || codec == "AAC" || codec.hasPrefix("HE-AAC") {
            format = ext.isEmpty ? codec : "\(codec) · \(ext)"
        } else {
            format = ext.isEmpty ? (codec.isEmpty ? "audio" : codec) : ext
        }
        var details = [format]
        if song.bitrate > 0 { details.append(MediaFormats.bitrateText(song.bitrate)) }
        if song.sampleRate > 0 { details.append(MediaFormats.sampleRateText(song.sampleRate)) }
        return (song.durationMs > 0 ? formatDuration(song.durationMs) : "–:–") + " | " + details.joined(separator: " · ")
    }
    static func accessibilityLabel(_ song: Song, includingFileDetails: Bool) -> String {
        var parts = [song.title, song.artist]
        if includingFileDetails { parts += [song.album, fileDetails(song)] }
        return parts.filter { !$0.isBlank }.joined(separator: ", ")
    }
}

/// A track in a list: artwork (or track number), title (highlighted when playing), "artist · album",
/// a heart and the actions menu.
struct TrackRow: View {
    let song: Song
    let isCurrent: Bool
    var showTrackNumber = false
    var displayTrackNumber: Int? = nil
    var subtitle: String?
    var showsFileDetails = false
    var showsActions = true
    var artworkURL: URL? = nil
    let actions: SongActions
    let onTap: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipe: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            // One native recognizer pair owns playback taps and row swipes. The tap waits
            // for the horizontal pan to fail, so releasing a swipe cannot play this song.
            HStack(spacing: Spacing.md) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isCurrent ? palette.primary : palette.onSurface)
                        .lineLimit(1)
                    Text(subtitle ?? [song.artist, song.album].filter { !$0.isBlank }.joined(separator: " - "))
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                    if showsFileDetails {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.system(size: 9, weight: .semibold))
                            Text(SongRowText.fileDetails(song))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            if song.isFavorite {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                            }
                        }
                        .foregroundStyle(palette.primary.opacity(0.78))
                    } else if song.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.primary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay {
                PanInteraction(canBegin: { _, delta in HorizontalGestureIntent.accepts(delta) },
                               change: { sample in
                                   var transaction = Transaction()
                                   transaction.disablesAnimations = true
                                   withTransaction(transaction) { swipe = sample.translation.width.clamped(-112, 112) }
                               },
                               end: { sample in
                                   resetSwipe()
                                   switch SongSwipeAction.committed(translation: sample.translation, startedHorizontally: true) {
                                   case .queue: actions.addToQueue(song)
                                   case .like: actions.toggleFavorite(song)
                                   case nil: break
                                   }
                               },
                               cancel: resetSwipe,
                               tap: { _ in onTap() })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SongRowText.accessibilityLabel(song, includingFileDetails: showsFileDetails))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            if showsActions {
                Menu {
                    SongActionItems(song: song, actions: actions)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(palette.onSurfaceVariant.opacity(0.75))
                        .frame(width: 26, height: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel(L("More options"))
            }
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, showsActions ? 4 : Spacing.md)
        .padding(.vertical, 6)
        .offset(x: swipe)
        .background(alignment: swipe >= 0 ? .leading : .trailing) {
            if swipe != 0 {
                Image(systemName: swipe > 0 ? "text.badge.plus" : (song.isFavorite ? "heart.slash" : "heart.fill"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 64)
                    .frame(maxHeight: .infinity)
                    .background(palette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .opacity(min(Double(abs(swipe) / 60), 1))
                    .frame(width: abs(swipe), alignment: swipe > 0 ? .leading : .trailing)
                    .clipped()
            }
        }
        .modifier(PlayerRevealedSong(songID: song.id))
        .onDisappear { swipe = 0 }
        .accessibilityAction(named: "Add to queue") { actions.addToQueue(song) }
        .accessibilityAction(named: song.isFavorite ? "Remove from favorites" : "Add to favorites") { actions.toggleFavorite(song) }
        .contextMenu {
            SongActionItems(song: song, actions: actions)
        } preview: {
            HStack(spacing: Spacing.md) {
                SongArtworkView(url: artworkURL ?? song.url, maxPixels: 144)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2)
                    Text(subtitle ?? [song.artist, song.album].filter { !$0.isBlank }.joined(separator: " — "))
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant.opacity(0.6))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .frame(minWidth: 300)
            .background(palette.surface)
        }
    }

    private func resetSwipe() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { swipe = 0 }
    }

    @ViewBuilder private var leading: some View {
        if showTrackNumber {
            Text("\(displayTrackNumber ?? song.trackNumber)")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? palette.primary : palette.onSurfaceVariant)
                .frame(width: 52, height: 52)
        } else {
            SongArtworkView(url: artworkURL ?? song.url, maxPixels: 144)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// An artwork-first card: square cover, title, one quiet line.
struct ArtworkTile<Cover: View>: View {
    let title: String
    let subtitle: String?
    var circular = false
    let action: () -> Void
    @ViewBuilder let cover: () -> Cover
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(alignment: circular ? .center : .leading, spacing: 2) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { cover() }
                    .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)))
                    .padding(.bottom, Spacing.sm - 2)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.onSurface).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
            }
        }
        .pressable()
    }
}

struct AlbumTile: View {
    let album: Album
    let action: () -> Void

    var body: some View {
        ArtworkTile(title: album.title, subtitle: album.artist, action: action) { AlbumArtworkView(albumId: album.id) }
    }
}

struct PlaylistTile: View {
    let playlist: Playlist
    let action: () -> Void

    var body: some View {
        ArtworkTile(title: playlist.name, subtitle: countLabel(playlist.songCount, "song"), action: action) { PlaylistCoverView(playlist: playlist) }
    }
}

struct ArtistTile: View {
    let artist: Artist
    let action: () -> Void

    var body: some View {
        ArtworkTile(title: artist.name, subtitle: "\(countLabel(artist.songCount, "song")) · \(countLabel(artist.albumCount, "album"))",
                    circular: true, action: action) { ArtistArtworkView(artist: artist) }
    }
}

struct SongTile: View {
    let song: Song
    let action: () -> Void

    var body: some View {
        ArtworkTile(title: song.title, subtitle: song.artist, action: action) { SongArtworkView(song: song) }
    }
}

/// First cell of the playlist grid: same footprint as a playlist card.
struct NewPlaylistTile: View {
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        ArtworkTile(title: "New playlist", subtitle: nil, action: action) {
            ZStack {
                Rectangle().fill(palette.surfaceVariant)
                Image(systemName: "plus").font(.system(size: 32, weight: .semibold)).foregroundStyle(palette.primary)
            }
        }
    }
}

struct SectionHeading: View {
    let title: String
    var onMore: (() -> Void)?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(palette.onSurface).lineLimit(1)
            Spacer()
            if let onMore {
                Button(action: onMore) {
                    HStack(spacing: Spacing.xs) {
                        Text("More")
                        Image(systemName: "arrow.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                }
                .accessibilityLabel("More \(title)")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.sm)
    }
}

/// A titled horizontal row of cards.
struct Shelf<Content: View>: View {
    let title: String
    var onMore: (() -> Void)?
    var lazy = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title, onMore: onMore)
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if lazy { LazyHStack(alignment: .top, spacing: Spacing.md) { content() } }
                    else { HStack(alignment: .top, spacing: Spacing.md) { content() } }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.xs)
            }
        }
    }
}

struct EmptyState: View {
    let message: String
    var systemImage = "music.note"
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage).font(.system(size: 36)).foregroundStyle(palette.onSurfaceVariant)
            Text(message).font(.body).foregroundStyle(palette.onSurfaceVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.xxl)
    }
}

/// A short message that slides up above the bottom chrome and fades away.
struct Toast: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.onPrimary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Capsule().fill(palette.primary))
            .padding(.horizontal, Spacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
    }
}

enum LibraryToastMetrics {
    static let fontSize: CGFloat = 13
    static let iconSize: CGFloat = 14
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 9
    static let spacing: CGFloat = 7
    static let backgroundOpacity = 0.84
    static let duration = 1.8
    static let fadeDuration = 0.2
    static let navigationGap: CGFloat = 10
}

/// A new identity extends the display time even when consecutive actions have the same text.
struct LibraryActionToast: View {
    let text: String
    let id: UUID
    @Environment(LibraryActions.self) private var actions
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: LibraryToastMetrics.spacing) {
            if actions.messageKind != .info {
                Image(systemName: actions.messageKind == .liked ? "checkmark.circle.fill" : "heart")
                    .font(.system(size: LibraryToastMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(actions.messageKind == .liked ? Color.green : palette.onSurfaceVariant)
            }
            Text(text).font(.system(size: LibraryToastMetrics.fontSize, weight: .semibold))
                .foregroundStyle(settings.glassEnabled ? Color.primary : palette.onSurface)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, LibraryToastMetrics.horizontalPadding)
        .padding(.vertical, LibraryToastMetrics.verticalPadding)
        .glassCapsule(enabled: settings.glassEnabled)
        .padding(.horizontal, Spacing.lg)
        .transition(.opacity)
        .allowsHitTesting(false)
        .accessibilityIdentifier("libraryActionToast")
        .task(id: id) {
            do { try await Task.sleep(for: .seconds(LibraryToastMetrics.duration)) }
            catch { return }
            withAnimation(.easeOut(duration: LibraryToastMetrics.fadeDuration)) { actions.dismissMessage(id: id) }
        }
    }
}
