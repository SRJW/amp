import SwiftUI
import AVFoundation
import AVKit

/// Full-bleed artwork player with waveform transport and compact library navigation.
struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(SoundStore.self) private var sound
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
                    let waveformHeight = height * PlayerLayoutMetrics.waveformHeightH
                    let waveformCentreY = height * PlayerLayoutMetrics.transportCentreH
                    let waveformBottom = waveformCentreY + waveformHeight / 2
                    let navCentreY = AppNavigationMetrics.centreY(height: height, safeAreaBottom: navigationBottomInset)
                    let navTop = navCentreY - (settings.playerBackground.navBarCapsule ? AppNavigationMetrics.capsuleHeight / 2 : 16)
                    let bitrateCentreY = (waveformBottom + navTop) / 2
                    ProgressSection(song: song, screenWidth: width, marksRevision: marksRevision, controlColors: artworkControls) { controls(state, width: width) }
                        .frame(width: width - 20, height: waveformHeight)
                        .position(x: width / 2, y: waveformCentreY)
                    Button { showsAudioDetails = true } label: {
                        Text(audioSummary(song)).font(.system(size: 10.5 * PlayerLayoutMetrics.technicalTextScale, weight: .bold))
                            .foregroundStyle(artworkControls?.accentInk.opacity(0.80) ?? playerInk)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(width: width - 24)
                    .position(x: width / 2, y: bitrateCentreY)
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
        .opacity(router.showsLyrics ? 0 : 1)
        .scaleEffect(router.showsLyrics && !reduceMotion ? 0.985 : 1.0)
        .allowsHitTesting(!router.showsLyrics)
        .accessibilityHidden(router.showsLyrics)
        .animation(
            reduceMotion
                ? .linear(duration: 0.14)
                : (router.showsLyrics
                    ? .easeOut(duration: 0.22)
                    : .easeOut(duration: 0.30).delay(0.14)),
            value: router.showsLyrics
        )
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

    private func openLyrics() {
        withAnimation(reduceMotion ? .linear(duration: 0.14) : .easeInOut(duration: 0.34)) {
            router.showsLyrics = true
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = actions.message {
            LibraryActionToast(text: message, id: actions.messageID)
                .padding(.bottom, AppNavigationMetrics.effectiveBottomInset(navigationBottomInset) + AppNavigationMetrics.bottomPadding + AppNavigationMetrics.buttonsHeight + LibraryToastMetrics.navigationGap)
        }
    }

    private func menu(width: CGFloat) -> some View {
        let current = player.state.currentSong
        let song = current.flatMap { c in library.songs.first(where: { $0.id == c.id }) ?? c }
        let pinned = Set(settings.nowPlayingButtons)
        let showQueue = !pinned.contains(.queue)
        let showLyrics = !pinned.contains(.lyrics)
        let showAddToPlaylist = !pinned.contains(.addToPlaylist)
        let canOpenArtist = song.map { $0.artistId != 0 && library.artist($0.artistId) != nil } ?? false
        let canOpenAlbum = song.map { $0.albumId != 0 && library.album($0.albumId) != nil } ?? false
        let showGoToArtist = canOpenArtist && !pinned.contains(.goToArtist)
        let showGoToAlbum = canOpenAlbum && !pinned.contains(.goToAlbum)
        let showBookmarks = !pinned.contains(.bookmarks)
        let showVisualizer = !pinned.contains(.visualizer)
        let showMusicInfo = !pinned.contains(.musicInfo)
        return Menu {
            if showQueue || showLyrics {
                Section {
                    if showQueue {
                        Button { showsQueue = true } label: { Label(L("Queue"), systemImage: "list.bullet") }
                    }
                    if showLyrics {
                        Button { openLyrics() } label: { Label(L("Lyrics"), systemImage: "quote.bubble") }
                    }
                }
            }
            if showAddToPlaylist || showGoToArtist || showGoToAlbum {
                Section {
                    if showAddToPlaylist {
                        Button { if let song { router.songsForPlaylist = [song] } } label: { Label(L("Add to playlist"), systemImage: "music.note.list") }
                    }
                    if showGoToArtist, let song {
                        Button {
                            close()
                            router.select(.library)
                            router.open(.artist(song.artistId))
                        } label: {
                            Text(L("Go to artist"))
                            if !song.artist.isBlank { Text(song.artist) }
                            Image(systemName: "person")
                        }
                    }
                    if showGoToAlbum, let song {
                        Button {
                            close()
                            router.select(.library)
                            router.open(.album(song.albumId))
                        } label: {
                            Text(L("Go to album"))
                            if !song.album.isBlank { Text(song.album) }
                            Image(systemName: "square.stack")
                        }
                    }
                }
            }
            if showBookmarks || showVisualizer || showMusicInfo {
                Section {
                    if showBookmarks {
                        Button { showsMarks = true } label: {
                            Label(player.state.abLoop?.enabled == true ? L("Bookmarks & A–B loop (on)") : L("Bookmarks & A–B loop"), systemImage: "bookmark.square")
                        }
                    }
                    if showVisualizer {
                        Button { showsVisualizer = true } label: { Label(L("Visualizer"), systemImage: "waveform") }
                    }
                    if showMusicInfo {
                        Button { router.songForDetails = song } label: { Label(L("Music information"), systemImage: "info.circle") }
                    }
                }
            }
            if let song {
                Section {
                    Button(role: .destructive) { actions.songPendingDeletion = song } label: {
                        Label(L("Delete from device"), systemImage: "trash")
                    }
                }
            }
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
        let buttons = settings.nowPlayingButtons
        return ZStack {
            ForEach(0..<NowPlayingActionButton.slotCount, id: \.self) { index in
                secondaryActionButton(buttons[index], song: song, state: state, width: width)
                    .position(x: width * PlayerLayoutMetrics.secondaryCentresW[index], y: 24)
            }
        }
    }

    @ViewBuilder
    private func secondaryActionButton(_ kind: NowPlayingActionButton, song: Song, state: PlaybackState, width: CGFloat) -> some View {
        let iconWidth = width * PlayerLayoutMetrics.secondaryIconW
        switch kind {
        case .favorite:
            PlayerFavoriteButton(songID: song.id, isFavorite: song.isFavorite, iconWidth: width * PlayerLayoutMetrics.heartIconW, ink: playerInk, reduceMotion: reduceMotion) {
                actions.toggleFavorite(song)
            }
        case .share:
            PlayerShareButton(song: song, iconWidth: iconWidth)
        case .more:
            menu(width: width)
        case .shuffle:
            ToggleIcon(systemImage: "shuffle", active: state.shuffleModeEnabled, iconWidth: iconWidth) {
                player.setShuffleModeEnabled(!state.shuffleModeEnabled)
            }
            .accessibilityLabel("Shuffle")
        case .repeatMode:
            ToggleIcon(systemImage: state.repeatMode == .one ? "repeat.1" : "repeat", active: state.repeatMode != .off, iconWidth: iconWidth) {
                player.cycleRepeatMode()
            }
            .accessibilityLabel("Repeat")
        case .lyrics:
            ToggleIcon(systemImage: "quote.bubble", active: router.showsLyrics, iconWidth: iconWidth) {
                openLyrics()
            }
            .accessibilityLabel(L("Lyrics"))
        case .queue:
            ToggleIcon(systemImage: "list.bullet", active: showsQueue, iconWidth: iconWidth) {
                showsQueue = true
            }
            .accessibilityLabel(L("Queue"))
        case .addToPlaylist:
            ToggleIcon(systemImage: "music.note.list", active: false, iconWidth: iconWidth) {
                router.songsForPlaylist = [song]
            }
            .accessibilityLabel(L("Add to playlist"))
        case .visualizer:
            ToggleIcon(systemImage: "waveform", active: showsVisualizer, iconWidth: iconWidth) {
                showsVisualizer = true
            }
            .accessibilityLabel(L("Visualizer"))
        case .bookmarks:
            ToggleIcon(systemImage: "bookmark.square", active: state.abLoop?.enabled == true, iconWidth: iconWidth) {
                showsMarks = true
            }
            .accessibilityLabel(L("Bookmarks & A–B loop"))
        case .musicInfo:
            ToggleIcon(systemImage: "info.circle", active: false, iconWidth: iconWidth) {
                router.songForDetails = song
            }
            .accessibilityLabel(L("Music information"))
        case .goToAlbum:
            ToggleIcon(systemImage: "square.stack", active: false, iconWidth: iconWidth) {
                guard song.albumId != 0, library.album(song.albumId) != nil else { return }
                close()
                router.select(.library)
                router.open(.album(song.albumId))
            }
            .disabled(song.albumId == 0 || library.album(song.albumId) == nil)
            .opacity(song.albumId != 0 && library.album(song.albumId) != nil ? 1 : 0.4)
            .accessibilityLabel(L("Go to album"))
        case .goToArtist:
            ToggleIcon(systemImage: "person", active: false, iconWidth: iconWidth) {
                guard song.artistId != 0, library.artist(song.artistId) != nil else { return }
                close()
                router.select(.library)
                router.open(.artist(song.artistId))
            }
            .disabled(song.artistId == 0 || library.artist(song.artistId) == nil)
            .opacity(song.artistId != 0 && library.artist(song.artistId) != nil ? 1 : 0.4)
            .accessibilityLabel(L("Go to artist"))
        case .audioOutput:
            AirPlayRouteButton(tint: playerInk.opacity(PlayerLayoutMetrics.idleOpacity), activeTint: playerInk, iconWidth: iconWidth)
                .frame(width: 48, height: 48)
                .accessibilityLabel(L("Audio output"))
        case .eqToggle:
            ToggleIcon(systemImage: "slider.vertical.3", active: sound.settings.isEqEnabled, iconWidth: iconWidth) {
                sound.setEqEnabled(!sound.settings.isEqEnabled)
            }
            .accessibilityLabel(L("Equalizer"))
        case .sleepTimer:
            sleepTimerMenu(iconWidth: iconWidth)
        }
    }

    private func sleepTimerMenu(iconWidth: CGFloat) -> some View {
        let active = player.sleepTimerActive
        return Menu {
            if player.sleepTimerEndOfTrack {
                Text(L("Active: End of track"))
            } else if let deadline = player.sleepTimerDeadline {
                let remaining = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
                Text(L("Active: %d min left", remaining))
            }
            Button(L("15 minutes")) { player.setSleepTimer(minutes: 15) }
            Button(L("30 minutes")) { player.setSleepTimer(minutes: 30) }
            Button(L("45 minutes")) { player.setSleepTimer(minutes: 45) }
            Button(L("60 minutes")) { player.setSleepTimer(minutes: 60) }
            Button(L("End of track")) { player.setSleepTimerEndOfTrack() }
            if active {
                Divider()
                Button(L("Turn off timer"), role: .destructive) { player.cancelSleepTimer() }
            }
        } label: {
            Image(systemName: active ? "moon.zzz.fill" : "moon.zzz")
                .resizable().scaledToFit()
                .frame(width: iconWidth, height: iconWidth)
                .foregroundStyle(playerInk.opacity(active ? 1 : PlayerLayoutMetrics.idleOpacity))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .accessibilityLabel(L("Sleep timer"))
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

/// Now Playing favorite star button delegating to the shared Apple Music 120 Hz star choreography.
private struct PlayerFavoriteButton: View {
    let songID: Int64
    let isFavorite: Bool
    let iconWidth: CGFloat
    let ink: Color
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        AppleMusicFavoriteButton(
            itemID: songID,
            isFavorite: isFavorite,
            iconSize: iconWidth,
            hitSize: 44,
            ink: ink,
            reduceMotion: reduceMotion,
            action: action
        )
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

/// Full-screen editorial lyrics view: full-bleed top artwork smoothly dissolving into a luminous
/// cover-tinted backdrop, compact Title/Artist + Pause seam row, and large focused line-by-line lyrics.
/// Presented in-place over Now Playing with a symmetric two-phase album-color melt so both covers
/// never ghost over each other.
struct ExpandedLyrics: View {
    let previous: () -> Void
    let next: () -> Void
    let onDismiss: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var artworkPalette = ArtworkPaletteState()
    @State private var contentAppeared = false
    @State private var isDismissing = false
    @State private var dragOffset: CGFloat = 0

    private func dismissAnimated() {
        guard !isDismissing else { return }
        isDismissing = true
        if reduceMotion {
            onDismiss()
            return
        }
        withAnimation(.easeIn(duration: 0.20)) {
            contentAppeared = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            onDismiss()
        }
    }

    var body: some View {
        let state = player.state
        let sampled = artworkPalette.palette(for: state.currentSong?.url).forScheme(.dark)
        let colors = LyricsColors(sampled)
        let dismissProgress = min(max(dragOffset / 240.0, 0.0), 1.0)
        let contentOpacity = (contentAppeared ? 1.0 : 0.0) * max(0.0, 1.0 - dismissProgress * 1.35)
        let backdropOpacity = max(0.0, 1.0 - max(0.0, dismissProgress - 0.14) * 1.05)
        GeometryReader { geo in
            let width = geo.size.width
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            let totalHeight = geo.size.height + topInset + bottomInset
            let heroTotalHeight = totalHeight * 0.58
            let seamSpacerHeight = max(totalHeight * 0.48 - topInset, 120)

            ZStack(alignment: .top) {
                // Phase 1 bridge: luminous cover-tinted color canvas that melts Now Playing into Lyrics
                // smoothly in the album's dominant hue before the Lyrics hero blooms into view.
                ZStack {
                    Color(argb: sampled.artworkDominant)
                    LinearGradient(colors: colors.gradient, startPoint: .top, endPoint: .bottom)
                        .opacity(0.92)
                    if let song = state.currentSong {
                        SongArtworkView(url: song.url, maxPixels: 320)
                            .frame(width: width, height: totalHeight)
                            .scaleEffect(1.38)
                            .saturation(1.18)
                            .blur(radius: 48)
                            .opacity(0.92)
                            .frame(width: width, height: totalHeight)
                            .clipped()
                    }
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.06), location: 0.00),
                            .init(color: Color.black.opacity(0.18), location: 0.50),
                            .init(color: Color.black.opacity(0.28), location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: width, height: totalHeight)
                .clipped()
                .opacity(backdropOpacity)
                .ignoresSafeArea()

                // Phase 2: Full-bleed dissolving hero artwork emerging cleanly out of the album-color bridge.
                if let song = state.currentSong {
                    ZStack {
                        // Soft feathered transition bridge behind the dissolve band.
                        SongArtworkView(url: song.url, maxPixels: 600)
                            .frame(width: width, height: heroTotalHeight)
                            .clipped()
                            .blur(radius: 18)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.45),
                                        .init(color: .white.opacity(0.85), location: 0.72),
                                        .init(color: .clear, location: 1.00),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        // Sharp top artwork dissolving smoothly downward.
                        SongArtworkView(url: song.url, maxPixels: 1200)
                            .frame(width: width, height: heroTotalHeight)
                            .clipped()
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.00),
                                        .init(color: .white, location: 0.55),
                                        .init(color: .white.opacity(0.82), location: 0.67),
                                        .init(color: .white.opacity(0.42), location: 0.79),
                                        .init(color: .white.opacity(0.12), location: 0.90),
                                        .init(color: .clear, location: 1.00),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .frame(width: width, height: heroTotalHeight)
                    .clipped()
                    .opacity(contentOpacity)
                    .ignoresSafeArea(edges: .top)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 14)
                            .onChanged { value in
                                let dy = value.translation.height
                                let dx = value.translation.width
                                if dy > 0 && dy > abs(dx) {
                                    dragOffset = dy
                                }
                            }
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                if abs(dx) > abs(dy) && abs(dx) > 48 {
                                    withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                                    if dx < 0 { next() } else { previous() }
                                } else if dy > 65 || value.predictedEndTranslation.height > 180 {
                                    dismissAnimated()
                                } else {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }

                // Foreground vertical layout strictly locked to viewport width:
                // transparent hero zone -> seam header (Title/Artist menu + Pause) -> synced lyrics.
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: seamSpacerHeight)
                        .allowsHitTesting(false)

                    HStack(alignment: .center, spacing: 12) {
                        if let song = state.currentSong {
                            LyricsOptionsMenu(song: song, onClose: dismissAnimated) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.28), radius: 6, y: 1)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(Color.white.opacity(0.76))
                                        .shadow(color: .black.opacity(0.24), radius: 4, y: 1)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                        } else {
                            Spacer()
                        }

                        Button { player.togglePlayPause() } label: {
                            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.28), radius: 6, y: 1)
                                .frame(width: 44, height: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
                    }
                    .padding(.horizontal, 26)
                    .frame(width: width)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 14)
                            .onChanged { value in
                                if value.translation.height > 0 && value.translation.height > abs(value.translation.width) {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 55 || value.predictedEndTranslation.height > 160 {
                                    dismissAnimated()
                                } else {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )

                    if let song = state.currentSong {
                        LyricsPanel(song: song, immersive: true)
                            .frame(width: width)
                            .frame(maxHeight: .infinity)
                    } else {
                        Spacer()
                    }
                }
                .frame(width: width, height: geo.size.height, alignment: .top)
                .offset(y: (contentAppeared || reduceMotion ? 0 : 12) + dragOffset * 0.18)
                .opacity(contentOpacity)
            }
            .frame(width: width, height: geo.size.height, alignment: .top)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if reduceMotion {
                contentAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.34).delay(0.14)) {
                    contentAppeared = true
                }
            }
        }
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

/// Native iOS audio output / AirPlay route picker styled to match Now Playing's secondary icons.
private struct AirPlayRouteButton: UIViewRepresentable {
    let tint: Color
    let activeTint: Color
    let iconWidth: CGFloat

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.backgroundColor = .clear
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor(tint)
        picker.activeTintColor = UIColor(activeTint)
        return picker
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(activeTint)
    }
}
