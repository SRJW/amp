import AppIntents
import Foundation

enum AmpWidgetCommand: String, AppEnum {
    case toggle, previous, next
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playback"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .toggle: "Play / Pause", .previous: "Previous track", .next: "Next track"
    ]
}

/// AudioPlaybackIntent executes in the containing audio app, without foregrounding its UI.
struct AmpPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Control amp"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Action") var command: AmpWidgetCommand
    init() { command = .toggle }
    init(command: AmpWidgetCommand) { self.command = command }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !AMP_WIDGET_EXTENSION
        LifecycleLog.record("widget playback intent command=\(command.rawValue) foregroundRequested=false")
        let player = AppServices.shared.player
        for _ in 0..<200 {
            if player.restoreFinished { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard player.restoreFinished else { return .result() }
        guard player.state.currentSong != nil else {
            player.refreshSystemPlayback()
            return .result()
        }
        switch command {
        case .toggle: player.togglePlayPause()
        case .previous: player.skipToPreviousItem()
        case .next: player.skipNext()
        }
        // Do not request PlayerLaunchSignal or navigate: this is background playback only.
        player.refreshSystemPlayback()
        #endif
        return .result()
    }
}
