import SwiftUI
import AVFoundation

/// Full-bleed artwork player with waveform transport and compact library navigation.
struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.playerForegroundInk) private var playerInk
    @Environment(\.playerArtworkPresent) private var playerArtworkPresent
    @Environment(\.colorScheme) private var themeScheme
    @Environment(\.palette) private var palette
    @Environment(\.playerReduceMotion) private var reduceMotion
    @Environment(\.appNavigationBottomInset) private var navigationBottomInset
    @Environment(\.appNavigationIsShared) private var sharedNavigation
    @State private var artworkDrag = 0.0
    @State private var artworkGestureMode = 0
    @State private var artworkGestureEntry: UUID?
    @State private var artworkDominant: UInt32 = LyricsPalette.fallback.artworkDominant
    @State private var artworkRevision = 0
    let drag: PlayerDragState
    @State private var showsQueue = false
    @State private var showsLyrics = false
    @State private var showsMarks = false
    @State private var marksRevision = 0
    @State private var showsVisualizer = false
    @State private var showsAudioDetails = false
    @GestureState private var artworkGestureActive = false

    private var artworkControls: PlayerBackdropPalette.ControlColors? {
        guard playerArtworkPresent, settings.customTheme == nil else { return nil }
        let bg = settings.playerBackground
        return PlayerBackdropPalette.controlColors(
            for: Color(argb: artworkDominant),
            style: bg.gradientStyle,
            scheme: themeScheme,
            colorStyle: bg.controlColorStyle
        )
    }

    var body: some View {
        let state = player.state
        let artworkURL = state.currentSong?.url
        GeometryReader { geometry in
            if let current = state.currentSong {
                let song = library.songs.first(where: { $0.id == current.id }) ?? current
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .accessibilityAction(named: "Close player") { close() }
                    artworkInteraction(width: width)
                        .frame(width: width, height: height * 0.55)
                        .position(x: width / 2, y: height * 0.275)
                    Button { reveal(song, album: false) } label: {
                        Text(song.title)
                        .font(.system(size: PlayerButtonConstants.titleSize * PlayerLayoutMetrics.titleScale, weight: PlayerButtonConstants.titleWeight))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    }
                        .accessibilityIdentifier("nowPlayingTitle")
                        .frame(width: width - 32).position(x: width / 2, y: height * PlayerArtworkComposition.titleCentreH)
                    Button { reveal(song, album: true) } label: {
                        Text(song.artist + PlayerButtonConstants.metadataSeparator + song.album)
                        .font(.system(size: PlayerButtonConstants.subtitleSize * PlayerLayoutMetrics.subtitleScale, weight: PlayerButtonConstants.subtitleWeight))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                    }
                        .accessibilityIdentifier("nowPlayingAlbum")
                        .frame(width: width - 32).position(x: width / 2, y: height * 0.633)
                    referenceOptions(song, state: state, width: width)
                        .frame(width: width, height: 48).position(x: width / 2, y: height * PlayerLayoutMetrics.secondaryCentreH)
                    ProgressSection(song: song, screenWidth: width, marksRevision: marksRevision, controlColors: artworkControls) { controls(state, width: width) }
                        .frame(width: width - 20, height: height * 0.18)
                        .position(x: width / 2, y: height * PlayerLayoutMetrics.transportCentreH)
                    let navCentreY = AppNavigationMetrics.centreY(height: height, safeAreaBottom: navigationBottomInset)
                    Button { showsAudioDetails = true } label: {
                        Text(audioSummary(song)).font(.system(size: 10.5 * PlayerLayoutMetrics.technicalTextScale, weight: .bold))
                            .foregroundStyle(artworkControls?.accentInk.opacity(0.80) ?? playerInk)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(width: width - 24)
                    .position(x: width / 2, y: settings.playerBackground.navBarCapsule ? min(height * 0.874, navCentreY - 43) : height * 0.895)
                    if !sharedNavigation {
                        referenceNavigation(width: width)
                            .position(x: width / 2, y: navCentreY)
                    }
                }
                .foregroundStyle(playerInk)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: artworkDominant)
            } else {
                ZStack {
                    EmptyState(message: "Nothing is playing. Pick a song from your library.", systemImage: "music.note")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !sharedNavigation {
                        referenceNavigation(width: geometry.size.width)
                            .position(x: geometry.size.width / 2,
                                      y: AppNavigationMetrics.centreY(height: geometry.size.height, safeAreaBottom: navigationBottomInset))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.visible)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PlayerForegroundMotion(drag: drag, externallyFaded: true))
        .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
            if note.object as? String == artworkURL?.path { artworkRevision += 1 }
        }
        .task(id: "\(artworkURL?.path ?? "")|\(artworkRevision)") {
            guard let artworkURL else { return }
            let sampled = await LyricsPaletteCache.shared.palette(for: artworkURL)
            guard !Task.isCancelled else { return }
            artworkDominant = sampled.artworkDominant
        }
        .onChange(of: artworkGestureActive) { _, active in
            guard !active else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                guard !artworkGestureActive, artworkGestureMode != 0 else { return }
                artworkGestureMode = 0
                artworkGestureEntry = nil
                restoreArtworkDrag()
                drag.cancelGesture(reduceMotion: reduceMotion)
            }
        }
        .onChange(of: drag.isMoving, initial: true) { _, active in player.setVisualMotion(.presentation, active: active) }
        .onDisappear {
            player.setVisualMotion(.presentation, active: false)
            player.setVisualMotion(.carousel, active: false)
        }
        .background(backdrop(state.currentSong).ignoresSafeArea())
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { toast }
        .animation(.easeInOut(duration: 0.2), value: actions.message)
        .routerSheets(active: true)
        .sheet(isPresented: $showsQueue) { QueueSheet().preferredColorScheme(themeScheme) }
        .sheet(isPresented: $showsMarks, onDismiss: { marksRevision += 1 }) { MarksSheet().preferredColorScheme(themeScheme) }
        .sheet(isPresented: $showsAudioDetails) { AudioDetailsView().preferredColorScheme(themeScheme) }
        .fullScreenCover(isPresented: $showsVisualizer) { VisualizerView().preferredColorScheme(themeScheme) }
        .fullScreenCover(isPresented: $showsLyrics) { ExpandedLyrics(previous: { player.skipPrevious() }, next: next).preferredColorScheme(themeScheme) }
    }

    private func artworkInteraction(width: CGFloat) -> some View {
        Rectangle().fill(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .updating($artworkGestureActive) { _, active, _ in active = true }
            .onChanged { sample in
                if artworkGestureMode == 0 {
                    if HorizontalGestureIntent.accepts(sample.translation) { artworkGestureMode = 1 }
                    else if sample.translation.height > abs(sample.translation.width) { artworkGestureMode = 2 }
                    else { return }
                    artworkGestureEntry = player.state.currentEntry?.id
                }
                guard artworkGestureEntry == player.state.currentEntry?.id else { return }
                if artworkGestureMode == 1 {
                    let direction = sample.translation.width < 0 ? 1 : -1
                    let available = canSwipeArtwork(direction)
                    artworkDrag = Double(sample.translation.width / max(width, 1)).clamped(-0.95, 0.95) * (available ? 1 : 0.12)
                } else { pulled(sample.translation.height) }
            }
            .onEnded { sample in
                defer { artworkGestureMode = 0; artworkGestureEntry = nil }
                guard artworkGestureEntry == player.state.currentEntry?.id else { restoreArtworkDrag(); return }
                if artworkGestureMode == 1 {
                    let velocity = (sample.predictedEndTranslation.width - sample.translation.width) * 5
                    let direction = ArtworkSwipeIntent.direction(translation: Double(sample.translation.width),
                        velocity: Double(velocity), width: Double(width),
                        canNext: canSwipeArtwork(1), canPrevious: canSwipeArtwork(-1))
                    if direction > 0 { player.skipNext() }
                    else if direction < 0 { player.skipToPreviousItem() }
                    else { restoreArtworkDrag() }
                } else if artworkGestureMode == 2 {
                    pullEnded(sample.translation.height, sample.predictedEndTranslation.height)
                } else { restoreArtworkDrag() }
            })
        .accessibilityElement()
        .accessibilityLabel("Album artwork")
        .accessibilityIdentifier("nowPlayingArtwork")
        .accessibilityAction(named: "Next track") { player.skipNext() }
        .accessibilityAction(named: "Previous track") { player.skipToPreviousItem() }
    }

    private func canSwipeArtwork(_ direction: Int) -> Bool {
        let state = player.state
        let index = direction > 0
            ? PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true)
            : PlayOrder.previous(before: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode)
        guard let index, state.queue.indices.contains(index) else { return false }
        return state.queue[index].id != state.currentEntry?.id
    }

    private func restoreArtworkDrag() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { artworkDrag = 0 }
    }

    private func pulled(_ distance: CGFloat) { drag.update(distance) }

    private func pullEnded(_ distance: CGFloat, _ predicted: CGFloat) {
        if distance > 140 || predicted > 420 {
            close(velocity: (predicted - distance) * 4)
        } else {
            drag.restore(reduceMotion: reduceMotion)
        }
    }

    private func close(velocity: CGFloat? = nil) {
        drag.beginDismissal(reduceMotion: reduceMotion, velocity: velocity)
        router.showsNowPlaying = false
    }

    private func reveal(_ song: Song, album: Bool) {
        if !router.revealSong(song, album: album, source: player.state.currentEntry?.source, library: library) {
            actions.show(PlayerButtonConstants.locationUnavailable)
        }
    }

    private func next() { player.skipNext() }

    @ViewBuilder
    private var toast: some View {
        if let message = actions.message {
            LibraryActionToast(text: message, id: actions.messageID)
                .padding(.bottom, AppNavigationMetrics.effectiveBottomInset(navigationBottomInset) + AppNavigationMetrics.bottomPadding + AppNavigationMetrics.buttonsHeight + LibraryToastMetrics.navigationGap)
        }
    }

    private func menu(width: CGFloat) -> some View {
        let song = player.state.currentSong
        return Menu {
            Button { showsQueue = true } label: { Label(L("Queue"), systemImage: "list.bullet") }
            Button { showsLyrics = true } label: { Label(L("Lyrics"), systemImage: "quote.bubble") }
            Button { if let song { router.songsForPlaylist = [song] } } label: { Label(L("Add to playlist"), systemImage: "music.note.list") }
            Button { showsVisualizer = true } label: { Label(L("Visualizer"), systemImage: "waveform") }
            Button { showsMarks = true } label: {
                Label(player.state.abLoop?.enabled == true ? L("Bookmarks & A–B loop (on)") : L("Bookmarks & A–B loop"), systemImage: "bookmark.square")
            }
            Button { router.songForDetails = song } label: { Label(L("Music information"), systemImage: "info.circle") }
            Divider()
            Button { close() } label: { Label(L("Close player"), systemImage: "chevron.down") }
                .accessibilityIdentifier("closeNowPlaying")
        } label: {
            Image(systemName: PlayerButtonConstants.optionsSymbol)
                .resizable().scaledToFit()
                .frame(width: width * PlayerLayoutMetrics.secondaryIconW, height: width * PlayerLayoutMetrics.secondaryIconW)
                .rotationEffect(.degrees(PlayerButtonConstants.optionsRotation))
                .font(.system(size: PlayerButtonConstants.iconSize, weight: .black))
                .foregroundStyle(playerInk.opacity(PlayerButtonConstants.iconOpacity))
                .frame(width: PlayerButtonConstants.touchSize, height: PlayerButtonConstants.touchSize)
                .contentShape(Rectangle())
        }.accessibilityIdentifier("nowPlayingMenu")
        .menuStyle(.button)
        .menuOrder(.fixed)
        .disabled(song == nil)
        .accessibilityLabel(PlayerButtonConstants.optionsLabel)
    }

    private func referenceOptions(_ song: Song, state: PlaybackState, width: CGFloat) -> some View {
        ZStack {
            PlayerFavoriteButton(isFavorite: song.isFavorite, iconWidth: width * PlayerLayoutMetrics.heartIconW, ink: playerInk, reduceMotion: reduceMotion) {
                actions.toggleFavorite(song)
            }
            .position(x: width * PlayerLayoutMetrics.secondaryCentresW[0], y: 24)
            PlayerShareButton(song: song, iconWidth: width * PlayerLayoutMetrics.secondaryIconW)
                .position(x: width * PlayerLayoutMetrics.secondaryCentresW[1], y: 24)
            menu(width: width).position(x: width * PlayerLayoutMetrics.secondaryCentresW[2], y: 24)
            ToggleIcon(systemImage: "shuffle", active: state.shuffleModeEnabled, iconWidth: width * PlayerLayoutMetrics.secondaryIconW) {
                player.setShuffleModeEnabled(!state.shuffleModeEnabled)
            }.accessibilityLabel("Shuffle").position(x: width * PlayerLayoutMetrics.secondaryCentresW[3], y: 24)
            ToggleIcon(systemImage: state.repeatMode == .one ? "repeat.1" : "repeat", active: state.repeatMode != .off, iconWidth: width * PlayerLayoutMetrics.secondaryIconW) {
                player.cycleRepeatMode()
            }.accessibilityLabel("Repeat").position(x: width * PlayerLayoutMetrics.secondaryCentresW[4], y: 24)
        }
    }

    private func controls(_ state: PlaybackState, width: CGFloat) -> some View {
        let playIntent = state.isPlaying || state.status == .buffering
        let inset: CGFloat = 10 // Match the existing waveform's horizontal inset.
        let centres = PlayerLayoutMetrics.transportCentresW
        let outer = width * PlayerLayoutMetrics.outerDiameterW
        let inner = width * PlayerLayoutMetrics.innerDiameterW
        let main = width * PlayerLayoutMetrics.playDiameterW
        // Stable slots keep every centre fixed while the main circle animates in size.
        let slots: [CGFloat] = [outer, inner, main, inner, outer]
        let gaps: [CGFloat] = (0..<4).map { index -> CGFloat in
            let separation: CGFloat = centres[index + 1] - centres[index]
            let radii: CGFloat = (slots[index] + slots[index + 1]) / 2
            return width * separation - radii
        }
        return HStack(spacing: 0) {
            transport("seek.backward", identifier: "nowPlayingRewind", label: "Rewind 10 seconds", size: outer, action: { player.seek(to: max(0, player.currentPositionMs() - 10_000)) })
                .frame(width: outer)
            Spacer(minLength: 0).frame(width: gaps[0])
            transport("backward.fill", identifier: "nowPlayingPreviousTrack", label: "Previous track", size: inner, action: { player.skipToPreviousItem() })
                .frame(width: inner)
            Spacer(minLength: 0).frame(width: gaps[1])
            transport(playIntent ? "pause.fill" : "play.fill", identifier: "nowPlayingPlayPause", label: playIntent ? "Pause" : "Play", size: width * (playIntent ? PlayerLayoutMetrics.pauseDiameterW : PlayerLayoutMetrics.playDiameterW), action: { player.togglePlayPause() })
                .frame(width: main, height: main)
            Spacer(minLength: 0).frame(width: gaps[2])
            transport("forward.fill", identifier: "nowPlayingNextTrack", label: "Next track", size: inner, action: next)
                .frame(width: inner)
            Spacer(minLength: 0).frame(width: gaps[3])
            transport("seek.forward", identifier: "nowPlayingForward", label: "Forward 10 seconds", size: outer, action: { player.seek(to: min(state.durationMs, player.currentPositionMs() + 10_000)) })
                .frame(width: outer)
        }
        .padding(.leading, width * centres[0] - outer / 2 - inset)
        .padding(.trailing, width * (1 - centres[4]) - outer / 2 - inset)
        .frame(width: width - inset * 2, height: main)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: playIntent)
    }

    private var themedControls: Bool { settings.customTheme != nil || settings.theme == .artwork }

    private func transport(_ symbol: String, identifier: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        let isSeek = symbol.hasPrefix("seek.")
        let circleOpacity = settings.playerBackground.buttonOpacity.clamped(0, 1)
        let baseFill: Color = artworkControls?.buttonFill ?? (themedControls ? palette.filledButton : .black)
        let iconColor: Color = circleOpacity < 0.35
            ? (artworkControls?.accentInk ?? playerInk)
            : (artworkControls?.buttonIcon ?? (themedControls ? palette.onFilledButton : .white))
        let circleFill: Color = baseFill.opacity(circleOpacity)
        return Button(action: action) {
            Group {
                if isSeek {
                    HStack(spacing: -2) {
                        ForEach(0..<3) { _ in
                            Image(systemName: symbol == "seek.backward" ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                                .resizable().scaledToFit()
                        }
                    }
                    .frame(width: size * PlayerLayoutMetrics.triangleWidthInCircle, height: size * PlayerLayoutMetrics.triangleWidthInCircle)
                } else if symbol == "backward.fill" || symbol == "forward.fill" {
                    Image(systemName: symbol).resizable().scaledToFit()
                        .frame(width: size * PlayerLayoutMetrics.triangleWidthInCircle, height: size * PlayerLayoutMetrics.triangleWidthInCircle)
                } else {
                    Image(systemName: symbol)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: symbol)
                }
            }
                .font(.system(size: size * 0.43, weight: .black))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
                .background(circleFill, in: Circle())
                .frame(minWidth: isSeek ? PlayerButtonConstants.seekTouchSize : PlayerButtonConstants.touchSize,
                       minHeight: PlayerButtonConstants.touchSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerTransportPressStyle(reduceMotion: reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityActivationPoint(UnitPoint.center)
        .accessibilityAction { action() }
        .accessibilityIdentifier(identifier)
    }

    private func referenceNavigation(width: CGFloat) -> some View {
        AppNavigationButtons(width: max(width - 2 * AppNavigationMetrics.horizontalInset, 0), inPlayer: true)
            .frame(width: width, height: AppNavigationMetrics.buttonsHeight)
    }

    private func audioSummary(_ song: Song) -> String {
        [song.sampleRate > 0 ? MediaFormats.sampleRateText(song.sampleRate) : nil,
         song.bitrate > 0 ? MediaFormats.bitrateText(song.bitrate) : nil,
         song.url.pathExtension.uppercased()].compactMap { $0 }.joined(separator: PlayerLayoutMetrics.technicalSeparator).uppercased()
    }

    private func backdrop(_ song: Song?) -> some View {
        ReferencePlayerBackdrop(song: song, artworkDrag: $artworkDrag)
    }

}

/// Apple Music–style favorite button: spring pop + radial micro-burst synchronized with tactile haptic feedback.
private struct PlayerFavoriteButton: View {
    let isFavorite: Bool
    let iconWidth: CGFloat
    let ink: Color
    let reduceMotion: Bool
    let action: () -> Void
    @State private var addPulse = 0
    @State private var removePulse = 0
    @State private var popScale: CGFloat = 1
    @State private var burstProgress: CGFloat = 0
    @State private var showingBurst = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Button {
            let adding = !isFavorite
            action()
            if adding {
                addPulse += 1
                playFavoriteAnimation()
            } else {
                removePulse += 1
                playUnfavoriteAnimation()
            }
        } label: {
            ZStack {
                if showingBurst && !reduceMotion {
                    Circle()
                        .strokeBorder(ink.opacity(Double(max(0, 1 - burstProgress)) * 0.55), lineWidth: max(0.5, 2.2 * (1 - burstProgress)))
                        .frame(width: iconWidth * (0.75 + burstProgress * 0.95), height: iconWidth * (0.75 + burstProgress * 0.95))
                    ForEach(0..<6, id: \.self) { index in
                        let angle = Double(index) * (.pi / 3) - .pi / 6
                        let radius = iconWidth * (0.42 + burstProgress * 0.62)
                        Circle()
                            .fill(ink)
                            .frame(width: max(1.5, 3.6 * (1 - burstProgress)), height: max(1.5, 3.6 * (1 - burstProgress)))
                            .opacity(Double(max(0, 1 - burstProgress)))
                            .offset(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius)
                    }
                }
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .resizable().scaledToFit()
                    .frame(width: iconWidth, height: iconWidth)
                    .font(.system(size: 25, weight: .bold))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .scaleEffect(popScale)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(isFavorite ? L("Remove from favorites") : L("Add to favorites"))
        .sensoryFeedback(.success, trigger: addPulse)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: removePulse)
        .onDisappear { animationTask?.cancel() }
    }

    private func playFavoriteAnimation() {
        animationTask?.cancel()
        guard !reduceMotion else { return }
        popScale = 0.78
        burstProgress = 0
        showingBurst = true
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
            popScale = 1.24
        }
        withAnimation(.easeOut(duration: 0.42)) {
            burstProgress = 1
        }
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.30, dampingFraction: 0.65)) {
                popScale = 1.0
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            showingBurst = false
            burstProgress = 0
        }
    }

    private func playUnfavoriteAnimation() {
        animationTask?.cancel()
        showingBurst = false
        burstProgress = 0
        guard !reduceMotion else { return }
        popScale = 0.86
        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
            popScale = 1.0
        }
    }
}

