import SwiftUI
import WidgetKit
import UIKit
import AppIntents

enum AmpWidgetStyle: String, AppEnum {
    case artwork, compact, immersive
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .artwork: "A · Cover focus", .compact: "B · Compact", .immersive: "C · Immersive"
    ]
}
struct AmpWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "amp widget"
    static var description = IntentDescription("Choose the appearance of this widget.")
    @Parameter(title: "Style", default: .artwork) var style: AmpWidgetStyle
}
private enum WidgetMetrics {
    static let padding: CGFloat = 12
    static let smallPadding: CGFloat = 12
    static let spacing: CGFloat = 12
    static let coverRadius: CGFloat = 14
    static let compactCoverRadius: CGFloat = 10
    static let touchSize: CGFloat = 44
    static let compactTouchSize: CGFloat = 42
    static let smallTouchWidth: CGFloat = 40
    static let playSize: CGFloat = 42
    static let immersivePlaySize: CGFloat = 46
    static let skipSize: CGFloat = 34
    static let immersiveSkipSize: CGFloat = 38
    static let smallPlaySize: CGFloat = 40
    static let smallSkipSize: CGFloat = 34
    static let titleSize: CGFloat = 16.5
    static let compactTitleSize: CGFloat = 15
    static let immersiveTitleSize: CGFloat = 18
    static let artistSize: CGFloat = 12
    static let triangleFraction: CGFloat = 0.50
    static let refreshInterval: TimeInterval = 5 * 60
    static let fallbackWaveform: [UInt8] = [
        72, 112, 158, 128, 188, 224, 166, 138, 198, 240,
        210, 154, 122, 178, 220, 250, 194, 148, 174, 214,
        230, 164, 132, 184, 204, 158, 118, 142, 108, 76
    ]
}

private extension Color {
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}

private struct PlayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PlayerWidgetSnapshot
    let style: AmpWidgetStyle
    // Capture the cover while providing the timeline, rather than reopening a pruned file at render time.
    let artwork: UIImage?
}

private struct PlayerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PlayerEntry {
        PlayerEntry(date: .now, snapshot: .empty, style: .artwork, artwork: nil)
    }
    func snapshot(for configuration: AmpWidgetConfiguration, in context: Context) async -> PlayerEntry {
        load(configuration.style)
    }
    func timeline(for configuration: AmpWidgetConfiguration, in context: Context) async -> Timeline<PlayerEntry> {
        Timeline(entries: [load(configuration.style)], policy: .after(.now.addingTimeInterval(WidgetMetrics.refreshInterval)))
    }
    private func load(_ style: AmpWidgetStyle) -> PlayerEntry { PlayerEntryLoader.load(style) }
}

private enum PlayerEntryLoader {
    static func load(_ style: AmpWidgetStyle) -> PlayerEntry {
        let cacheFolder = URL.applicationSupportDirectory.appendingPathComponent("amp-widget", isDirectory: true)
        let cached = PlayerWidgetArchive.load(in: cacheFolder)
        if let folder = PlayerWidgetSnapshot.folder, let snapshot = PlayerWidgetSnapshot.read(in: folder) {
            let filename = snapshot.artworkFileName ?? "cover.jpg"
            var data: Data? = snapshot.hasArtwork && filename == (filename as NSString).lastPathComponent
                ? (try? Data(contentsOf: folder.appendingPathComponent(filename))) : nil
            if data == nil, cached?.snapshot.songID == snapshot.songID, snapshot.hasArtwork { data = cached?.artwork }
            let archive = PlayerWidgetArchive(snapshot: snapshot, artwork: data)
            try? archive.save(in: cacheFolder)
            return PlayerEntry(date: .now, snapshot: snapshot, style: style, artwork: data.flatMap { UIImage(data: $0) })
        }
        return PlayerEntry(date: .now, snapshot: cached?.snapshot ?? PlayerWidgetSnapshot.load(), style: style,
                           artwork: (cached?.artwork).flatMap { UIImage(data: $0) })
    }
}

