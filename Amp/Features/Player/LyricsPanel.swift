import SwiftUI

/// The playing song's lyrics: synced lines follow the music (the current line bright, its words lit
/// as they are sung when the lyrics time them), a tap on a line seeks to it; plain lyrics scroll.
/// Without lyrics it shows what the online lookup is doing, never invented text. It sits on a
/// surface in the artwork's colours, with text colours checked for contrast against it.
struct LyricsPanel: View {
    let song: Song
    /// Set for Now Playing's card (Android's LyricsPanel): a "Lyrics" heading with this expand
    /// button, smaller lines, on the artwork-coloured card. Nil: the full-screen lyrics, with the
    /// source and the lyrics options, drawn on whatever is behind.
    var onExpand: (() -> Void)?
    /// Editorial full-screen layout with large typography, smooth active-line highlight, and soft depth blur.
    var immersive = false
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @State private var artworkPalette = ArtworkPaletteState()
    @State private var artworkRevision = 0

    var body: some View {
        let colors = LyricsColors(artworkPalette.palette(for: song.url), scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        LyricsPanelContent(song: song, onExpand: onExpand, immersive: immersive)
            .environment(\.palette, palette.lyrics(colors))
            .environment(\.lyricsColors, colors)
            .environment(\.lyricsCompact, onExpand != nil)
            .environment(\.lyricsImmersive, immersive)
            .background { if onExpand != nil { CardSurface(colors: colors, shape: shape) } }
            .clipShape(RoundedRectangle(cornerRadius: onExpand != nil ? Radius.large : 0, style: .continuous))
            .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
                if note.object as? String == song.url.path { artworkRevision += 1 }
            }
            .task(id: "\(song.url.path)|\(artworkRevision)") {
                // Resolve cached colours synchronously; this task only fills a cold or edited cover.
                let revision = ArtworkLoader.shared.revision(for: song.url.path)
                let next = await LyricsPaletteCache.shared.palette(for: song.url)
                guard !Task.isCancelled else { return }
                artworkPalette.set(next, for: song.url, revision: revision)
            }
    }
}

/// Now Playing's card material (Android's carouselCardSurface without glass): the artwork's card
/// gradient falling from the top-leading corner, with a rim bright along the top.
struct CardSurface<S: InsettableShape>: View {
    let colors: LyricsColors
    let shape: S

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: colors.cardGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(stops: [
                .init(color: colors.rim.opacity(0.5), location: 0),
                .init(color: colors.rim.opacity(0.12), location: 0.5),
                .init(color: .black.opacity(0.22), location: 1),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}

private struct LyricsCompactKey: EnvironmentKey {
    static let defaultValue = false
}

private struct LyricsImmersiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Lyrics set for the small card in Now Playing: smaller lines, the current one nearer the top.
    var lyricsCompact: Bool {
        get { self[LyricsCompactKey.self] }
        set { self[LyricsCompactKey.self] = newValue }
    }

    /// Editorial full-screen lyrics mode with large white-lit active line and soft depth-of-field blur.
    var lyricsImmersive: Bool {
        get { self[LyricsImmersiveKey.self] }
        set { self[LyricsImmersiveKey.self] = newValue }
    }
}

extension AppPalette {
    /// This palette with the lyrics colours for text: current line, other lines, the timed word.
    func lyrics(_ colors: LyricsColors) -> AppPalette {
        AppPalette(primary: colors.accent, onPrimary: colors.surface, background: background, surface: colors.surface,
                   surfaceVariant: colors.content.opacity(0.12), onSurface: colors.content,
                   onSurfaceVariant: colors.secondary, outline: colors.secondary.opacity(0.4))
    }
}

/// Reusable lyrics options menu with a custom label (used for standard headers and seamless immersive Title/Artist tap).
struct LyricsOptionsMenu<LabelContent: View>: View {
    let song: Song
    var onClose: (() -> Void)? = nil
    @ViewBuilder let label: () -> LabelContent
    @Environment(LyricsStore.self) private var store
    @State private var searching = false
    @State private var timingContext: LyricsTimingContext?
    @State private var searchText = ""