/// A toggle in the controls (shuffle, repeat): its icon dimmed when off, on a soft disc when on.
private struct ToggleIcon: View {
    let systemImage: String
    let active: Bool
    let iconWidth: CGFloat
    let action: () -> Void
    @Environment(\.playerForegroundInk) private var playerInk
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).resizable().scaledToFit()
                .frame(width: iconWidth, height: iconWidth)
                .font(.system(size: 25, weight: .black))
                .foregroundStyle(playerInk.opacity(active ? 1 : PlayerLayoutMetrics.idleOpacity))
                .frame(width: 48, height: 48)
                .background(Circle().fill(palette.primary.opacity(active ? 0.18 : 0)))
                .contentShape(Circle())
        }
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}

/// Real track waveform with transport controls overlaid and elapsed/duration badges.
private struct ProgressSection<Controls: View>: View {
    let song: Song
    let screenWidth: CGFloat
    var marksRevision: Int = 0
    var controlColors: PlayerBackdropPalette.ControlColors? = nil
    @ViewBuilder let controls: () -> Controls
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.playerReduceMotion) private var reduceMotion
    @Environment(\.playerInMotion) private var playerInMotion
    @AppStorage(PlaybackPreferences.waveformKey) private var waveformMode = PlaybackPreferences.defaultWaveform
    @State private var previewMs: Int64?
    @State private var levels: [Float]?
    @State private var levelsSongID: Int64?
    @State private var bookmarks: [Int64] = []

    private var themedBadges: Bool { settings.customTheme != nil || settings.theme == .artwork }

    var body: some View {
        let state = player.state
        let entryID = state.currentEntry?.id
        let duration = max(state.durationMs > 0 ? state.durationMs : song.durationMs, 1)
        GeometryReader { geometry in
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 60,
                                        paused: !state.isPlaying || previewMs != nil || playerInMotion)) { _ in
                    let position = player.displayPositionMs(smoothed: waveformMode == PlayerWaveformMode.scrolling.rawValue)
                    WaveformSeekBar(levels: levelsSongID == song.id ? levels : nil, positionMs: position,
                                    durationMs: duration, bookmarks: bookmarks,
                                    loop: state.abLoop?.songId == song.id ? state.abLoop : nil,
                                    previewMs: $previewMs, onSeek: { target in
                                        guard player.state.currentEntry?.id == entryID else { return }
                                        player.seek(to: target)
                                    }, referenceStyle: true, scrollsWithPlayback: waveformMode == PlayerWaveformMode.scrolling.rawValue,
                                    barHeight: geometry.size.height,
                                    referenceInk: controlColors?.accentInk)
                        .id(entryID)
                        .transition(reduceMotion ? .opacity : .modifier(
                            active: WaveformArrival(amount: 0), identity: WaveformArrival(amount: 1)))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: entryID)
                        .overlay(alignment: .bottom) {
                            HStack {
                                timeBadge(previewMs ?? position)
                                    .accessibilityIdentifier("nowPlayingElapsed")
                                Spacer()
                                timeBadge(duration)
                            }
                            .allowsHitTesting(false)
                        }
                }
                // Transport must react to scrub completion even when the waveform clock is paused.
                controls()
                    .zIndex(1)
                    .opacity(previewMs == nil ? 1 : 0)
                    .allowsHitTesting(previewMs == nil)
                    .accessibilityHidden(previewMs != nil)
                    .animation(reduceMotion ? nil : .easeInOut(duration: previewMs == nil ? 0.22 : 0.18), value: previewMs != nil)
            }
        }
        .onChange(of: entryID) { _, _ in previewMs = nil }
        .onChange(of: waveformMode) { _, _ in previewMs = nil }
        .task(id: "\(song.id)|\(marksRevision)") {
            bookmarks = ((try? AppServices.shared.database.bookmarks(songId: song.id)) ?? []).map(\.positionMs)
        }
        .task(id: entryID) {
            levels = nil
            levelsSongID = nil
            previewMs = nil
            let result = await AppServices.shared.waveforms.waveform(song)
            guard !Task.isCancelled, player.state.currentEntry?.id == entryID else { return }
            if case .ready(let loaded) = result {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    levelsSongID = song.id
                    levels = loaded
                }
            }
        }
    }

    private func timeBadge(_ ms: Int64) -> some View {
        let foreground: Color = controlColors?.buttonIcon.opacity(0.88) ?? (themedBadges ? palette.onFilledButton : .white)
        let background: Color = controlColors?.buttonFill.opacity(0.90) ?? (themedBadges ? palette.filledButton : .black)
        return Text(formatDuration(ms))
            .font(.system(size: 14 * PlayerLayoutMetrics.timeTextScale, weight: .bold).monospacedDigit())
            .foregroundStyle(foreground)
            .lineLimit(1).minimumScaleFactor(PlayerLayoutMetrics.timeMinimumScale)
            .frame(width: screenWidth * PlayerLayoutMetrics.timeBadgeW, height: PlayerLayoutMetrics.timeBadgeHeight)
            .background(background, in: Capsule())
    }
}