/// Dedicated gallery entries remain selectable when a sideloaded installation
/// does not expose WidgetConfigurationIntent's Edit Widget metadata.
private struct FixedStylePlayerProvider: TimelineProvider {
    let style: AmpWidgetStyle
    func placeholder(in context: Context) -> PlayerEntry {
        PlayerEntry(date: .now, snapshot: .empty, style: style, artwork: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (PlayerEntry) -> Void) {
        completion(PlayerEntryLoader.load(style))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlayerEntry>) -> Void) {
        completion(Timeline(entries: [PlayerEntryLoader.load(style)],
                            policy: .after(.now.addingTimeInterval(WidgetMetrics.refreshInterval))))
    }
}

private struct PlayerWidgetView: View {
    let entry: PlayerEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var isSmall: Bool { family == .systemSmall }
    private var hasArtwork: Bool { entry.artwork != nil }
    private var hasSong: Bool { entry.snapshot.songID != nil }
    private var title: String { hasSong ? entry.snapshot.title : "Your music, ready." }
    private var artist: String { hasSong ? entry.snapshot.artist : "Open amp to choose a song" }
    private var artworkPalette: WidgetArtworkPalette { entry.snapshot.palette ?? .fallback }
    private var compactUsesLight: Bool { colorScheme == .light }
    private var activeTone: WidgetTonePalette {
        entry.style == .compact && compactUsesLight ? artworkPalette.light : artworkPalette.dark
    }
    private var primaryInk: Color {
        if !hasArtwork {
            return entry.style == .compact && compactUsesLight ? Color(argb: 0xFF12_1316) : Color(argb: 0xFFF8_F9FA)
        }
        return entry.style == .immersive ? .white : Color(argb: activeTone.content)
    }
    private var secondaryInk: Color {
        if !hasArtwork {
            return primaryInk.opacity(0.60)
        }
        return entry.style == .immersive ? .white.opacity(0.75) : Color(argb: activeTone.secondary)
    }
    private var accentColor: Color {
        hasArtwork ? Color(argb: activeTone.accent) : primaryInk
    }
    private var headerBadgeText: String? {
        let album = entry.snapshot.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let format = entry.snapshot.formatBadge?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !album.isEmpty && !format.isEmpty { return "\(album) · \(format)" }
        if !format.isEmpty { return format }
        if !album.isEmpty { return album }
        return nil
    }
    private var durationSeconds: Double { max(Double(entry.snapshot.durationMs ?? 0) / 1000, 0) }
    private var positionSeconds: Double {
        let raw = Double(entry.snapshot.positionMs ?? 0) / 1000
        return durationSeconds > 0 ? min(max(raw, 0), durationSeconds) : 0
    }
    private var progressFraction: Double {
        durationSeconds > 0 ? min(max(positionSeconds / durationSeconds, 0), 1) : 0
    }
    private var liveTimerRange: ClosedRange<Date>? {
        guard entry.snapshot.isPlaying, durationSeconds > 0, let date = entry.snapshot.updatedAt else { return nil }
        let start = date.addingTimeInterval(-positionSeconds)
        let end = start.addingTimeInterval(durationSeconds)
        return end > start ? start...end : nil
    }

    var body: some View {
        GeometryReader { geometry in
            switch entry.style {
            case .artwork:
                coverStageContent(size: geometry.size)
            case .compact:
                miniPlayerContent(size: geometry.size)
            case .immersive:
                immersiveContent(size: geometry.size)
            }
        }
        .foregroundStyle(primaryInk)
        .containerBackground(for: .widget) { background }
        .widgetURL(PlayerLaunchRequest.url())
    }

    // MARK: - Style A · Cover Stage