    var body: some View {
        let lyrics = store.current?.songId == song.id ? store.current : nil
        Menu {
            if store.canEmbed {
                Button { store.embedLyrics() } label: {
                    Label(L("Embed lyrics in file"), systemImage: "arrow.down.doc")
                }
                .disabled(store.embeddingLyrics)
            }
            if store.canDownload {
                Button { store.downloadLyrics() } label: { Label(L("Download lyrics"), systemImage: "arrow.down.circle") }
                    .disabled(store.savingLyrics)
            }
            if let saved = store.savedLyrics {
                Button(role: .destructive) { store.removeDownloadedLyrics() } label: {
                    Label(saved.explicitDownload == true ? L("Remove downloaded lyrics") : L("Remove previously saved lyrics"), systemImage: "trash")
                }.disabled(store.savingLyrics)
            }
            if let lyrics, case .synced? = lyrics.parsed {
                Button {
                    timingContext = LyricsTimingContext(song: song, lyrics: lyrics)
                } label: { Label(L("Adjust timing…"), systemImage: "timer") }
            }
            Divider()
            Button { store.refresh() } label: { Label(L("Refresh online lyrics"), systemImage: "arrow.clockwise") }
            Button {
                searchText = "\(song.title) \(song.artist)"
                searching = true
            } label: { Label(L("Search online…"), systemImage: "magnifyingglass") }
            if let lyrics, lyrics.hasFileLyrics, lyrics.origin != .file {
                Button { store.useFileLyrics() } label: { Label(L("Use the file's lyrics"), systemImage: "doc.text") }
            }
            if let onClose {
                Divider()
                Button(action: onClose) {
                    Label(L("Close lyrics"), systemImage: "chevron.down")
                }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Lyrics options")
        .sheet(item: $timingContext) { context in
            if let lyrics = store.current, LyricsTimingContext(song: song, lyrics: lyrics) == context {
                LyricsTimingEditor(song: song, lyrics: lyrics, context: context, preferences: store.timingPreferences)
            }
        }
        .sheet(isPresented: $searching, onDismiss: { store.closeSearch() }) {
            LyricsSearchSheet(searchText: $searchText, onDismiss: { searching = false })
                .task { if !searchText.isBlank { store.search(searchText) } }
        }
        .onChange(of: song.id) { _, _ in timingContext = nil }
        .onChange(of: store.current?.sourceID) { _, _ in timingContext = nil }
    }
}

/// Reusable lyrics options menu button for standard lyrics headers.
struct LyricsOptionsButton: View {
    let song: Song
    var floatingStyle = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        LyricsOptionsMenu(song: song) {
            if floatingStyle {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassCircle(enabled: settings.glassEnabled, interactive: true)
                    .environment(\.colorScheme, .dark)
            } else {
                Image(systemName: "ellipsis.circle").font(.body.weight(.semibold)).foregroundStyle(palette.onSurface)
                    .frame(width: 44, height: 32).contentShape(Rectangle())
            }
        }
    }
}

private struct LyricsPanelContent: View {
    let song: Song
    let onExpand: (() -> Void)?
    let immersive: Bool
    @Environment(LyricsStore.self) private var store
    @Environment(PlayerController.self) private var player
    @Environment(\.palette) private var palette
    @Environment(\.lyricsCompact) private var compact
    @State private var searching = false
    @State private var timingContext: LyricsTimingContext?
    @State private var searchText = ""

    var body: some View {
        let lyrics = store.current?.songId == song.id ? store.current : nil
        VStack(spacing: 0) {
            if let onExpand {
                cardHeader(lyrics, onExpand)
            } else if !immersive {
                header(lyrics)
                if let lyrics, case .synced? = lyrics.parsed {
                    Button("Not synced? Adjust timing") {
                        timingContext = LyricsTimingContext(song: song, lyrics: lyrics)
                    }
                    .font(.caption).foregroundStyle(palette.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.heroGutter).padding(.vertical, Spacing.sm)
                }
            }
            if let notice = store.embedNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(immersive ? .white.opacity(0.92) : palette.onSurface)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background((immersive ? Color.white.opacity(0.16) : palette.surfaceVariant), in: Capsule())
                    .padding(.vertical, Spacing.xs)
            }
            if let error = store.downloadError {
                Text(error).font(.footnote)
                    .foregroundStyle(immersive ? Color.white.opacity(0.8) : .secondary)
                    .padding(.horizontal)
            }
            if !immersive, let notice = lyrics?.syncedServiceNotice {
                Text(notice).font(.caption).foregroundStyle(palette.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, compact ? Spacing.lg : Spacing.heroGutter)
                    .padding(.vertical, Spacing.xs)
            }
            if let lyrics, let parsed = lyrics.parsed {
                switch parsed {
                case .synced(let lines):
                    SyncedLyricsView(lyrics: parsed, lines: lines,
                                     offsetMs: store.timingPreferences.offset(for: LyricsTimingContext(song: song, lyrics: lyrics)))
                case .plain(let lines): plain(lines)
                }
            } else if let onExpand {
                lookupLine(lyrics?.lookup ?? .idle, onExpand)
            } else {
                status(lyrics?.lookup ?? .idle)
            }
        }
        .sheet(item: $timingContext) { context in
            if let lyrics = store.current, LyricsTimingContext(song: song, lyrics: lyrics) == context {
                LyricsTimingEditor(song: song, lyrics: lyrics, context: context, preferences: store.timingPreferences)
            }
        }
        .onChange(of: song.id) { _, _ in timingContext = nil }
        .onChange(of: store.current?.sourceID) { _, _ in timingContext = nil }
        .task(id: song.id) { store.shown(song) }
        .sheet(isPresented: $searching, onDismiss: { store.closeSearch() }) {
            LyricsSearchSheet(searchText: $searchText, onDismiss: { searching = false })
                .task { if !searchText.isBlank { searchLyrics(searchText) } }
        }
    }