private struct WaveformArrival: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content.scaleEffect(x: 1, y: 0.08 + amount * 0.92).opacity(Double(amount))
    }
}

/// The cover keeps its full composition in a width-sized slot. Its lower edge
/// dissolves into the original dominant colour, which fills all remaining space.
struct PlayerArtworkBackground<Artwork: View>: View {
    let dominant: Color
    var topInset: CGFloat = 0
    var horizontalInset: CGFloat = 0
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                dominant
                artwork()
                    .frame(width: max(geometry.size.width - horizontalInset * 2, 1),
                           height: max(geometry.size.width - horizontalInset * 2, 1))
                    .shadow(color: .black.opacity(topInset > 0 ? 0.20 : 0), radius: 10, y: 3)
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: 0),
                                               .init(color: .white, location: 0.72),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .padding(.top, topInset)
                // Keep the artwork itself intact; add depth to the colour extension
                // beneath it, with some of its hue still present at the bottom.
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .clear, location: min(geometry.size.width / max(geometry.size.height, 1) * 0.72, 0.6)),
                                       .init(color: .black.opacity(0.25), location: 0.65),
                                       .init(color: .black.opacity(0.88), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                if topInset > 0 {
                    // Keep white system status text readable even over a white cover.
                    LinearGradient(stops: [.init(color: .black.opacity(0.60), location: 0),
                                           .init(color: .black.opacity(0.60), location: 0.60),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: topInset + 30)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The full lyrics over Now Playing (Android's ExpandedLyrics): the song at the top, the lyrics in
/// the artwork's colours on its gradient, previous / play / next underneath.
private struct ExpandedLyrics: View {
    let previous: () -> Void
    let next: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var artworkPalette = ArtworkPaletteState()

    var body: some View {
        let state = player.state
        let sampled = artworkPalette.palette(for: state.currentSong?.url).forScheme(scheme)
        let colors = LyricsColors(sampled)
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 48, height: 48).contentShape(Rectangle())
                }
                .accessibilityLabel("Close lyrics")
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.currentSong?.title ?? "").font(.headline).foregroundStyle(colors.content).lineLimit(1)
                    Text(state.currentSong?.artist ?? "").font(.caption).foregroundStyle(colors.secondary).lineLimit(1)
                }
                Spacer()
            }
            .foregroundStyle(colors.content)
            .padding(.leading, Spacing.xs)
            .padding(.trailing, Spacing.lg)
            .padding(.top, Spacing.sm)
            if let song = state.currentSong {
                LyricsPanel(song: song).frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            HStack(spacing: Spacing.xxl) {
                Button(action: previous) {
                    Image(systemName: "backward.fill").font(.title).frame(width: 52, height: 52).contentShape(Rectangle())
                }
                .accessibilityLabel("Previous")
                Button { player.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(Color(argb: sampled.onButtonFill))
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color(argb: sampled.buttonFill)))
                }
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
                Button(action: next) {
                    Image(systemName: "forward.fill").font(.title).frame(width: 52, height: 52).contentShape(Rectangle())
                }
                .accessibilityLabel("Next")
            }
            .foregroundStyle(colors.content)
            .padding(.vertical, Spacing.md)
        }
        .buttonStyle(.plain)
        .background(LinearGradient(colors: colors.gradient, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .task(id: state.currentSong?.url) {
            guard let url = state.currentSong?.url else { return }
            let revision = ArtworkLoader.shared.revision(for: url.path)
            let next = await LyricsPaletteCache.shared.palette(for: url)
            guard !Task.isCancelled else { return }
            artworkPalette.set(next, for: url, revision: revision)
        }
    }
}