    @ViewBuilder
    private func coverStageContent(size: CGSize) -> some View {
        if isSmall {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    artworkTile(side: 54, radius: 13)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        wordmark(size: 12, opacity: 0.48)
                        if let format = entry.snapshot.formatBadge, !format.isEmpty {
                            Text(format)
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(secondaryInk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(primaryInk.opacity(0.09), in: Capsule())
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                coverStageControls(compact: true)
            }
            .padding(WidgetMetrics.smallPadding)
        } else {
            let coverSide = min(max(size.height - WidgetMetrics.padding * 2, 64), size.width * 0.42)
            HStack(alignment: .center, spacing: WidgetMetrics.spacing) {
                artworkTile(side: coverSide, radius: WidgetMetrics.coverRadius)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 6) {
                        if let badge = headerBadgeText {
                            Text(badge.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(secondaryInk)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(primaryInk.opacity(0.08), in: Capsule())
                        }
                        Spacer(minLength: 4)
                        wordmark(size: 12, opacity: 0.48)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: WidgetMetrics.titleSize, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(artist)
                            .font(.system(size: WidgetMetrics.artistSize))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if durationSeconds > 0 {
                        HStack(spacing: 6) {
                            slimProgressBar(tint: accentColor)
                            elapsedLabel(size: 9.5, alignment: .trailing)
                        }
                        .padding(.top, 5)
                    }
                    Spacer(minLength: 4)
                    coverStageControls(compact: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(WidgetMetrics.padding)
        }
    }

    private func coverStageControls(compact: Bool) -> some View {
        let playSide = compact ? WidgetMetrics.smallPlaySize : WidgetMetrics.playSize
        let skipSide = compact ? WidgetMetrics.smallSkipSize : WidgetMetrics.skipSize
        let playFill = hasArtwork ? Color(argb: activeTone.buttonFill) : primaryInk
        let playInk = hasArtwork ? Color(argb: activeTone.onButtonFill) : Color.black
        return HStack(spacing: 0) {
            circularButton(.previous, symbol: "backward.fill", label: "Previous track", side: skipSide,
                           fill: primaryInk.opacity(0.10), glyph: primaryInk, stroke: nil, accentable: false)
            Spacer(minLength: 0)
            circularButton(.toggle, symbol: entry.snapshot.isPlaying ? "pause.fill" : "play.fill",
                           label: entry.snapshot.isPlaying ? "Pause" : "Play", side: playSide,
                           fill: playFill, glyph: playInk, stroke: Color.white.opacity(0.18), accentable: true)
            Spacer(minLength: 0)
            circularButton(.next, symbol: "forward.fill", label: "Next track", side: skipSide,
                           fill: primaryInk.opacity(0.10), glyph: primaryInk, stroke: nil, accentable: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Style B · Mini Player

    @ViewBuilder
    private func miniPlayerContent(size: CGSize) -> some View {
        let isLight = compactUsesLight
        let dockFill = isLight ? Color.white.opacity(0.56) : Color.white.opacity(0.09)
        let dockStroke = isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.11)
        let playFill: Color = {
            if !hasArtwork { return primaryInk }
            return isLight ? Color(argb: activeTone.content) : Color(argb: activeTone.buttonFill)
        }()
        let playInk: Color = {
            if !hasArtwork { return isLight ? .white : .black }
            return isLight ? .white : Color(argb: activeTone.onButtonFill)
        }()

        if isSmall {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    artworkTile(side: 36, radius: 9)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(artist)
                            .font(.system(size: 10))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                miniWaveform(bars: 16, maxHeight: 16)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    dockIconButton(.previous, symbol: "backward.fill", label: "Previous track", size: 12.5)
                    Spacer(minLength: 0)
                    Button(intent: AmpPlaybackIntent(command: .toggle)) {
                        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(playInk)
                            .frame(width: 34, height: 30)
                            .background(playFill, in: Capsule())
                            .frame(minWidth: WidgetMetrics.smallTouchWidth, minHeight: 34)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(entry.snapshot.isPlaying ? "Pause" : "Play")
                    .disabled(!hasSong)
                    .opacity(hasSong ? 1 : 0.4)
                    .widgetAccentable()
                    Spacer(minLength: 0)
                    dockIconButton(.next, symbol: "forward.fill", label: "Next track", size: 12.5)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(dockFill, in: Capsule())
                .overlay { Capsule().stroke(dockStroke, lineWidth: 0.75) }
            }
            .padding(WidgetMetrics.smallPadding)
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    artworkTile(side: 42, radius: WidgetMetrics.compactCoverRadius)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(title)
                            .font(.system(size: WidgetMetrics.compactTitleSize, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                        Text(artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack {
                        wordmark(size: 12, opacity: 0.45)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 40)
                }
                Spacer(minLength: 4)
                HStack(alignment: .center, spacing: 6) {
                    if durationSeconds > 0 {
                        elapsedLabel(size: 10, alignment: .leading)
                    }
                    VStack(spacing: 3) {
                        miniWaveform(bars: 24, maxHeight: 16)
                        if durationSeconds > 0 {
                            slimProgressBar(tint: accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if durationSeconds > 0 {
                        Text(formatDuration(durationSeconds))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: timerLabelWidth, alignment: .trailing)
                    }
                }
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    dockIconButton(.previous, symbol: "backward.fill", label: "Previous track", size: 14.5)
                    Spacer(minLength: 0)
                    Button(intent: AmpPlaybackIntent(command: .toggle)) {
                        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(playInk)
                            .frame(width: 64, height: 32)
                            .background(playFill, in: Capsule())
                            .shadow(color: .black.opacity(isLight ? 0.14 : 0.26), radius: 5, y: 2)
                            .frame(minWidth: 64, minHeight: 34)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(entry.snapshot.isPlaying ? "Pause" : "Play")
                    .disabled(!hasSong)
                    .opacity(hasSong ? 1 : 0.4)
                    .widgetAccentable()
                    Spacer(minLength: 0)
                    dockIconButton(.next, symbol: "forward.fill", label: "Next track", size: 14.5)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(dockFill, in: Capsule())
                .overlay { Capsule().stroke(dockStroke, lineWidth: 0.75) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(WidgetMetrics.padding)
        }
    }

    // MARK: - Style C · Now Playing Bleed

    @ViewBuilder
    private func immersiveContent(size: CGSize) -> some View {
        if isSmall {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer(minLength: 0)
                    wordmark(size: 11.5, opacity: 0.72)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(hasArtwork ? 0.26 : 0), in: Capsule())
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .shadow(color: .black.opacity(0.28), radius: 6, y: 1)
                    Text(artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)
                immersiveControls(compact: true)
            }
            .padding(WidgetMetrics.smallPadding)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: WidgetMetrics.immersiveTitleSize, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                            .shadow(color: .black.opacity(0.26), radius: 8, y: 1)
                        Text(artist)
                            .font(.system(size: 12.5))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                        if durationSeconds > 0 {
                            slimProgressBar(tint: hasArtwork ? Color(argb: artworkPalette.dark.accent) : .white)
                                .frame(width: 112)
                                .padding(.top, 7)
                        }
                    }
                    .frame(maxWidth: size.width * 0.64, alignment: .leading)
                    Spacer(minLength: 0)
                    wordmark(size: 12, opacity: hasArtwork ? 0.82 : 0.48)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(hasArtwork ? 0.26 : 0), in: Capsule())
                }
                Spacer(minLength: 0)
                immersiveControls(compact: false)
            }
            .padding(14)
        }
    }

    private func immersiveControls(compact: Bool) -> some View {
        let playSide = compact ? WidgetMetrics.smallPlaySize : WidgetMetrics.immersivePlaySize
        let skipSide = compact ? WidgetMetrics.smallSkipSize : WidgetMetrics.immersiveSkipSize
        return HStack(spacing: compact ? 0 : 20) {
            if !compact { Spacer(minLength: 0) }
            smokedGlassButton(.previous, symbol: "backward.fill", label: "Previous track", side: skipSide, primary: false)
            if compact { Spacer(minLength: 0) }
            smokedGlassButton(.toggle, symbol: entry.snapshot.isPlaying ? "pause.fill" : "play.fill",
                              label: entry.snapshot.isPlaying ? "Pause" : "Play", side: playSide, primary: true)
            if compact { Spacer(minLength: 0) }
            smokedGlassButton(.next, symbol: "forward.fill", label: "Next track", side: skipSide, primary: false)
            if !compact { Spacer(minLength: 0) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable Controls & Visual Elements

    private func wordmark(size: CGFloat, opacity: Double) -> some View {
        Text("amp")
            .font(.system(size: size, weight: .heavy))
            .tracking(-0.5)
            .foregroundStyle(primaryInk.opacity(opacity))
            .widgetAccentable()
    }

    private func circularButton(_ command: AmpWidgetCommand, symbol: String, label: String, side: CGFloat,
                                fill: Color, glyph: Color, stroke: Color?, accentable: Bool) -> some View {
        let isToggle = command == .toggle
        let minTouch = isSmall ? WidgetMetrics.smallTouchWidth : WidgetMetrics.compactTouchSize
        return Button(intent: AmpPlaybackIntent(command: command)) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: side * (isToggle ? 0.39 : WidgetMetrics.triangleFraction), height: side * 0.39)
                .foregroundStyle(glyph)
                .frame(width: side, height: side)
                .background(fill, in: Circle())
                .overlay {
                    if let stroke {
                        Circle().stroke(stroke, lineWidth: 0.75)
                    }
                }
                .shadow(color: .black.opacity(isToggle ? 0.26 : 0), radius: 5, y: 2)
                .frame(minWidth: minTouch, minHeight: minTouch)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .disabled(!hasSong)
        .opacity(hasSong ? 1 : 0.4)
        .widgetAccentable(accentable)
    }

    private func smokedGlassButton(_ command: AmpWidgetCommand, symbol: String, label: String,
                                   side: CGFloat, primary: Bool) -> some View {
        let isToggle = command == .toggle
        return Button(intent: AmpPlaybackIntent(command: command)) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: side * (isToggle ? 0.39 : WidgetMetrics.triangleFraction), height: side * 0.39)
                .foregroundStyle(!hasArtwork && primary ? Color.black : Color.white)
                .frame(width: side, height: side)
                .background {
                    if !hasArtwork && primary {
                        Circle().fill(Color.white)
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay { Circle().fill(Color.black.opacity(primary ? 0.50 : 0.36)) }
                    }
                }
                .overlay {
                    Circle().stroke(
                        LinearGradient(colors: [.white.opacity(primary ? 0.34 : 0.24), .white.opacity(0.07)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
                }
                .shadow(color: .black.opacity(primary ? 0.34 : 0.24), radius: primary ? 8 : 5, y: 3)
                .frame(minWidth: isSmall ? WidgetMetrics.smallTouchWidth : WidgetMetrics.touchSize,
                       minHeight: WidgetMetrics.touchSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .disabled(!hasSong)
        .opacity(hasSong ? 1 : 0.4)
        .widgetAccentable(primary)
    }

    private func dockIconButton(_ command: AmpWidgetCommand, symbol: String, label: String, size: CGFloat) -> some View {
        Button(intent: AmpPlaybackIntent(command: command)) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(primaryInk.opacity(0.86))
                .frame(minWidth: isSmall ? 36 : WidgetMetrics.touchSize, minHeight: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .disabled(!hasSong)
        .opacity(hasSong ? 1 : 0.4)
    }

    private func miniWaveform(bars count: Int, maxHeight: CGFloat) -> some View {
        let raw = (entry.snapshot.waveform?.isEmpty == false) ? entry.snapshot.waveform! : WidgetMetrics.fallbackWaveform
        let levels = resampledBars(from: raw, count: count)
        let barWidth: CGFloat = isSmall ? 3 : 3.5
        return HStack(alignment: .center, spacing: 0) {
            ForEach(levels.indices, id: \.self) { index in
                let fraction = Double(index) / Double(max(count - 1, 1))
                let played = hasSong && fraction <= progressFraction
                let normalized = Double(levels[index]) / 255.0
                let barHeight = max(3, CGFloat(normalized) * maxHeight)
                Capsule()
                    .fill(played ? accentColor : primaryInk.opacity(0.18))
                    .frame(width: barWidth, height: barHeight)
                    .widgetAccentable(played)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: maxHeight)
    }

    private func resampledBars(from source: [UInt8], count: Int) -> [UInt8] {
        guard !source.isEmpty, count > 0 else { return [] }
        if source.count == count { return source }
        return (0..<count).map { index in
            let position = index * source.count / count
            return source[min(position, source.count - 1)]
        }
    }

    @ViewBuilder
    private func slimProgressBar(tint: Color) -> some View {
        Group {
            if let range = liveTimerRange {
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: progressFraction)
            }
        }
        .progressViewStyle(.linear)
        .labelsHidden()
        .tint(tint)
        .frame(height: 4)
        .clipped()
        .widgetAccentable()
    }

    private var timerLabelWidth: CGFloat { durationSeconds >= 3600 ? 48 : 36 }

    @ViewBuilder
    private func elapsedLabel(size: CGFloat, alignment: Alignment) -> some View {
        Group {
            if let range = liveTimerRange {
                Text(timerInterval: range, countsDown: false, showsHours: durationSeconds >= 3600)
            } else {
                Text(formatDuration(positionSeconds))
            }
        }
        .font(.system(size: size, weight: .medium).monospacedDigit())
        .foregroundStyle(secondaryInk)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        .frame(width: timerLabelWidth, alignment: alignment)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    private func artworkTile(side: CGFloat, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Group {
            if let cover = entry.artwork {
                artworkImage(cover)
                    .frame(width: side, height: side)
                    .clipped()
                    .clipShape(shape)
                    .overlay {
                        shape.stroke(Color.white.opacity(entry.style == .compact && compactUsesLight ? 0.55 : 0.16),
                                     lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(entry.style == .compact && compactUsesLight ? 0.14 : 0.34),
                            radius: side > 80 ? 10 : 5, y: side > 80 ? 5 : 2)
            } else {
                shape
                    .fill(primaryInk.opacity(0.07))
                    .frame(width: side, height: side)
                    .overlay {
                        Text("amp")
                            .font(.system(size: max(side * 0.22, 11), weight: .heavy))
                            .tracking(-0.8)
                            .foregroundStyle(primaryInk.opacity(0.28))
                    }
                    .overlay { shape.stroke(primaryInk.opacity(0.12), lineWidth: 0.75) }
            }
        }
    }

    @ViewBuilder
    private func artworkImage(_ cover: UIImage) -> some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: cover).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
        } else {
            Image(uiImage: cover).resizable().scaledToFill()
        }
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private var background: some View {
        if !hasArtwork {
            missingArtworkBackground
        } else {
            switch entry.style {
            case .artwork:
                let tone = artworkPalette.dark
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [Color(argb: tone.cardTop), Color(argb: tone.surface), Color(argb: tone.cardBottom)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [Color(argb: tone.accent).opacity(0.20), .clear],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 150
                    )
                    ContainerRelativeShape()
                        .strokeBorder(Color(argb: tone.rim).opacity(0.34), lineWidth: 1)
                }
            case .compact:
                let tone = activeTone
                ZStack {
                    LinearGradient(
                        colors: [Color(argb: tone.cardTop), Color(argb: tone.surface), Color(argb: tone.cardBottom)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ContainerRelativeShape()
                        .strokeBorder(Color(argb: tone.rim).opacity(compactUsesLight ? 0.24 : 0.32), lineWidth: 1)
                }
            case .immersive:
                immersiveBackground
            }
        }
    }

    private var missingArtworkBackground: some View {
        let isLight = entry.style == .compact && compactUsesLight
        let base = isLight ? Color.white : Color.black
        let watermark = (isLight ? Color.black : Color.white).opacity(0.068)
        return ZStack {
            base
            Text("amp")
                .font(.system(size: isSmall ? 54 : 86, weight: .heavy))
                .tracking(-3)
                .foregroundStyle(watermark)
                .offset(y: -3)
            ContainerRelativeShape()
                .strokeBorder((isLight ? Color.black : Color.white).opacity(0.10), lineWidth: 1)
        }
    }

    private var immersiveBackground: some View {
        let bleed = Color(argb: artworkPalette.bleed)
        let deep = Color(argb: artworkPalette.bleedDeep)
        return GeometryReader { geometry in
            if let cover = entry.artwork {
                if isSmall {
                    ZStack(alignment: .top) {
                        LinearGradient(colors: [bleed, deep], startPoint: .top, endPoint: .bottom)
                        artworkImage(cover)
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.80)
                            .clipped()
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black.opacity(0.86), location: 0.44),
                                    .init(color: .black.opacity(0.24), location: 0.76),
                                    .init(color: .clear, location: 1)
                                ], startPoint: .top, endPoint: .bottom)
                            }
                        LinearGradient(colors: [.black.opacity(0.24), .clear, deep.opacity(0.90)],
                                       startPoint: .top, endPoint: .bottom)
                        ContainerRelativeShape()
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
                } else {
                    ZStack(alignment: .trailing) {
                        LinearGradient(colors: [deep, bleed, deep], startPoint: .leading, endPoint: .trailing)
                        artworkImage(cover)
                            .frame(width: geometry.size.width * 0.72, height: geometry.size.height)
                            .clipped()
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black.opacity(0.24), location: 0.18),
                                    .init(color: .black.opacity(0.80), location: 0.45),
                                    .init(color: .black, location: 0.70),
                                    .init(color: .black, location: 1)
                                ], startPoint: .leading, endPoint: .trailing)
                            }
                        LinearGradient(colors: [.clear, deep.opacity(0.72)],
                                       startPoint: UnitPoint(x: 0.5, y: 0.52), endPoint: .bottom)
                        ContainerRelativeShape()
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.08)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1
                            )
                    }
                }
            }
        }
    }
}

struct AmpPlayerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: PlayerWidgetSnapshot.kind, intent: AmpWidgetConfiguration.self, provider: PlayerProvider()) {
            PlayerWidgetView(entry: $0)
        }
        .configurationDisplayName("amp · Cover focus")
        .description("Three artwork-adaptive styles. Previous, play/pause and next, without opening amp.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct AmpCompactWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PlayerWidgetSnapshot.compactKind, provider: FixedStylePlayerProvider(style: .compact)) {
            PlayerWidgetView(entry: $0)
        }
        .configurationDisplayName("amp · Compact")
        .description("Adaptive mini player with waveform progress and a frosted control dock.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct AmpImmersiveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PlayerWidgetSnapshot.immersiveKind, provider: FixedStylePlayerProvider(style: .immersive)) {
            PlayerWidgetView(entry: $0)
        }
        .configurationDisplayName("amp · Immersive")
        .description("Directional artwork bleed with smoked glass playback controls.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

@available(iOS 18.0, *)
struct AmpPlayerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlayerWidgetSnapshot.controlKind) {
            ControlWidgetButton(action: OpenAmpPlayerIntent()) { Label("amp", systemImage: "play.circle.fill") }
        }
        .displayName("Open amp")
        .description("Open amp at the current song.")
    }
}

@main
struct AmpWidgetBundle: WidgetBundle {
    var body: some Widget {
        AmpPlayerWidget()
        AmpCompactWidget()
        AmpImmersiveWidget()
        if #available(iOS 18.0, *) { AmpPlayerControl() }
    }
}
