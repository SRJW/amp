import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

/// Drives playback (Android's PlaybackControllerImpl + MusicPlaybackService). [state] is what every
/// screen reads; the queue lives here, the audio in [AudioEngine]. Lock screen, Control Center and
/// headphone commands act on the same state.
@MainActor
@Observable
final class PlayerController {
    private(set) var state = PlaybackState() {
        didSet {
            let id = state.currentSong?.id
            if currentSongID != id { currentSongID = id }
        }
    }
    /// Isolated current song identity so song lists only invalidate when the playing track actually changes.
    private(set) var currentSongID: Int64?
    private(set) var artworkDirection = 1
    /// The playing position, published on its own: it changes four times a second, and only the
    /// views showing progress should redraw for it (a menu open elsewhere would otherwise reset).
    let clock = PlaybackClock()

    @ObservationIgnored let engine = AudioEngine()
    @ObservationIgnored private let database: LibraryDatabase
    @ObservationIgnored let transitions: TransitionSettingsStore
    @ObservationIgnored private let persistence = JSONStore<PersistedPlaybackState>(name: "playback.json", debounce: .milliseconds(250))
    @ObservationIgnored private var removals = QueueRemovals<QueueEntry>()
    @ObservationIgnored private lazy var history = SessionHistory(now: { Int64(Date().timeIntervalSince1970 * 1000) })
    @ObservationIgnored private lazy var listening = ListeningTracker(
        elapsedRealtime: { Int64(ProcessInfo.processInfo.systemUptime * 1000) },
        onPlayCounted: { [weak self] id in self?.recordPlay(id) },
        onListened: { [weak self] id, ms in self?.recordListened(id, ms) }
    )
    @ObservationIgnored private lazy var abLoop = AbLoopController(
        scheduler: { [weak self] _, position, onReached in self?.scheduleLoop(at: position, onReached) ?? Cancellable {} },
        player: loopPlayer,
        onStateChanged: { [weak self] loop in
            self?.state.abLoop = loop
            self?.reevaluateTransition()
        }
    )
    @ObservationIgnored private lazy var loopPlayer = ControllerLoopPlayer(controller: self)
    @ObservationIgnored private var loopTarget: (positionMs: Int64, onReached: () -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var displayTimeline = PlaybackDisplayTimeline()
    @ObservationIgnored private var ticks = 0
    enum VisualMotion: Hashable { case carousel, presentation }
    @ObservationIgnored private var visualMotion: Set<VisualMotion> = []
    @ObservationIgnored private var nowPlayingUpdate: Task<Void, Never>?
    @ObservationIgnored private let albumHistoryQueue = DispatchQueue(label: "amp.album-history", qos: .utility)
    @ObservationIgnored private var artworkWarmup: Task<Void, Never>?
    @ObservationIgnored private var fileWarmup: Task<Void, Never>?
    @ObservationIgnored private var audioPreparation: Task<Void, Never>?
    @ObservationIgnored private var engineSetup: Task<Void, Never>?
    @ObservationIgnored private var preparingPlayIntent = false
    private(set) var playbackError: String?
    private(set) var restoreFinished = false
    private(set) var sleepTimerDeadline: Date?
    private(set) var sleepTimerEndOfTrack = false
    private(set) var sleepTimerPlayLastSongToEnd = true
    private(set) var sleepTimerConfiguredMinutes = 30
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    var sleepTimerActive: Bool { sleepTimerEndOfTrack || sleepTimerDeadline != nil }
    @ObservationIgnored private var consecutiveErrors = 0
    @ObservationIgnored private var plannedTransition: (entryId: UUID, nextEntryId: UUID, plan: Planned)?
    @ObservationIgnored private var pendingTransitionCommit: Task<Void, Never>?
    @ObservationIgnored private var smartBlendAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var plannedSmartBlendTempoMatched = false
    @ObservationIgnored private var activeSmartBlendEndUptime: TimeInterval?
    @ObservationIgnored private var activeSmartBlendMeta: (tempoMatched: Bool, durationMs: Int, outgoingCutMs: Int, incomingStartMs: Int)?
    private(set) var smartBlendStatus: SmartBlendStatus?
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var headphonePolicy = HeadphoneRoutePolicy()
    @ObservationIgnored private let settings: AppSettings?
    @ObservationIgnored var continuousContinuation: ((_ current: Song, _ existingIds: Set<Int64>, _ shuffled: Bool) -> [Song])?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var artworkSongId: Int64?

    func setSleepTimer(minutes: Int, playLastSongToEnd: Bool = false) {
        cancelSleepTimer()
        sleepTimerPlayLastSongToEnd = playLastSongToEnd
        guard minutes > 0 else {
            if playLastSongToEnd {
                sleepTimerEndOfTrack = true
            }
            return
        }
        sleepTimerConfiguredMinutes = minutes
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerDeadline = deadline
        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.triggerSleepTimer()
        }
    }

    func setSleepTimerEndOfTrack() {
        cancelSleepTimer()
        sleepTimerPlayLastSongToEnd = true
        sleepTimerEndOfTrack = true
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerDeadline = nil
        sleepTimerEndOfTrack = false
    }

    private func triggerSleepTimer() {
        let finishCurrentTrack = sleepTimerPlayLastSongToEnd && intendsToPlay && state.currentSong != nil
        sleepTimerTask = nil
        sleepTimerDeadline = nil
        if finishCurrentTrack {
            sleepTimerEndOfTrack = true
        } else {
            sleepTimerEndOfTrack = false
            if intendsToPlay { pause() }
        }
    }

    /// Media3's "previous restarts the song after 3 s".
    private static let restartThreshold: Int64 = 3_000
    private static let tickInterval: TimeInterval = 0.05
    /// Ticks between published positions (250 ms, Android's poll).
    private static let publishEvery = 5
    private static let persistEvery = 100
    private static let checkpointEvery = 1_200
    /// A transition is armed this far ahead of its start (the engine then starts it sample-exactly).
    private static let transitionLeadMs: Int64 = 400
    /// The next track is queued gaplessly once this little of the current one remains.
    private static let gaplessLeadMs: Int64 = 8_000