    private func cardHeader(_ lyrics: SongLyrics?, _ onExpand: @escaping () -> Void) -> some View {
        let plain = if case .plain? = lyrics?.parsed { true } else { false }
        return HStack {
            Text(plain ? "Lyrics · not synced" : "Lyrics").font(.subheadline.weight(.semibold)).foregroundStyle(palette.onSurface)
            Spacer()
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand lyrics")
        }
        .padding(.leading, Spacing.lg)
        .padding(.trailing, Spacing.xs)
        .padding(.top, Spacing.xs)
    }

    /// No lyrics text (yet) in the card: what the lookup is doing, never invented lyrics.
    private func lookupLine(_ lookup: LyricsLookup, _ onExpand: @escaping () -> Void) -> some View {
        let text = switch lookup {
        case .idle: "Lyrics unavailable"
        case .searching: "Looking for lyrics…"
        case .notFound: "No synced lyrics found · search online"
        case .instrumental: "Instrumental"
        case .offline: "Offline · synced lyrics couldn’t be checked"
        case .rateLimited, .failed: "No alternate lyrics available · search online"
        case .switching: "Checking another lyrics source…"
        case .usingFallback: "Lyrics unavailable · search online"
        }
        return Button(action: onExpand) {
            Text(text).font(.headline).foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func header(_ lyrics: SongLyrics?) -> some View {
        HStack {
            Text(origin(lyrics)).font(.caption.weight(.semibold)).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            Spacer()
            LyricsOptionsButton(song: song, floatingStyle: false)
        }
        .padding(.horizontal, Spacing.heroGutter)
    }

    private func origin(_ lyrics: SongLyrics?) -> String {
        guard let lyrics, lyrics.text != nil else { return "Lyrics" }
        switch lyrics.origin {
        case .file: return lyrics.parsed.map { if case .plain = $0 { "Lyrics · not synced" } else { "Lyrics · embedded" } } ?? "Lyrics"
        case .online, .onlineSaved:
            return "From \(lyrics.provider ?? "online") · \(lyrics.timing?.label ?? "")" + (store.currentIsDownloaded ? " · downloaded" : (lyrics.origin == .onlineSaved ? " · cached" : ""))
        }
    }

    private func plain(_ lines: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: immersive ? Spacing.md : Spacing.sm) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(compact ? .headline : (immersive ? .system(size: 24, weight: .bold) : .title3.weight(.semibold)))
                        .foregroundStyle(immersive ? Color.white.opacity(0.92) : palette.onSurface)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? Spacing.lg : Spacing.heroGutter)
            .padding(.vertical, Spacing.lg)
        }
        .scrollIndicators(.hidden)
    }

