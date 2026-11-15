import SwiftUI

/// Constants shared by the compact player's gestures and progress hit target.
enum MiniPlayerMetrics {
    static let artworkVerticalInset: CGFloat = 16
    static let height: CGFloat = ArtworkSize.miniPlayer + artworkVerticalInset * 2
    static let horizontalInset: CGFloat = 14
    static let columnSpacing: CGFloat = 10
    static let cornerRadius: CGFloat = 32
    static let artworkCornerRadius: CGFloat = 12
    static let titleSize: CGFloat = 16
    static let subtitleSize: CGFloat = 13
    static let textSpacing: CGFloat = 2
    static let textHeight: CGFloat = 44
    static let progressHeight: CGFloat = ArtworkSize.miniPlayer - textHeight
    static let progressLineHeight: CGFloat = 4
    static let progressThumbSize: CGFloat = 10
    static let playSize: CGFloat = 24
    static let buttonWidth: CGFloat = 44
    static let swipeThreshold: CGFloat = 48
    static let dragDistance: CGFloat = 12
    static let maximumOffset: CGFloat = 36
    static let seekLabel = "Mini player progress"
    static let nextLabel = "Next track"
    static let previousLabel = "Previous track"
    static let openLabel = "Open Now Playing"
    static let artworkLabel = "Open Now Playing artwork"
    static let openHint = "Tap to open. Swipe left or right to change tracks; swipe up to open."
}

struct MiniPlayer: View {
    let song: Song
    let onOpen: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation = CGSize.zero

    var body: some View {
        let state = player.state
        let entry = state.currentEntry?.id
        HStack(spacing: MiniPlayerMetrics.columnSpacing) {
            openButton(entry: entry, identifier: "openNowPlayingArtwork", label: MiniPlayerMetrics.artworkLabel) {
                SongArtworkView(song: song, maxPixels: Int(ArtworkSize.miniPlayer * 3))
                    .frame(width: ArtworkSize.miniPlayer, height: ArtworkSize.miniPlayer)
                    .clipShape(RoundedRectangle(cornerRadius: MiniPlayerMetrics.artworkCornerRadius, style: .continuous))
                    .playerArtworkFrame(expanded: false)
                    .modifier(MiniArtworkVisibility(enabled: router.presentedTool == nil))
            }
            VStack(spacing: 0) {
                openButton(entry: entry, identifier: "openNowPlaying", label: MiniPlayerMetrics.openLabel) {
                    VStack(alignment: .leading, spacing: MiniPlayerMetrics.textSpacing) {
                        Text(song.title).font(.system(size: MiniPlayerMetrics.titleSize, weight: .semibold))
                            .foregroundStyle(palette.onSurface).lineLimit(1)
                        Text(song.subtitle).font(.system(size: MiniPlayerMetrics.subtitleSize))
                            .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: MiniPlayerMetrics.textHeight,
                           maxHeight: MiniPlayerMetrics.textHeight, alignment: .bottomLeading)
                }
                MiniPlayerProgress(durationMs: state.durationMs, entryID: entry)
                    .id(entry)
                    .frame(height: MiniPlayerMetrics.progressHeight)
            }
            .frame(maxWidth: .infinity)
            Button { player.togglePlayPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: MiniPlayerMetrics.playSize, weight: .semibold))
                    .frame(width: MiniPlayerMetrics.buttonWidth, height: ArtworkSize.miniPlayer)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("miniPlayerPlayPause")
        }
        .foregroundStyle(palette.onSurface)
        .buttonStyle(.plain)
        .padding(.horizontal, MiniPlayerMetrics.horizontalInset)
        .padding(.vertical, MiniPlayerMetrics.artworkVerticalInset)
        .frame(height: MiniPlayerMetrics.height)
        .contentShape(Rectangle())
    }

    /// Both open areas share gestures; progress and play/pause remain independent siblings.
    private func openButton<Label: View>(entry: UUID?, identifier: String, label: String,
                                         @ViewBuilder content: () -> Label) -> some View {
        Button(action: onOpen) {
            content()
                .offset(x: reduceMotion ? 0 : min(max(translation.width, -MiniPlayerMetrics.maximumOffset), MiniPlayerMetrics.maximumOffset))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityValue("\(song.title), \(song.subtitle)")
        .accessibilityHint(MiniPlayerMetrics.openHint)
        .accessibilityAction(named: MiniPlayerMetrics.nextLabel) { player.skipNext() }
        .accessibilityAction(named: MiniPlayerMetrics.previousLabel) { player.skipToPreviousItem() }
        .highPriorityGesture(DragGesture(minimumDistance: MiniPlayerMetrics.dragDistance)
            .updating($translation) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard player.state.currentEntry?.id == entry else { return }
                let delta = value.translation
                if abs(delta.width) > abs(delta.height) * 1.3, abs(delta.width) >= MiniPlayerMetrics.swipeThreshold {
                    if delta.width < 0 { player.skipNext() } else { player.skipToPreviousItem() }
                } else if -delta.height >= MiniPlayerMetrics.swipeThreshold, abs(delta.height) > abs(delta.width) * 1.3 {
                    onOpen()
                }
            })
    }
}

/// Seek has its own gesture region, separate from the song's horizontal swipe.
private struct MiniPlayerProgress: View {
    let durationMs: Int64
    let entryID: UUID?
    @Environment(PlayerController.self) private var player
    @Environment(\.palette) private var palette
    @State private var preview: Int64?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !player.state.isPlaying || preview != nil)) { _ in
            let position = preview ?? player.displayPositionMs()
            GeometryReader { geometry in
                let fraction = durationMs > 0 ? min(max(Double(position) / Double(durationMs), 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.onSurfaceVariant.opacity(0.25)).frame(height: MiniPlayerMetrics.progressLineHeight)
                    Capsule().fill(palette.primary).frame(width: geometry.size.width * fraction, height: MiniPlayerMetrics.progressLineHeight)
                    if preview != nil {
                        Circle().fill(palette.primary).frame(width: MiniPlayerMetrics.progressThumbSize, height: MiniPlayerMetrics.progressThumbSize)
                            .offset(x: min(max(geometry.size.width * fraction - MiniPlayerMetrics.progressThumbSize / 2, 0),
                                           max(geometry.size.width - MiniPlayerMetrics.progressThumbSize, 0)))
                    }
                }
                .frame(height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard player.state.currentEntry?.id == entryID, durationMs > 0 else { return }
                        preview = FullTrackWaveformGeometry(durationMs: durationMs, width: geometry.size.width).position(at: value.location.x)
                    }
                    .onEnded { value in
                        defer { preview = nil }
                        guard player.state.currentEntry?.id == entryID, durationMs > 0 else { return }
                        player.seek(to: FullTrackWaveformGeometry(durationMs: durationMs, width: geometry.size.width).position(at: value.location.x))
                    })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MiniPlayerMetrics.seekLabel)
            .accessibilityIdentifier("miniPlayerProgress")
            .accessibilityValue("\(formatDuration(position)) of \(formatDuration(durationMs))")
            .accessibilityAdjustableAction { direction in
                let delta: Int64 = direction == .increment ? 10_000 : -10_000
                player.seek(to: min(max(player.currentPositionMs() + delta, 0), durationMs))
            }
        }
        .disabled(durationMs <= 0)
        .onChange(of: entryID) { _, _ in preview = nil }
        .onDisappear { preview = nil }
    }
}
