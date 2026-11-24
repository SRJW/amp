import SwiftUI

struct SongRevealRequest: Hashable {
    let id = UUID()
    let songID: Int64
    let destination: Route
    var dismissesPlayer = false
}

extension Song {
    /// ForEach and ScrollViewReader share the same identity, including rows not yet created.
    var listScrollAnchor: String { "amp-song-\(id)" }
}

/// Wraps existing lists, rather than introducing a separate player destination screen.
struct PlayerSongReveal<Content: View>: View {
    let destination: Route
    let songs: [Song]
    var alphabetEnabled = false
    var alphabetKey: (Song) -> String = \.title
    @ViewBuilder let content: Content
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var alphabetTarget: Int64?

    private var readyRequest: SongRevealRequest? {
        guard let request = router.songReveal, request.destination == destination,
              songs.contains(where: { $0.id == request.songID }) else { return nil }
        return request
    }

    private var showsAlphabetIndex: Bool { alphabetEnabled && songs.count >= 8 }

    var body: some View {
        ScrollViewReader { proxy in
            content
                .padding(.trailing, showsAlphabetIndex ? SongAlphabetMetrics.width : 0)
                .overlay(alignment: .trailing) {
                    if showsAlphabetIndex {
                        SongAlphabetIndex(songs: songs, key: alphabetKey) { id in
                            alphabetTarget = id
                            withAnimation(reduceMotion ? nil : .easeOut(duration: SongAlphabetMetrics.scrollDuration)) {
                                proxy.scrollTo(Self.anchor(id), anchor: .top)
                            }
                        }
                    }
                }
                .task(id: alphabetTarget) {
                    guard let id = alphabetTarget else { return }
                    do {
                        // Rapid letter changes can outrun lazy row measurement. Once the
                        // latest scroll has settled, resolve that same identity again.
                        try await Task.sleep(for: .seconds(SongAlphabetMetrics.scrollDuration))
                        try Task.checkCancellation()
                        withAnimation(reduceMotion ? nil : .easeOut(duration: SongAlphabetMetrics.scrollDuration)) {
                            proxy.scrollTo(Self.anchor(id), anchor: .top)
                        }
                    } catch { /* A newer letter or navigation cancels this refinement. */ }
                }
                .task(id: readyRequest) {
                guard let request = readyRequest else { return }
                defer {
                    if !Task.isCancelled, router.songReveal?.id == request.id {
                        router.highlightedSongID = nil
                        router.songReveal = nil
                    }
                }
                do {
                    // Let the destination and its asynchronously loaded rows finish layout.
                    // Prepare the target under the player, before revealing the library.
                    try await Task.sleep(for: .seconds(PlayerButtonConstants.revealDelaySeconds))
                    proxy.scrollTo(Self.anchor(request.songID), anchor: .center)
                    // A lazy row can refine its height when artwork and metadata arrive.
                    try await Task.sleep(for: .seconds(PlayerButtonConstants.revealDelaySeconds))
                    proxy.scrollTo(Self.anchor(request.songID), anchor: .center)
                    router.completeSongReveal(request)
                    try await Task.sleep(for: .seconds(PlayerButtonConstants.highlightSeconds
                        + (request.dismissesPlayer ? PlayerMotionTiming.duration : 0)))
                } catch { /* Navigation cancels the transient highlight. */ }
            }
        }
    }

    static func anchor(_ songID: Int64) -> String { "amp-song-\(songID)" }
}

struct PlayerRevealedSong: ViewModifier {
    let songID: Int64
    @Environment(\.palette) private var palette
    @Environment(AppRouter.self) private var router
    func body(content: Content) -> some View {
        content.background {
            if router.highlightedSongID == songID {
                palette.primary.opacity(PlayerButtonConstants.highlightOpacity)
                    .allowsHitTesting(false)
            }
        }
    }
}