    init(database: LibraryDatabase, transitions: TransitionSettingsStore, settings: AppSettings? = nil) {
        self.database = database
        self.transitions = transitions
        self.settings = settings
        if settings?.bitPerfectMode == true {
            engine.setBitPerfect(true)
        }
        transitions.onChange = { [weak self] in self?.reevaluateTransition() }
        engine.onEntryFinished = { [weak self] id in self?.entryFinished(id) }
        engine.onConfigurationChange = { [weak self] in self?.restartAfterConfigurationChange() }
        configureAudioSession()
        configureRemoteCommands()
        observeAudioSession()
        Task {
            // Restoring the queue and browsing the library do not need an audio output device.
            restorePersistedState()
        }
    }

    func setBitPerfect(_ enabled: Bool) {
        let wasPlaying = state.isPlaying
        let position = currentPositionMs()
        cancelPendingTransitionCommit()
        plannedTransition = nil
        engine.setBitPerfect(enabled)
        if state.currentSong != nil && engine.isReady {
            let clamped = state.durationMs > 0 ? min(position, state.durationMs) : position
            startCurrent(at: clamped, playing: wasPlaying, sameEntryRepeated: true)
        } else {
            reevaluateTransition()
        }
    }

    // MARK: Transport

    private var intendsToPlay: Bool {
        state.isPlaying || (state.status == .buffering && preparingPlayIntent)
    }

    private func cancelPendingTransitionCommit() {
        pendingTransitionCommit?.cancel()
        pendingTransitionCommit = nil
    }

    private func clearActiveSmartBlendMix() {
        activeSmartBlendEndUptime = nil
        activeSmartBlendMeta = nil
        updateSmartBlendStatus(position: currentPositionMs())
    }

    func play() {
        guard !state.queue.isEmpty else { return }
        headphonePolicy.userDidPlay()
        if state.status == .idle || engine.currentPosition()?.entryId != state.currentEntry?.id {
            startCurrent(at: state.positionMs, playing: true)
            return
        }
        activateAudioSession()
        do {
            try engine.resume()
            playingChanged(true)
        } catch {
            startCurrent(at: state.positionMs, playing: true)
        }
    }

    func pause() {
        headphonePolicy.userDidPause()
        pauseInternal()
    }

    private func pauseInternal() {
        cancelPendingTransitionCommit()
        clearActiveSmartBlendMix()
        audioPreparation?.cancel(); audioPreparation = nil; preparingPlayIntent = false
        refreshPosition()
        engine.pause()
        playingChanged(false)
    }

    func togglePlayPause() {
        if intendsToPlay { pause() }
        else { play() }
    }

    /// Plays [songs] from [startIndex] as an ordinary queue.
    func playSongs(_ songs: [Song], startIndex: Int = 0) {
        playCollection(songs, startIndex: startIndex, origin: nil)
    }

    /// Plays [songs] as album or playlist [origin] (its transition settings apply); [slots] are the
    /// playlist positions (parallel), so duplicates stay distinct.
    func playCollection(_ songs: [Song], startIndex: Int, origin: CollectionRef?, slots: [Int]? = nil, source: PlaybackSource? = nil) {
        guard !songs.isEmpty else { return }
        headphonePolicy.userDidPlay()
        let index = songs.indices.contains(startIndex) ? startIndex : 0
        consecutiveErrors = 0
        var order = Array(songs.indices)
        var playIndex = index
        if state.shuffleModeEnabled && songs.count > 1 {
            order = [index] + songs.indices.filter { $0 != index }.shuffled()
            playIndex = 0
        }
        let entries = order.map { i in
            QueueEntry(song: songs[i], origin: origin.map {
                QueueOrigin(collection: $0, occurrence: TrackOccurrence(songs[i].id, slots.flatMap { $0.indices.contains(i) ? $0[i] : nil }))
            }, source: source)
        }
        artworkDirection = 1
        setQueue(entries, startIndex: playIndex)
        if case .playlist(let id)? = origin.map({ CollectionKindRef($0) }) { try? database.markPlaylistPlayed(id) }
        startCurrent(at: 0, playing: true)
    }

    func seek(to positionMs: Int64) {
        guard let entry = state.currentEntry else { return }
        cancelPendingTransitionCommit()
        let target = max(positionMs, 0)
        if state.status == .buffering { startCurrent(at: target, playing: preparingPlayIntent); return }
        if !engine.isReady {
            setPosition(target)
            updateNowPlaying()
            persistState()
            return
        }
        if DecodedAudioSource.requiresDecoder(entry.song.url), !DecodedAudioSource.isPrepared(entry.song.url) {
            startCurrent(at: target, playing: state.isPlaying)
            return
        }
        do {
            try engine.seek(entryId: entry.id, url: entry.song.url, toMs: target)
        } catch {
            handleError(entry)
            return
        }
        setPosition(target)
        reevaluateTransition()
        updateNowPlaying()
    }