/// The queue and what has played this session: reorder, remove (with undo), shuffle upcoming,
/// save as a playlist, play a history entry again.
struct QueueSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var savingName = ""
    @State private var saving = false
    @State private var feedback: String?
    @State private var feedbackID = UUID()

    var body: some View {
        let state = player.state
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L("Page"), selection: $page) {
                    Text(L("Queue (%d)", state.queue.count)).tag(0)
                    Text(L("History")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.sm)
                if page == 0 { queue(state) } else { history(state) }
            }
            .modifier(ToolPageAppearance())
            .navigationTitle(page == 0 ? L("Queue") : L("History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
                if page == 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button { if !player.shuffleUpcoming() { showFeedback(L("Fewer than two songs are coming up")) } } label: {
                                Label(L("Shuffle upcoming"), systemImage: "shuffle")
                            }
                            Button { saving = true } label: { Label(L("Save as playlist"), systemImage: "square.and.arrow.down") }
                            Button { showFeedback(player.undoQueueRemoval() ? L("Removal undone") : L("Nothing to undo")) } label: {
                                Label(L("Undo removal"), systemImage: "arrow.uturn.backward")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .alert(L("Save queue as playlist"), isPresented: $saving) {
                TextField(L("Name"), text: $savingName)
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Save")) {
                    actions.createPlaylist(savingName, songs: player.state.queue.map(\.song))
                    savingName = ""
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback { Toast(text: feedback).padding(.horizontal, Spacing.gutter).padding(.bottom, Spacing.md).allowsHitTesting(false) }
        }
        .task(id: feedbackID) {
            guard feedback != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            feedback = nil
        }
        .presentationDetents([.medium, .large])
    }

    private func showFeedback(_ text: String) { feedback = text; feedbackID = UUID() }

    private func queue(_ state: PlaybackState) -> some View {
        List {
            if state.queue.isEmpty {
                Text(L("No track playing")).foregroundStyle(palette.onSurfaceVariant)
                    .listRowBackground(palette.background)
            }
            ForEach(Array(state.queue.enumerated()), id: \.element.id) { index, entry in
                Button { player.skipToQueueItem(index) } label: {
                    row(entry.song, highlighted: index == state.currentIndex)
                }
                .buttonStyle(.plain)
                .opacity(index < state.currentIndex ? 0.55 : 1)
                .listRowBackground(palette.background)
            }
            .onDelete { offsets in offsets.sorted(by: >).forEach { player.removeFromQueue($0) } }
            .onMove { source, destination in
                guard let from = source.first else { return }
                player.reorder(from: from, to: destination > from ? destination - 1 : destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    private func history(_ state: PlaybackState) -> some View {
        List {
            if state.history.isEmpty {
                Text("Songs you play this session show up here.").foregroundStyle(palette.onSurfaceVariant)
                    .listRowBackground(palette.background)
            }
            ForEach(state.history) { entry in
                HStack {
                    row(entry.song, highlighted: false)
                    Button { player.playFromHistory(entry.entryId) } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(entry.song.title) again")
                }
                .listRowBackground(palette.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ song: Song, highlighted: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            SongArtworkView(song: song, maxPixels: 132)
                .frame(width: ArtworkSize.compact, height: ArtworkSize.compact)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(highlighted ? palette.primary : palette.onSurface).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