    private func status(_ lookup: LyricsLookup) -> some View {
        let info = statusText(lookup)
        return VStack(spacing: Spacing.md) {
            Spacer()
            if lookup.isSearching { ProgressView().tint(immersive ? .white : nil) }
            Text(info.0).font(.body)
                .foregroundStyle(immersive ? Color.white.opacity(0.76) : palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
            if !lookup.isSearching {
                HStack(spacing: Spacing.sm) {
                    if info.1 { Button(L("Retry")) { store.refresh() }.buttonStyle(.bordered) }
                    Button(L("Search online…")) {
                        searchText = "\(song.title) \(song.artist)"
                        searching = true
                    }
                    .foregroundStyle(immersive ? .white : palette.primary)
                }
                if let url = LyricsWebSearch.url(for: "\(song.title) \(song.artist)") {
                    Link(L("Search the web"), destination: url)
                        .foregroundStyle(immersive ? Color.white.opacity(0.8) : palette.primary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    private func statusText(_ lookup: LyricsLookup) -> (String, Bool) {
        switch lookup {
        case .searching: return ("Looking for lyrics online…", false)
        case .notFound: return ("No matching synced lyrics found. Search online for available versions.", false)
        case .instrumental: return ("This track is instrumental.", false)
        case .offline: return ("Synced lyrics couldn’t be checked while offline.", true)
        case .rateLimited, .failed: return ("No alternate lyrics could be loaded. Search online for other versions.", true)
        case .switching: return ("Looking for lyrics from another source…", false)
        case .usingFallback: return ("No alternate lyrics could be loaded.", true)
        case .idle: return ("No synced lyrics available. Search online for other versions.", false)
        }
    }

    private func searchLyrics(_ query: String) {
        SearchHistoryStore.shared.remember(query, in: "lyrics")
        store.search(query)
    }
}

struct LyricsSearchSheet: View {
    @Binding var searchText: String
    let onDismiss: () -> Void
    @Environment(LyricsStore.self) private var store
    @Environment(\.palette) private var palette
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if searchText.isBlank, !SearchHistoryStore.shared.entries("lyrics").isEmpty {
                    Section {
                        RecentSearchesView(scope: "lyrics") {
                            searchText = $0
                            searchLyrics($0)
                        }
                    }.toolSectionAppearance()
                }
                Section {
                    Button {
                        searchLyrics(searchText)
                        searchFocused = false
                    } label: {
                        Label(L("Search"), systemImage: "magnifyingglass")
                            .foregroundStyle(searchText.isBlank ? palette.onSurfaceVariant : palette.primary)
                    }
                    .disabled(searchText.isBlank)
                    if let url = LyricsWebSearch.url(for: searchText) {
                        Link(destination: url) {
                            Label(L("Search the web"), systemImage: "safari")
                                .foregroundStyle(palette.primary)
                        }
                    }
                } footer: {
                    Text(L("Opens in your browser."))
                }.toolSectionAppearance()
                Section {
                    switch store.current?.search ?? .idle {
                    case .idle: EmptyView()
                    case .searching: ProgressView().frame(maxWidth: .infinity)
                    case .error(let message): Text(message).foregroundStyle(palette.onSurfaceVariant)
                    case .results(let candidates): searchResults(candidates)
                    case .resultsWithNotice(let candidates, let notice):
                        Text(notice).font(.caption).foregroundStyle(palette.onSurfaceVariant)
                        searchResults(candidates)
                    }
                }.toolSectionAppearance()
            }
            .modifier(ToolPageAppearance())
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                GlassSearchField(
                    text: $searchText,
                    prompt: L("Title and artist"),
                    focused: $searchFocused,
                    close: { searchFocused = false; searchText = "" },
                    identifier: "lyricsSearchField",
                    historyScope: "lyrics"
                )
                .onSubmit { searchLyrics(searchText) }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.sm)
                .background(palette.background.opacity(0.92))
            }
            .navigationTitle(L("Search lyrics online"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L("Close")) { onDismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func searchResults(_ candidates: [LyricsCandidate]) -> some View {
        if candidates.isEmpty { Text(L("No results.")).foregroundStyle(palette.onSurfaceVariant) }
        ForEach(candidates) { candidate in
            Button {
                store.choose(candidate)
                onDismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.trackName).foregroundStyle(palette.onSurface)
                    Text([candidate.artistName, candidate.provider, candidate.timing.label].joined(separator: " · "))
                        .font(.caption).foregroundStyle(palette.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }

    private func searchLyrics(_ query: String) {
        SearchHistoryStore.shared.remember(query, in: "lyrics")
        store.search(query)
    }
}

/// Time-synced lines that follow playback.
struct SyncedLyricsView: View {
    let lyrics: Lyrics
    let lines: [LyricLine]
    var offsetMs: Int64 = 0
    @Environment(PlayerController.self) private var player
    @Environment(\.palette) private var palette
    @Environment(\.lyricsCompact) private var compact
    @Environment(\.lyricsImmersive) private var immersive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.playerInMotion) private var playerInMotion
    @Environment(\.visualWorkBudget) private var budget
    @State private var visible = false

    var body: some View {
        let wordTimed = lines.contains { !($0.words?.isEmpty ?? true) }
        let wantsSmoothSweep = (wordTimed || immersive) && budget.allowsDecorativeMotion && !reduceMotion
        let interval = wantsSmoothSweep ? 0.08 : 0.25
        TimelineView(.animation(minimumInterval: interval,
                                paused: !player.state.isPlaying || !visible || scenePhase != .active || playerInMotion)) { _ in
            let position = LyricsTimingPreferences.lyricsPosition(playbackMs: player.currentPositionMs(), offsetMs: offsetMs)
            let currentLine = lyrics.lineAt(position)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: compact ? Spacing.md : (immersive ? 26 : Spacing.lg)) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Button { player.seek(to: LyricsTimingPreferences.playbackPosition(lyricMs: line.timeMs, offsetMs: offsetMs)) } label: {
                                lineText(line, index: index, current: currentLine, position: position)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, compact ? Spacing.lg : (immersive ? 26 : Spacing.heroGutter))
                    .padding(.top, compact ? Spacing.lg : (immersive ? 26 : 120))
                    .padding(.bottom, compact ? 200 : (immersive ? 180 : 120))
                }
                .scrollIndicators(.hidden)
                .mask {
                    if immersive {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white, location: 0.14),
                            .init(color: .white, location: 0.82),
                            .init(color: .clear, location: 1.00),
                        ], startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle()
                    }
                }
                .onChange(of: currentLine) { _, line in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        proxy.scrollTo(max(line, 0), anchor: anchor)
                    }
                }
                .onAppear { proxy.scrollTo(max(currentLine, 0), anchor: anchor) }
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .reportsScrollVisibility { visible = $0 }
    }

    /// In the card the current line sits nearer the top; in immersive mode it frames one blurred past line above.
    private var anchor: UnitPoint {
        if compact { return UnitPoint(x: 0.5, y: 0.25) }
        return immersive ? UnitPoint(x: 0.5, y: 0.32) : .center
    }

    private func wordColor(_ index: Int, sung: Int) -> Color {
        if immersive {
            return index <= sung ? Color.white : Color.white.opacity(0.50)
        }
        if index < sung { return palette.onSurface }
        return index == sung ? palette.primary : palette.onSurfaceVariant
    }

    private func immersiveLineSweep(_ text: String, index: Int, position: Int64) -> Text {
        guard !reduceMotion, budget.allowsDecorativeMotion else {
            return Text(text).foregroundColor(.white)
        }
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false)
        guard tokens.count > 1 else {
            return Text(text).foregroundColor(.white)
        }
        let startMs = lines[index].timeMs
        let nextMs: Int64 = index + 1 < lines.count ? lines[index + 1].timeMs : (startMs + 4_000)
        let duration = max(min(nextMs - startMs, 9_000), 1_200)
        let progress = min(max(Double(position - startMs) / Double(duration), 0), 1)
        let litCount = min(Int(ceil(progress * Double(tokens.count))), tokens.count)
        return tokens.enumerated().reduce(Text("")) { acc, pair in
            let suffix = pair.offset == tokens.count - 1 ? "" : " "
            let color: Color = pair.offset < litCount ? .white : Color.white.opacity(0.50)
            return acc + Text(String(pair.element) + suffix).foregroundColor(color)
        }
    }

    private func lineText(_ line: LyricLine, index: Int, current: Int, position: Int64) -> some View {
        let isCurrent = index == current
        let distance = abs(index - current)
        let text = line.text.isEmpty ? "♪" : line.text
        let base = Text(text)
        let styled: Text
        if isCurrent, let words = line.words {
            let sung = lyrics.wordAt(line: index, position)
            styled = words.enumerated().reduce(Text("")) { acc, item in
                acc + Text(item.element.text).foregroundColor(wordColor(item.offset, sung: sung))
            }
        } else if isCurrent {
            styled = immersive ? immersiveLineSweep(text, index: index, position: position) : base.foregroundColor(palette.onSurface)
        } else if immersive {
            let opacity: Double
            if index == current - 1 { opacity = 0.34 }
            else if index == current + 1 { opacity = 0.42 }
            else if distance == 2 { opacity = 0.30 }
            else { opacity = 0.22 }
            styled = base.foregroundColor(Color.white.opacity(opacity))
        } else {
            let fade = compact ? 1 : max(1 - Double(distance) * 0.15, 0.45)
            styled = base.foregroundColor(palette.onSurfaceVariant.opacity(fade))
        }
        let blurRadius: CGFloat
        if immersive && !isCurrent && !reduceMotion && budget.allowsDecorativeMotion && distance <= 5 {
            if index == current - 1 { blurRadius = 3.0 }
            else if index == current + 1 { blurRadius = 2.6 }
            else if distance == 2 { blurRadius = 3.2 }
            else { blurRadius = 3.6 }
        } else {
            blurRadius = 0
        }
        return styled
            .font(compact ? .headline : (immersive ? .system(size: 31, weight: .bold) : .title2.weight(.bold)))
            .tracking(immersive ? -0.4 : 0)
            .lineSpacing(immersive ? 1 : 0)
            .blur(radius: blurRadius)
            .scaleEffect(isCurrent || compact || immersive ? 1 : 0.96, anchor: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: isCurrent)
    }
}