    func skipNext() {
        guard let next = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true)
        else { return }
        moveTo(next, playing: intendsToPlay, sameEntryRepeated: false)
    }

    /// Restarts the current song past the first few seconds, otherwise moves to the previous one.
    func skipPrevious() {
        if currentPositionMs() > Self.restartThreshold || state.previousIndex < 0 {
            seek(to: 0)
        } else {
            skipToPreviousItem()
        }
    }

    /// The previous song in play order, never a restart of the current one.
    func skipToPreviousItem() {
        guard let previous = PlayOrder.previous(before: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode)
        else { return }
        moveTo(previous, playing: intendsToPlay, sameEntryRepeated: false, direction: -1)
    }

    func skipToQueueItem(_ index: Int) {
        guard state.queue.indices.contains(index) else { return }
        moveTo(index, playing: true, sameEntryRepeated: false, direction: index < state.currentIndex ? -1 : 1)
    }

    /// Shuffle is physical: turning it on puts the current entry first and shuffles the rest; turning
    /// it off keeps the order (as on Android).
    func setShuffleModeEnabled(_ enabled: Bool) {
        state.shuffleModeEnabled = enabled
        if enabled, state.queue.count > 1, let current = state.currentEntry {
            removals.clear()
            let rest = state.queue.enumerated().filter { $0.offset != state.currentIndex }.map(\.element).shuffled()
            state.queue = [current] + rest
            state.currentIndex = 0
            queueChanged()
        }
        persistState()
    }

    func setRepeatMode(_ mode: RepeatMode) {
        state.repeatMode = mode
        queueChanged()
        persistState()
    }

    func cycleRepeatMode() {
        setRepeatMode(state.repeatMode.next)
    }

    func setVolume(_ volume: Float) {
        engine.volume = volume
    }

    // MARK: Queue edits

    func playNext(_ song: Song, source: PlaybackSource? = nil) {
        let wasEmpty = state.queue.isEmpty
        let insertAt = wasEmpty ? 0 : min(state.currentIndex + 1, state.queue.count)
        state.queue.insert(QueueEntry(song: song, source: source), at: insertAt)
        if wasEmpty { state.currentIndex = 0 }
        queueChanged()
    }

    func addToQueue(_ song: Song, source: PlaybackSource? = nil) {
        let wasEmpty = state.queue.isEmpty
        state.queue.append(QueueEntry(song: song, source: source))
        if wasEmpty { state.currentIndex = 0 }
        queueChanged()
    }

    /// Removes the entry at [index]; [undoQueueRemoval] puts it back.
    func removeFromQueue(_ index: Int) {
        guard state.queue.indices.contains(index) else { return }
        let removingCurrent = index == state.currentIndex
        let shouldPlay = intendsToPlay
        let entry = state.queue.remove(at: index)
        removals.push(index: index, item: entry)
        if state.queue.isEmpty {
            cancelPendingTransitionCommit()
            state.currentIndex = -1
            engine.stopAll()
            playingChanged(false)
            currentEntryChanged(sameEntryRepeated: false)
        } else if removingCurrent {
            state.currentIndex = min(index, state.queue.count - 1)
            startCurrent(at: 0, playing: shouldPlay)
        } else if index < state.currentIndex {
            state.currentIndex -= 1
        }
        queueChanged()
    }

    /// Permanent deletion removes every occurrence and cannot be undone into a missing file.
    func removeDeletedSong(_ songID: Int64) { removeDeletedSongs([songID]) }

    func removeDeletedSongs(_ songIDs: Set<Int64>) {
        guard !songIDs.isEmpty else { return }
        let oldQueue = state.queue
        let plan = QueueDeletionPlan(songIDs: oldQueue.map { $0.song.id }, currentIndex: state.currentIndex, deletedIDs: songIDs)
        let playing = state.isPlaying || (state.status == .buffering && preparingPlayIntent)
        removals.clear()
        state.queue = plan.retainedIndices.map { oldQueue[$0] }
        state.currentIndex = plan.currentIndex
        if state.queue.isEmpty {
            audioPreparation?.cancel(); audioPreparation = nil; preparingPlayIntent = false
            engine.stopAll()
            playingChanged(false)
            currentEntryChanged(sameEntryRepeated: false)
        } else if plan.currentWasDeleted {
            // All deleted entries are gone before starting a replacement; never open
            // another file from the same confirmed deletion batch.
            startCurrent(at: 0, playing: playing)
        } else if let current = state.currentEntry, plan.retainedIndices.count != oldQueue.count {
            engine.dropQueuedAfterCurrent(currentEntry: current.id)
        }
        queueChanged()
    }

    /// Puts the most recently removed entry back at its original position. False when there is nothing to undo.
    @discardableResult
    func undoQueueRemoval() -> Bool {
        guard let removal = removals.pop() else { return false }
        let wasEmpty = state.queue.isEmpty
        let index = removal.index.clamped(0, state.queue.count)
        state.queue.insert(removal.item, at: index)
        if wasEmpty {
            state.currentIndex = 0
        } else if index <= state.currentIndex {
            state.currentIndex += 1
        }
        queueChanged()
        return true
    }

    /// Shuffles only the entries after the current one. False when fewer than two are upcoming.
    @discardableResult
    func shuffleUpcoming() -> Bool {
        guard let upcoming = shuffledUpcoming(state.queue, currentIndex: state.currentIndex) else { return false }
        let start = upcomingStart(queueSize: state.queue.count, currentIndex: state.currentIndex)
        state.queue.replaceSubrange(start..., with: upcoming)
        queueChanged()
        return true
    }

    /// Replaces the entries after the current one with [songs] (Smart Radio); the current song keeps playing.
    func replaceUpcoming(_ songs: [Song]) {
        removals.clear()
        let entries = songs.map { QueueEntry(song: $0) }
        if state.queue.isEmpty {
            setQueue(entries, startIndex: 0)
            return
        }
        let start = upcomingStart(queueSize: state.queue.count, currentIndex: state.currentIndex)
        state.queue.replaceSubrange(start..., with: entries)
        queueChanged()
    }

    /// Plays a session-history entry again, right after the current entry.
    func playFromHistory(_ entryId: Int64) {
        guard let song = history.find(entryId)?.song else { return }
        if state.queue.isEmpty {
            playSongs([song])
        } else {
            let target = min(state.currentIndex + 1, state.queue.count)
            state.queue.insert(QueueEntry(song: song), at: target)
            queueChanged()
            skipToQueueItem(target)
        }
    }

    func reorder(from: Int, to: Int) {
        guard state.queue.indices.contains(from), state.queue.indices.contains(to), from != to else { return }
        let current = state.currentEntry?.id
        let entry = state.queue.remove(at: from)
        state.queue.insert(entry, at: to)
        if let current { state.currentIndex = state.queue.firstIndex { $0.id == current } ?? state.currentIndex }
        queueChanged()
    }

    // MARK: A–B loop

    func setLoopStart() -> AbLoopEdit { abLoop.setStart() }
    func setLoopEnd() -> AbLoopEdit { abLoop.setEnd() }
    func setLoopEnabled(_ enabled: Bool) -> AbLoopEdit { abLoop.setEnabled(enabled) }
    func clearLoop() { abLoop.clear() }

    /// The engine's exact position right now, finer than [state]'s published one.
    func currentPositionMs() -> Int64 {
        guard let entryId = state.currentEntry?.id else { return state.positionMs }
        if let position = engine.currentPosition(), position.entryId == entryId {
            return position.positionMs
        }
        if let crossfadePosition = engine.position(forEntry: entryId) {
            return crossfadePosition
        }
        return state.positionMs
    }

    func displayPositionMs(smoothed: Bool = true) -> Int64 {
        guard let entry = state.currentEntry else { displayTimeline.reset(); return 0 }
        let sampled = engine.displayPosition()
        let position: Int64
        if let sampled, sampled.entryId == entry.id { position = sampled.positionMs }
        else { position = currentPositionMs() }
        guard smoothed else { return position }
        return displayTimeline.position(audioMs: position, entry: entry.id,
            uptime: ProcessInfo.processInfo.systemUptime, durationMs: state.durationMs, playing: state.isPlaying)
    }

    private func scheduleLoop(at positionMs: Int64, _ onReached: @escaping () -> Void) -> Cancellable {
        loopTarget = (positionMs, onReached)
        return Cancellable { [weak self] in self?.loopTarget = nil }
    }

    fileprivate func loopSeek(_ positionMs: Int64) {
        seek(to: positionMs)
    }

    // MARK: Internals

    private func setQueue(_ entries: [QueueEntry], startIndex: Int) {
        removals.clear()
        state.queue = entries
        state.currentIndex = entries.isEmpty ? -1 : startIndex.clamped(0, entries.count - 1)
        setPosition(0)
    }

    /// Starts the current entry at [positionMs] from a fresh engine start.
    private func startCurrent(at positionMs: Int64, playing: Bool, sameEntryRepeated: Bool = false) {
        cancelPendingTransitionCommit()
        audioPreparation?.cancel(); audioPreparation = nil
        playbackError = nil
        guard let entry = state.currentEntry else { return }
        preparingPlayIntent = playing
        if !playing && !engine.isReady {
            setPosition(positionMs)
            state.durationMs = entry.song.durationMs
            currentEntryChanged(sameEntryRepeated: sameEntryRepeated)
            playingChanged(false)
            return
        }
        if DecodedAudioSource.requiresDecoder(entry.song.url), !DecodedAudioSource.isPrepared(entry.song.url) {
            // Keep the outgoing song audible until the incoming decoder is ready to blend.
            if !playing { engine.stopAll() }
            listening.onPlayingChanged(false, durationMs: state.durationMs)
            stopTimer()
            state.status = .buffering
            state.durationMs = entry.song.durationMs
            setPosition(positionMs)
            updateNowPlaying()
            audioPreparation = Task {
                let work = Task.detached(priority: .userInitiated) { () -> String? in
                    do { try DecodedAudioSource.prepare(entry.song.url); return nil }
                    catch { return error.localizedDescription }
                }
                let failure = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
                guard !Task.isCancelled, state.currentEntry?.id == entry.id else { return }
                audioPreparation = nil
                if let failure {
                    engine.stopAll()
                    playbackError = failure
                    state.status = .paused
                    updateNowPlaying()
                } else { startCurrent(at: positionMs, playing: playing, sameEntryRepeated: sameEntryRepeated) }
            }
            return
        }
        if playing && (!state.isPlaying || !engine.isRunning) { activateAudioSession() }
        do {
            let wasAlreadyPlaying = state.isPlaying && engine.isRunning
            let handoffSpec = transitions.config.global.manualSpec
            try engine.play(entryId: entry.id, url: entry.song.url, positionMs: positionMs, startPlaying: playing,
                            handoffSpec: handoffSpec)
            if wasAlreadyPlaying, playing, !engine.bitPerfectEnabled, let handoffSpec, handoffSpec.preset == .blend {
                activeSmartBlendEndUptime = ProcessInfo.processInfo.systemUptime + Double(handoffSpec.durationMs) / 1000.0
                activeSmartBlendMeta = (false, handoffSpec.durationMs, 0, 0)
            }
            setPosition(positionMs)
            state.durationMs = entry.song.durationMs
            if playing { consecutiveErrors = 0 }
            currentEntryChanged(sameEntryRepeated: sameEntryRepeated)
            playingChanged(playing)
            updateSmartBlendStatus(position: positionMs)
        } catch AudioEngine.EngineError.notReady {
            // One shared setup survives a cancelled/changed play request; only the latest
            // request may start audio once it is ready. No second tap is needed.
            state.status = .buffering
            state.durationMs = entry.song.durationMs
            setPosition(positionMs)
            updateNowPlaying()
            if engineSetup == nil {
                let engine = engine
                engineSetup = Task { await engine.setUp() }
            }
            let setup = engineSetup
            audioPreparation = Task {
                await setup?.value
                guard !Task.isCancelled, state.currentEntry?.id == entry.id else { return }
                audioPreparation = nil
                startCurrent(at: positionMs, playing: playing, sameEntryRepeated: sameEntryRepeated)
            }
        } catch {
            handleError(entry)
        }
    }

    private func moveTo(_ index: Int, playing: Bool, sameEntryRepeated: Bool, direction: Int = 1) {
        cancelPendingTransitionCommit()
        artworkDirection = direction
        engine.cancelCrossfade()
        state.currentIndex = index
        startCurrent(at: 0, playing: playing, sameEntryRepeated: sameEntryRepeated)
    }

    /// An entry played to its end on the engine.
    private func entryFinished(_ entryId: UUID) {
        guard entryId == state.currentEntry?.id else { return }
        if sleepTimerEndOfTrack {
            cancelSleepTimer()
            pause()
            return
        }
        if PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: false) == nil,
           settings?.continuousPlayback == true,
           let currentSong = state.currentSong,
           let continuation = continuousContinuation {
            let existing = Set(state.queue.map(\.song.id))
            let upcoming = continuation(currentSong, existing, state.shuffleModeEnabled)
            if !upcoming.isEmpty {
                state.queue.append(contentsOf: upcoming.map { QueueEntry(song: $0, source: .library) })
                queueChanged()
            }
        }
        guard let next = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: false)
        else {
            // End of the queue: back to the start of the last track, paused (Media3's ENDED).
            listening.onEnded()
            engine.stopAll()
            setPosition(0)
            playingChanged(false)
            state.status = .idle
            persistState()
            return
        }
        artworkDirection = 1
        let repeated = next == state.currentIndex
        if !repeated, engine.hasQueued(state.queue[next].id) {
            // Gapless: the engine already plays it.
            state.currentIndex = next
            setPosition(0)
            state.durationMs = state.queue[next].song.durationMs
            currentEntryChanged(sameEntryRepeated: false)
        } else {
            state.currentIndex = next
            startCurrent(at: 0, playing: true, sameEntryRepeated: repeated)
        }
    }

    /// A file that is gone or unreadable must not stall the queue: skip to the next entry, but give
    /// up after one full pass so a queue of broken files cannot loop forever.
    private func handleError(_ entry: QueueEntry) {
        NSLog("amp: cannot play \(entry.song.path)")
        consecutiveErrors += 1
        if consecutiveErrors < state.queue.count,
           let next = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true) {
            artworkDirection = 1
            state.currentIndex = next
            startCurrent(at: 0, playing: true)
        } else {
            consecutiveErrors = 0
            engine.stopAll()
            playingChanged(false)
            state.status = .idle
        }
    }

    private func currentEntryChanged(sameEntryRepeated: Bool) {
        warmAdjacentFiles()
        let song = state.currentSong
        listening.onItemChanged(song?.id, durationMs: song?.durationMs ?? 0, isPlaying: state.isPlaying)
        if history.onItemBecameCurrent(song, isPlaying: state.isPlaying) { state.history = history.entries }
        abLoop.onEntryChanged(sameEntryRepeated: sameEntryRepeated)
        if let song, state.isPlaying { recordAlbumPlayed(song.id) }
        reevaluateTransition()
        updateNowPlaying()
        persistState()
    }

    private func playingChanged(_ playing: Bool) {
        let wasPlaying = state.isPlaying
        state.status = state.queue.isEmpty ? .idle : (playing ? .playing : .paused)
        listening.onPlayingChanged(playing, durationMs: state.durationMs)
        if playing {
            if history.onPlaybackStarted() { state.history = history.entries }
            if !wasPlaying, let song = state.currentSong { recordAlbumPlayed(song.id) }
            startTimer()
        } else {
            stopTimer()
            refreshPosition()
            persistState()
        }
        updateNowPlaying()
    }

    private func queueChanged() {
        cancelPendingTransitionCommit()
        warmAdjacentFiles()
        if state.currentEntry == nil { state.currentIndex = state.queue.isEmpty ? -1 : 0 }
        if let current = state.currentEntry {
            let nextIndex = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: false)
            let expectedNextId = nextIndex.flatMap { state.queue.indices.contains($0) && $0 != state.currentIndex ? state.queue[$0].id : nil }
            if expectedNextId == nil || !engine.hasQueued(expectedNextId!) {
                engine.dropQueuedAfterCurrent(currentEntry: current.id)
            }
        }
        reevaluateTransition()
        persistState()
    }

    private func warmAdjacentFiles() {
        fileWarmup?.cancel()
        let previous = PlayOrder.previous(before: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode)
        let next = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true)
        let nextTwo = next.flatMap { PlayOrder.next(after: $0, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true) }
        let previousTwo = previous.flatMap { PlayOrder.previous(before: $0, count: state.queue.count, repeatMode: state.repeatMode) }
        let urls = [next, previous, nextTwo, previousTwo].compactMap { index -> URL? in
            guard let index, state.queue.indices.contains(index) else { return nil }
            let url = state.queue[index].song.url
            return url == state.currentSong?.url ? nil : url
        }
        DecodedAudioSource.pin(urls + [state.currentSong?.url].compactMap { $0 })
        fileWarmup = Task { [weak self] in await self?.engine.warmFiles(urls) }
        artworkWarmup?.cancel()
        artworkWarmup = Task {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        guard !Task.isCancelled else { return }
                        _ = await ArtworkLoader.shared.image(for: url, maxPixels: 600)
                    }
                }
            }
        }
    }

    // MARK: Position polling

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        ticks += 1
        let position = currentPositionMs()
        if ticks % Self.publishEvery == 0 {
            refreshPosition(publishState: false)
            listening.onProgress(durationMs: state.durationMs)
        }
        if ticks % Self.persistEvery == 0 { persistState() }
        if ticks % Self.checkpointEvery == 0 { listening.checkpoint() }
        if let target = loopTarget, position >= target.positionMs { target.onReached() }
        engine.releaseFinishedOutgoing()
        checkTransition(position: position)
        checkGapless(position: position)
        updateSmartBlendStatus(position: position)
    }

    /// While playing only [clock] moves; [state] keeps the position of the last seek, start or pause.
    private func refreshPosition(publishState: Bool = true) {
        let position = currentPositionMs()
        if clock.positionMs != position { clock.positionMs = position }
        if publishState { setPosition(position) }
        if let duration = state.currentSong?.durationMs, duration > 0, state.durationMs != duration { state.durationMs = duration }
    }

    private func setPosition(_ positionMs: Int64) {
        displayTimeline.reset()
        state.positionMs = positionMs
        clock.positionMs = positionMs
    }

    // MARK: Transitions

    /// Re-plans the boundary after the current entry (entry change, seek, queue edit, repeat, loop, settings).
    private func reevaluateTransition() {
        smartBlendAnalysisTask?.cancel()
        smartBlendAnalysisTask = nil
        plannedSmartBlendTempoMatched = false

        guard !engine.bitPerfectEnabled, let current = state.currentEntry else {
            plannedTransition = nil
            updateSmartBlendStatus(position: currentPositionMs())
            return
        }
        let nextIndex = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: true) ?? -1
        let next = state.queue.indices.contains(nextIndex) ? state.queue[nextIndex] : nil
        let resolved = next.map { transitions.resolve(outgoing: current.origin, incoming: $0.origin) }
        let automaticAllowed = (transitions.config.global.automaticMode ?? .all).allows(shuffled: state.shuffleModeEnabled)
        let rawSpec = resolved.flatMap { automaticAllowed || $0.source != .globalDefault ? $0.spec : nil }
        let immediateSpec = rawSpec.map { SmartBlendAutoMix.smoothedSpec(from: $0) }
        let info = BoundaryInfo(
            spec: immediateSpec, nextIndex: nextIndex, repeatMode: state.repeatMode, abLoopEnabled: state.abLoop?.enabled == true,
            outgoingDurationMs: current.song.durationMs, incomingDurationMs: next?.song.durationMs ?? 0
        )
        if let plan = TransitionPlanner.plan(info).planned, let next {
            plannedTransition = (current.id, next.id, plan)
            if let rawSpec, rawSpec.preset == .blend {
                let currentEntryId = current.id
                let nextEntryId = next.id
                let outgoingSong = current.song
                let incomingSong = next.song
                smartBlendAnalysisTask = Task { @MainActor [weak self] in
                    let analysis = await SmartBlendAutoMixStore.shared.analyze(
                        spec: rawSpec,
                        outgoing: outgoingSong,
                        incoming: incomingSong
                    )
                    guard !Task.isCancelled,
                          let self,
                          !self.engine.bitPerfectEnabled,
                          self.state.currentEntry?.id == currentEntryId,
                          self.plannedTransition?.entryId == currentEntryId,
                          self.plannedTransition?.nextEntryId == nextEntryId
                    else { return }
                    let refinedInfo = BoundaryInfo(
                        spec: analysis.spec,
                        nextIndex: nextIndex,
                        repeatMode: self.state.repeatMode,
                        abLoopEnabled: self.state.abLoop?.enabled == true,
                        outgoingDurationMs: outgoingSong.durationMs,
                        incomingDurationMs: incomingSong.durationMs
                    )
                    guard let refinedPlan = TransitionPlanner.plan(refinedInfo).planned else { return }
                    let nowPos = self.currentPositionMs()
                    self.plannedSmartBlendTempoMatched = analysis.tempoMatched
                    if nowPos < refinedPlan.startAtMs - Self.transitionLeadMs - 100 {
                        self.plannedTransition = (currentEntryId, nextEntryId, refinedPlan)
                    } else if let existing = self.plannedTransition {
                        // Keep the already-approaching startAtMs if the trimmed cut point already passed,
                        // while still applying the incoming auto-cue and smooth DJ curve.
                        var safeSpec = analysis.spec
                        safeSpec.outgoingCutMs = existing.plan.spec.outgoingCutMs
                        safeSpec.durationMs = existing.plan.durationMs
                        let fallbackInfo = BoundaryInfo(
                            spec: safeSpec,
                            nextIndex: nextIndex,
                            repeatMode: self.state.repeatMode,
                            abLoopEnabled: self.state.abLoop?.enabled == true,
                            outgoingDurationMs: outgoingSong.durationMs,
                            incomingDurationMs: incomingSong.durationMs
                        )
                        if let safePlan = TransitionPlanner.plan(fallbackInfo).planned {
                            self.plannedTransition = (currentEntryId, nextEntryId, safePlan)
                        }
                    }
                    self.updateSmartBlendStatus(position: nowPos)
                }
            }
        } else {
            plannedTransition = nil
        }
        updateSmartBlendStatus(position: currentPositionMs())
    }

    private func updateSmartBlendStatus(position: Int64) {
        guard state.isPlaying, !engine.bitPerfectEnabled else {
            if smartBlendStatus != nil { smartBlendStatus = nil }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let endUptime = activeSmartBlendEndUptime, let meta = activeSmartBlendMeta {
            if now < endUptime {
                let status = SmartBlendStatus(
                    phase: .mixing,
                    tempoMatched: meta.tempoMatched,
                    durationMs: meta.durationMs,
                    outgoingCutMs: meta.outgoingCutMs,
                    incomingStartMs: meta.incomingStartMs
                )
                if smartBlendStatus != status { smartBlendStatus = status }
                return
            } else {
                activeSmartBlendEndUptime = nil
                activeSmartBlendMeta = nil
            }
        }
        if let planned = plannedTransition,
           planned.entryId == state.currentEntry?.id,
           planned.plan.spec.preset == .blend {
            let untilStart = planned.plan.startAtMs - position
            if untilStart > 0 && untilStart <= 6_000 {
                let status = SmartBlendStatus(
                    phase: .preparing,
                    tempoMatched: plannedSmartBlendTempoMatched,
                    durationMs: planned.plan.durationMs,
                    outgoingCutMs: planned.plan.spec.outgoingCutMs,
                    incomingStartMs: planned.plan.spec.incomingStartMs
                )
                if smartBlendStatus != status { smartBlendStatus = status }
                return
            }
        }
        if smartBlendStatus != nil { smartBlendStatus = nil }
    }

    private func checkTransition(position: Int64) {
        guard let planned = plannedTransition, planned.entryId == state.currentEntry?.id, state.isPlaying else { return }
        let untilStart = planned.plan.startAtMs - position
        guard untilStart <= Self.transitionLeadMs else { return }
        let wasTempoMatched = plannedSmartBlendTempoMatched
        plannedTransition = nil
        smartBlendAnalysisTask?.cancel()
        smartBlendAnalysisTask = nil
        guard untilStart > 50, state.queue.indices.contains(planned.plan.nextIndex),
              state.queue[planned.plan.nextIndex].id == planned.nextEntryId
        else { return } // too late (e.g. seeked there): the boundary plays normally
        let next = state.queue[planned.plan.nextIndex]
        let startHost = mach_absolute_time() + TransitionStageKernel.hostTicks(forSeconds: Double(untilStart) / 1000)
        do {
            try engine.crossfade(
                to: next.id, url: next.song.url, incomingStartMs: planned.plan.incomingStartMs, spec: planned.plan.spec,
                durationMs: planned.plan.durationMs, startHostTime: startHost
            )
        } catch {
            return
        }
        if planned.plan.spec.preset == .blend {
            let totalSeconds = Double(untilStart + Int64(planned.plan.durationMs)) / 1000.0
            activeSmartBlendEndUptime = ProcessInfo.processInfo.systemUptime + totalSeconds
            activeSmartBlendMeta = (
                wasTempoMatched,
                planned.plan.durationMs,
                planned.plan.spec.outgoingCutMs,
                planned.plan.incomingStartMs
            )
            updateSmartBlendStatus(position: position)
        }
        // The queue moves on when the crossfade starts, as on Android.
        let delay = Double(untilStart) / 1000
        cancelPendingTransitionCommit()
        pendingTransitionCommit = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled,
                  self.state.isPlaying,
                  self.state.queue.indices.contains(planned.plan.nextIndex),
                  self.state.queue[planned.plan.nextIndex].id == next.id else { return }
            self.pendingTransitionCommit = nil
            self.artworkDirection = 1
            self.state.currentIndex = planned.plan.nextIndex
            self.setPosition(planned.plan.incomingStartMs)
            self.state.durationMs = next.song.durationMs
            self.currentEntryChanged(sameEntryRepeated: false)
        }
    }

    private func checkGapless(position: Int64) {
        guard plannedTransition == nil, let current = state.currentEntry,
              current.song.durationMs - position <= Self.gaplessLeadMs,
              let nextIndex = PlayOrder.next(after: state.currentIndex, count: state.queue.count, repeatMode: state.repeatMode, userSkip: false),
              nextIndex != state.currentIndex
        else { return }
        let next = state.queue[nextIndex]
        if !engine.hasQueued(next.id) { engine.queueGapless(entryId: next.id, url: next.song.url) }
    }

    // MARK: Listening statistics

    private func recordPlay(_ songId: Int64) {
        let database = self.database
        Task.detached(priority: .utility) { try? database.recordPlay(songId: songId) }
    }

    private func recordListened(_ songId: Int64, _ ms: Int64) {
        let database = self.database
        Task.detached(priority: .utility) { try? database.addListened(songId: songId, ms: ms) }
    }

    // MARK: Persistence

    private func persistState() {
        guard restoreFinished else { return }
        persistence.save(PersistedPlaybackState(
            queueSongIds: state.queue.map(\.song.id),
            currentIndex: state.currentIndex,
            positionMs: currentPositionMs(),
            shuffleModeEnabled: state.shuffleModeEnabled,
            repeatMode: state.repeatMode,
            queueCollectionKeys: state.queue.map { $0.origin?.key ?? "" }, queueSources: state.queue.map(\.source)
        ))
    }

    /// Saves at once (the app is going to the background).
    func persistNow() {
        guard restoreFinished else { return }
        persistence.saveNow(PersistedPlaybackState(
            queueSongIds: state.queue.map(\.song.id), currentIndex: state.currentIndex, positionMs: currentPositionMs(),
            shuffleModeEnabled: state.shuffleModeEnabled, repeatMode: state.repeatMode,
            queueCollectionKeys: state.queue.map { $0.origin?.key ?? "" }, queueSources: state.queue.map(\.source)
        ))
    }

    private func restorePersistedState() {
        defer { restoreFinished = true }
        guard state.queue.isEmpty, let saved = persistence.load(),
              let restored = buildRestoredQueue(saved, available: (try? database.songs(ids: Array(Set(saved.queueSongIds)))) ?? []),
              state.queue.isEmpty
        else { return }
        let entries = restored.songs.enumerated().map { i, song in
            QueueEntry(song: song, origin: restored.origins.indices.contains(i) ? restored.origins[i] : nil,
                       source: restored.sources.indices.contains(i) ? restored.sources[i] : nil)
        }
        state.queue = entries
        state.currentIndex = restored.startIndex
        setPosition(restored.startPositionMs)
        state.durationMs = state.currentSong?.durationMs ?? 0
        state.shuffleModeEnabled = saved.shuffleModeEnabled
        state.repeatMode = saved.repeatMode
        state.status = .paused
        listening.onItemChanged(state.currentSong?.id, durationMs: state.durationMs, isPlaying: false)
        history.onItemBecameCurrent(state.currentSong, isPlaying: false)
        reevaluateTransition()
        updateNowPlaying()
    }

    private func restartAfterConfigurationChange() {
        guard state.currentEntry != nil else { return }
        let wasPlaying = state.isPlaying
        let engineMs = currentPositionMs()
        let preservedMs = (engineMs == 0 && clock.positionMs > 0) ? clock.positionMs : max(engineMs, clock.positionMs)
        let clampedMs = state.durationMs > 0 ? min(preservedMs, state.durationMs) : preservedMs
        startCurrent(at: clampedMs, playing: wasPlaying, sameEntryRepeated: true)
    }

    // MARK: Audio session, remote commands, Now Playing

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            LifecycleLog.record("audioSession.setCategory playback success")
        } catch { LifecycleLog.record("audioSession.setCategory failed: \(error.localizedDescription)") }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            LifecycleLog.record("audioSession.setActive true success")
        } catch { LifecycleLog.record("audioSession.setActive failed: \(error.localizedDescription)") }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ArtworkLoader.didChange, object: nil, queue: .main) { [weak self] note in
            let path = note.object as? String
            MainActor.assumeIsolated {
                guard let self, path == self.state.currentSong?.url.path else { return }
                self.artworkSongId = nil
                self.updateNowPlaying()
            }
        })
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(type: type, options: options) }
        })
        // Headphone / Bluetooth disconnect & reconnect handling ("Pause on Disconnect" / "Resume on Connect").
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previousRoute = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousHadHeadphones = previousRoute.map { HeadphoneRoutePolicy.containsHeadphones($0.outputs) } ?? false
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonRaw: reasonRaw, previousHadHeadphones: previousHadHeadphones)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.configureAudioSession()
                self.engine.rebuildAfterMediaServicesReset()
                self.restartAfterConfigurationChange()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.visualMotion.removeAll()
                self?.nowPlayingUpdate?.cancel()
                self?.nowPlayingUpdate = nil
                self?.publishNowPlaying()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.visualMotion.removeAll()
                self?.nowPlayingUpdate?.cancel()
                self?.nowPlayingUpdate = nil
                self?.publishNowPlaying()
                self?.listening.checkpoint()
                self?.persistNow()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateNowPlaying()
            }
        })
    }

    private func handleRouteChange(reasonRaw: UInt?, previousHadHeadphones: Bool) {
        guard let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        let currentHasHeadphones = HeadphoneRoutePolicy.containsHeadphones(AVAudioSession.sharedInstance().currentRoute.outputs)
        let action = headphonePolicy.handleRouteChange(
            reason: reason,
            previousHadHeadphones: previousHadHeadphones,
            currentHasHeadphones: currentHasHeadphones,
            intendsToPlay: intendsToPlay,
            hasCurrentSong: state.currentSong != nil,
            pauseOnDisconnect: settings?.pauseOnDisconnect ?? true,
            resumeOnConnect: settings?.resumeOnConnect ?? false
        )
        switch action {
        case .none:
            break
        case .pause:
            pauseInternal()
        case .resume:
            play()
        }
    }

    private func handleInterruption(type: UInt?, options: UInt?) {
        guard let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch interruption {
        case .began:
            wasPlayingBeforeInterruption = intendsToPlay
            if wasPlayingBeforeInterruption {
                pauseInternal()
            }
        case .ended:
            let shouldResume = wasPlayingBeforeInterruption
                && AVAudioSession.InterruptionOptions(rawValue: options ?? 0).contains(.shouldResume)
            wasPlayingBeforeInterruption = false
            if shouldResume { play() }
        @unknown default:
            break
        }
    }

    private func configureRemoteCommands() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = Int64(event.positionTime * 1000)
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    private func recordAlbumPlayed(_ songID: Int64) {
        let database = database
        albumHistoryQueue.async { try? database.recordAlbumOfSongPlayed(songID) }
    }

    func setVisualMotion(_ reason: VisualMotion, active: Bool) {
        if active { visualMotion.insert(reason) } else { visualMotion.remove(reason) }
        if visualMotion.isEmpty, nowPlayingUpdate != nil { updateNowPlaying() }
    }

    /// Coalesce duplicate state/artwork publications. During gestures, keep MediaPlayer IPC
    /// off the initial input frame; a bounded delay also guarantees updates on a held drag.
    private func updateNowPlaying() {
        nowPlayingUpdate?.cancel()
        let delayed = !visualMotion.isEmpty && UIApplication.shared.applicationState == .active
        nowPlayingUpdate = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(delayed ? 350 : 0)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.nowPlayingUpdate = nil
            self.publishNowPlaying()
        }
    }

    func refreshSystemPlayback() {
        guard restoreFinished else { return }
        nowPlayingUpdate?.cancel()
        nowPlayingUpdate = nil
        publishNowPlaying(forceWidgetReload: true)
    }

    private func publishNowPlaying(forceWidgetReload: Bool = false) {
        // Opening from the widget must not erase the last snapshot while restoration runs.
        guard restoreFinished || state.currentSong != nil else { return }
        let waveformData = state.currentSong.flatMap { (try? database.cachedWaveform(songId: $0.id))?.levels }
        let waveformBars = waveformData.flatMap { PlayerWidgetSnapshot.downsampleWaveform($0, bars: 30) }
        PlayerWidgetPublisher.publish(song: state.currentSong, playing: state.isPlaying, positionMs: currentPositionMs(),
                                      durationMs: state.durationMs, waveform: waveformBars, forceReload: forceWidgetReload)
        guard let song = state.currentSong else {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        if artworkSongId != song.id {
            artworkSongId = song.id
            let exact = ArtworkLoader.shared.cachedImage(for: song.url, maxPixels: 600)
            let cached = exact ?? ArtworkLoader.shared.cachedImage(for: song.url, maxPixels: 600, fallbackSizes: [1200, 400, 300, 150, 120, 80])
            artwork = cached.map(Self.makeArtwork)
            if exact == nil { loadArtwork(for: song) }
        }
        var info: [String: Any] = [
            MPNowPlayingInfoPropertyExternalContentIdentifier: "amp.track.\(song.id)",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: Double(state.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(currentPositionMs()) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = state.isPlaying ? .playing : .paused
    }

    private func loadArtwork(for song: Song) {
        let url = song.url
        Task {
            let image = await ArtworkLoader.shared.image(for: url, maxPixels: 600)
            guard let image, self.state.currentSong?.id == song.id else { return }
            self.artwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    /// Nonisolated: the system calls the image handler off the main thread.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

/// The controller as the A–B loop sees it.
@MainActor
private final class ControllerLoopPlayer: LoopPlayer {
    unowned let controller: PlayerController

    init(controller: PlayerController) {
        self.controller = controller
    }

    var currentSongId: Int64? { controller.state.currentSong?.id }
    var currentIndex: Int { controller.state.currentIndex }
    var positionMs: Int64 { controller.currentPositionMs() }
    var durationMs: Int64 { controller.state.durationMs }

    func seekTo(_ positionMs: Int64) { controller.loopSeek(positionMs) }
}

/// Pattern-matching helper for collection refs.
private enum CollectionKindRef {
    case album(Int64)
    case playlist(Int64)

    init(_ ref: CollectionRef) {
        self = ref.kind == .album ? .album(ref.id) : .playlist(ref.id)
    }
}

/// The live playing position (see [PlayerController.clock]).
@MainActor
@Observable
final class PlaybackClock {
    var positionMs: Int64 = 0
}

enum HeadphoneRouteAction: Equatable, Sendable {
    case none
    case pause
    case resume
}

/// Decides whether wired or Bluetooth headphone route changes should auto-pause or auto-resume
/// playback without overriding a manual user pause.
struct HeadphoneRoutePolicy: Equatable, Sendable {
    private(set) var pausedByDisconnect = false
    private(set) var manuallyPaused = false

    static func containsHeadphones(_ outputs: [AVAudioSessionPortDescription]) -> Bool {
        outputs.contains { isHeadphonePort($0.portType) }
    }

    static func isHeadphonePort(_ port: AVAudioSession.Port) -> Bool {
        switch port {
        case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .carAudio, .lineOut:
            return true
        default:
            return false
        }
    }

    mutating func userDidPlay() {
        pausedByDisconnect = false
        manuallyPaused = false
    }

    mutating func userDidPause() {
        pausedByDisconnect = false
        manuallyPaused = true
    }

    mutating func handleRouteChange(
        reason: AVAudioSession.RouteChangeReason,
        previousHadHeadphones: Bool,
        currentHasHeadphones: Bool,
        intendsToPlay: Bool,
        hasCurrentSong: Bool,
        pauseOnDisconnect: Bool,
        resumeOnConnect: Bool
    ) -> HeadphoneRouteAction {
        switch reason {
        case .oldDeviceUnavailable:
            guard previousHadHeadphones && !currentHasHeadphones else { return .none }
            if intendsToPlay {
                if pauseOnDisconnect {
                    pausedByDisconnect = true
                    manuallyPaused = false
                    return .pause
                } else {
                    pausedByDisconnect = false
                    return .none
                }
            } else {
                // Playback was already paused before disconnecting (e.g. manually): never arm auto-resume.
                pausedByDisconnect = false
                return .none
            }
        case .newDeviceAvailable:
            guard currentHasHeadphones else { return .none }
            if resumeOnConnect && pausedByDisconnect && !manuallyPaused && !intendsToPlay && hasCurrentSong {
                pausedByDisconnect = false
                return .resume
            }
            return .none
        default:
            return .none
        }
    }
}
