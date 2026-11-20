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
    static let padding: CGFloat = 14
    static let spacing: CGFloat = 10
    static let coverRadius: CGFloat = 12
    static let touchSize: CGFloat = 44
    static let playSize: CGFloat = 48
    static let skipSize: CGFloat = 40
    static let titleSize: CGFloat = 16
    static let artistSize: CGFloat = 12
    static let triangleFraction: CGFloat = 0.55
    static let refreshInterval: TimeInterval = 5 * 60
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
    private func load(_ style: AmpWidgetStyle) -> PlayerEntry {
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
private struct PlayerWidgetView: View {
    let entry: PlayerEntry
    @Environment(\.widgetFamily) private var family
    private var compact: Bool { entry.style == .compact }
    private var ink: Color { compact ? Color(white: 0.08) : .white }
    private var title: String { entry.snapshot.songID == nil ? "Your music, ready." : entry.snapshot.title }
    private var artist: String { entry.snapshot.songID == nil ? "Open amp to choose a song" : entry.snapshot.artist }
    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        GeometryReader { geometry in
            if isSmall {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        artwork.frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 7))
                        Spacer()
                        wordmark
                    }
                    metadata
                    Spacer(minLength: 0)
                    controls
                }.padding(12)
            } else {
                switch entry.style {
                case .artwork:
                    HStack(spacing: WidgetMetrics.spacing) {
                        artwork.frame(width: max(geometry.size.height - 28, 60), height: max(geometry.size.height - 28, 60))
                            .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.coverRadius))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Spacer(); wordmark }
                            metadata
                            Spacer(minLength: 0)
                            controls
                        }
                    }.padding(WidgetMetrics.padding)
                case .compact:
                    VStack(spacing: 7) {
                        HStack(spacing: WidgetMetrics.spacing) {
                            artwork.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9))
                            metadata
                            Spacer(minLength: 0)
                            wordmark
                        }
                        Spacer(minLength: 0)
                        controls
                        progress.frame(height: 4)
                    }.padding(WidgetMetrics.padding)
                case .immersive:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) { metadata; Spacer(minLength: 0); wordmark }
                        Spacer(minLength: 0)
                        controls
                    }.padding(WidgetMetrics.padding)
                }
            }
        }
        .foregroundStyle(ink)
        .containerBackground(for: .widget) { background }
        .widgetURL(PlayerLaunchRequest.url())
    }
    private var wordmark: some View {
        Text("amp").font(.system(size: 17, weight: .heavy)).foregroundStyle(ink.opacity(0.85))
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: isSmall ? 13 : WidgetMetrics.titleSize, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(artist).font(.system(size: isSmall ? 10 : WidgetMetrics.artistSize))
                .foregroundStyle(ink.opacity(0.7)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var controls: some View {
        HStack(spacing: 0) {
            playbackButton(.previous, symbol: "backward.fill", label: "Previous track")
            Spacer(minLength: 0)
            playbackButton(.toggle, symbol: entry.snapshot.isPlaying ? "pause.fill" : "play.fill",
                           label: entry.snapshot.isPlaying ? "Pause" : "Play")
            Spacer(minLength: 0)
            playbackButton(.next, symbol: "forward.fill", label: "Next track")
        }.buttonStyle(.plain)
    }
    private func playbackButton(_ command: AmpWidgetCommand, symbol: String, label: String) -> some View {
        let side = command == .toggle && !isSmall ? WidgetMetrics.playSize : WidgetMetrics.skipSize
        return Button(intent: AmpPlaybackIntent(command: command)) {
            Image(systemName: symbol).resizable().scaledToFit()
                .frame(width: side * (command == .toggle ? 0.43 : WidgetMetrics.triangleFraction), height: side * 0.43)
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(.black.opacity(entry.style == .immersive ? 0.8 : 1), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.15), lineWidth: 0.75) }
                .frame(minWidth: WidgetMetrics.touchSize, minHeight: WidgetMetrics.touchSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .disabled(entry.snapshot.songID == nil)
        .opacity(entry.snapshot.songID == nil ? 0.4 : 1)
    }
    @ViewBuilder private var progress: some View {
        let duration = Double(entry.snapshot.durationMs ?? 0) / 1000
        let position = min(max(Double(entry.snapshot.positionMs ?? 0) / 1000, 0), duration)
        if entry.snapshot.isPlaying, duration > 0, let date = entry.snapshot.updatedAt {
            let start = date.addingTimeInterval(-position)
            ProgressView(timerInterval: start...start.addingTimeInterval(duration), countsDown: false)
                .labelsHidden().tint(Color(red: 0.47, green: 0.29, blue: 0.16))
        } else {
            ProgressView(value: duration > 0 ? position / duration : 0)
                .tint(Color(red: 0.47, green: 0.29, blue: 0.16))
        }
    }
    @ViewBuilder private var background: some View {
        if entry.style == .immersive {
            GeometryReader { geometry in
                artwork.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay { LinearGradient(colors: [.black.opacity(0.68), .black.opacity(0.3), .black.opacity(0.58)], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }
        } else if compact {
            LinearGradient(colors: [Color(red: 0.96, green: 0.92, blue: 0.86), Color(red: 0.88, green: 0.81, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    @ViewBuilder private var artwork: some View {
        if let cover = entry.artwork {
            if #available(iOS 18.0, *) {
                Image(uiImage: cover).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
            } else { Image(uiImage: cover).resizable().scaledToFill() }
        } else {
            Rectangle().fill(compact ? .black.opacity(0.08) : .white.opacity(0.08))
                .overlay { Image(systemName: "music.note").font(.title2).foregroundStyle(ink.opacity(0.6)) }
        }
    }
}
struct AmpPlayerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: PlayerWidgetSnapshot.kind, intent: AmpWidgetConfiguration.self, provider: PlayerProvider()) {
            PlayerWidgetView(entry: $0)
        }
        .configurationDisplayName("amp Player")
        .description("Three styles. Previous, play/pause and next, without opening amp.")
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
        if #available(iOS 18.0, *) { AmpPlayerControl() }
    }
}
