import SwiftUI

/// The ordinary collection song list, with direct access to each adjacent pair's editor.
struct CollectionTransitionTrackList: View {
    let collection: CollectionRef
    let tracks: [StudioTrack]
    var showTrackNumbers = false
    var albumStyle = false
    var songActions: SongActions? = nil
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(TransitionSettingsStore.self) private var transitions
    @Environment(\.palette) private var palette
    @State private var draft: EditorDraft?

    var body: some View {
        let songs = tracks.map(\.song)
        let slots = collection.kind == .playlist ? tracks.compactMap(\.occurrence.slot) : nil
        let pairs = collectionTransitionPairs(collection, tracks: tracks, config: transitions.config)
        let rowActions = songActions ?? router.songActions(actions, source: PlaybackSource(collection))
        LazyVStack(spacing: 0) {
            if albumStyle && !tracks.isEmpty {
                Rectangle()
                    .fill(palette.onSurface.opacity(0.14))
                    .frame(height: 0.5)
                    .padding(.horizontal, Spacing.lg)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.occurrence) { index, track in
                let isCurrent = track.song.id == player.state.currentSong?.id
                let anchorID = tracks.firstIndex(where: { $0.song.id == track.song.id }) == index
                    ? "amp-song-\(track.song.id)" : "amp-occurrence-\(index)"
                if albumStyle {
                    let displayNumber = track.song.trackNumber > 0 ? track.song.trackNumber : index + 1
                    VStack(spacing: 0) {
                        AlbumTrackRow(song: track.song, isCurrent: isCurrent, trackNumber: displayNumber, actions: rowActions) {
                            actions.play(songs, startIndex: index, origin: collection, slots: slots)
                        }
                        Rectangle()
                            .fill(palette.onSurface.opacity(0.14))
                            .frame(height: 0.5)
                            .padding(.leading, index == tracks.count - 1 ? Spacing.lg : 56)
                            .padding(.trailing, Spacing.lg)
                    }
                    .id(anchorID)
                } else {
                    TrackRow(song: track.song, isCurrent: isCurrent,
                             showTrackNumber: showTrackNumbers, displayTrackNumber: showTrackNumbers ? index + 1 : nil,
                             actions: rowActions) {
                        actions.play(songs, startIndex: index, origin: collection, slots: slots)
                    }
                    .id(anchorID)
                }
                if pairs.indices.contains(index) {
                    CollectionTransitionConnector(pair: pairs[index]) {
                        draft = EditorDraft.open(.pair(pairs[index]), config: transitions.config)
                    }
                }
            }
        }
        .sheet(item: $draft) { _ in
            TransitionEditorView(draft: $draft, noun: collection.kind == .album ? "album" : "playlist")
        }
    }
}

/// Clean numbered track row for album detail pages: optional leading favorite star, track number,
/// title + artist, swipe-to-queue/favorite, and compact horizontal options menu.
private struct AlbumTrackRow: View {
    let song: Song
    let isCurrent: Bool
    let trackNumber: Int
    let actions: SongActions
    let onTap: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipe: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isCurrent ? palette.primary : palette.onSurfaceVariant)
                    .opacity(song.isFavorite ? 1 : 0)
                    .frame(width: 12)
                    .accessibilityHidden(true)
                Text("\(trackNumber)")
                    .font(.system(size: 15, weight: .regular).monospacedDigit())
                    .foregroundStyle(isCurrent ? palette.primary : palette.onSurfaceVariant)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isCurrent ? palette.primary : palette.onSurface)
                        .lineLimit(1)
                    if !song.artist.isBlank {
                        Text(song.artist)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .lineLimit(1)
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
            .accessibilityLabel(SongRowText.accessibilityLabel(song, includingFileDetails: false))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }

            Menu {
                SongActionItems(song: song, actions: actions)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(L("More options"))
        }
        .padding(.leading, Spacing.xs)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, 8)
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
            HStack(spacing: 10) {
                Text("\(trackNumber)")
                    .font(.system(size: 15, weight: .regular).monospacedDigit())
                    .foregroundStyle(isCurrent ? palette.primary : palette.onSurfaceVariant)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isCurrent ? palette.primary : palette.onSurface)
                        .lineLimit(1)
                    if !song.artist.isBlank {
                        Text(song.artist)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 12)
            .frame(minWidth: 280)
            .background(palette.surface)
        }
    }

    private func resetSwipe() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { swipe = 0 }
    }
}

private struct CollectionTransitionConnector: View {
    let pair: StudioPair
    let open: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            connectorLine
            Button(action: open) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                    Text(pairLabel(pair.choice))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, Spacing.sm).padding(.vertical, 6)
                .background(palette.surfaceVariant.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(palette.outline, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit transition from \(pair.from.song.title) to \(pair.to.song.title): \(pairLabel(pair.choice))")
            .accessibilityHint("Opens preview and settings for this pair")
            connectorLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Spacing.gutter + 16)
    }

    private var connectorLine: some View {
        Rectangle().fill(palette.outline).frame(width: 1, height: 6).padding(.leading, 12).accessibilityHidden(true)
    }
}
