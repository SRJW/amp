import SwiftUI

private enum IntroductionMetrics {
    static let horizontalPadding: CGFloat = 24
    static let heroHeight: CGFloat = 220
    static let cornerRadius: CGFloat = 30
    static let titleSize: CGFloat = 32
    static let bodySize: CGFloat = 16
    static let buttonHeight: CGFloat = 52
    static let transitionDuration = 0.28
}
struct IntroductionPage: Identifiable {
    let id: String
    let eyebrow: String
    let title: String
    let text: String
    let benefit: String
    let symbol: String
    static func pages() -> [Self] { [
        .init(id: "welcome", eyebrow: "THIS IS AMP", title: "Your music.\nIn full color.",
              text: "A player for the music you own. Keep your collection on your iPhone, without an amp account or a music subscription.",
              benefit: "Your collection. Your listening space.", symbol: "music.note"),
        .init(id: "library", eyebrow: "A LIBRARY THAT FITS YOU", title: "Less searching.\nMore listening.",
              text: "Browse songs, albums, artists and playlists. Reorder or hide Library sections, jump by letter, and return to recent searches.",
              benefit: "Find your favorites, your way.", symbol: "square.grid.2x2.fill"),
        .init(id: "import", eyebrow: "BRING YOUR COLLECTION", title: "Your files.\nStraight to amp.",
              text: "Import with Files or send music from your computer through Wi-Fi Transfer. Playback stays local; MP3, AAC, ALAC, FLAC and more are supported.",
              benefit: "Wi-Fi transfers stay on your local network.", symbol: "wifi"),
        .init(id: "listen", eyebrow: "MADE FOR LISTENING", title: "Press play.\nStay in the music.",
              text: "Enjoy immersive artwork, two waveform modes and synced lyrics when available. Swipe to change songs and manage your queue without losing your place.",
              benefit: "Your music, with its own atmosphere.", symbol: "play.fill"),
        .init(id: "sound", eyebrow: "FIND YOUR SOUND", title: "Every track.\nA smoother handover.",
              text: "Shape playback with the eight-band equalizer and adjustable crossfade. Use Transition Studio to fine-tune an album or playlist's handovers.",
              benefit: "More control over how your collection sounds.", symbol: "slider.vertical.3"),
        .init(id: "ready", eyebrow: "MAKE IT YOURS", title: "One app.\nYour own rhythm.",
              text: "Choose artwork colors, tune the player background and add a widget in one of three styles. Artwork Fetcher and tag repair are ready in the menu; their online searches send the metadata needed by each provider.",
              benefit: "Ready when you are. Revisit this guide in Settings.", symbol: "sparkles")
    ] }
}
struct IntroductionView: View {
    var firstLaunch = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = "welcome"
    private let pages = IntroductionPage.pages()
    private var index: Int { pages.firstIndex { $0.id == selected } ?? 0 }

    var body: some View {
        NavigationStack {
            TabView(selection: $selected) {
                ForEach(pages) { page in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            IntroductionIllustration(page: page.id)
                                .frame(height: IntroductionMetrics.heroHeight)
                                .glassSurface(cornerRadius: IntroductionMetrics.cornerRadius, enabled: settings.glassEnabled,
                                              tint: palette.primary.opacity(0.14))
                                .accessibilityHidden(true)
                            Text(page.eyebrow).font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(palette.primary)
                            Text(page.title).accessibilityIdentifier("introductionTitle").font(.system(size: IntroductionMetrics.titleSize, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(page.text).font(.system(size: IntroductionMetrics.bodySize)).lineSpacing(4)
                                .foregroundStyle(palette.onSurfaceVariant).fixedSize(horizontal: false, vertical: true)
                            Label(page.benefit, systemImage: page.symbol)
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(palette.primary)
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, IntroductionMetrics.horizontalPadding).padding(.vertical, 18)
                    }.tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .background {
                LinearGradient(colors: [palette.primary.opacity(0.07), palette.background, palette.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .foregroundStyle(palette.onSurface)
            .navigationTitle("Welcome to amp").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(firstLaunch ? "Skip" : "Done", action: finish) } }
        }
    }
    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { position in
                    Capsule().fill(position == index ? palette.primary : palette.onSurfaceVariant.opacity(0.22))
                        .frame(width: position == index ? 24 : 7, height: 6)
                }
                Spacer()
                Text("\(index + 1) / \(pages.count)").font(.caption.monospacedDigit()).foregroundStyle(palette.onSurfaceVariant)
            }
            Button(index == pages.count - 1 ? "Start listening" : "Continue") {
                if index == pages.count - 1 { finish() }
                else { withAnimation(reduceMotion ? nil : .easeInOut(duration: IntroductionMetrics.transitionDuration)) { selected = pages[index + 1].id } }
            }
            .accessibilityIdentifier("introductionPrimaryAction")
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.onPrimary)
            .frame(maxWidth: .infinity, minHeight: IntroductionMetrics.buttonHeight)
            .background(palette.primary, in: Capsule()).buttonStyle(.plain)
        }
        .padding(.horizontal, IntroductionMetrics.horizontalPadding).padding(.vertical, 16)
        .background(palette.background.opacity(0.96))
    }
    private func finish() {
        if firstLaunch { settings.introductionCompleted = true }
        dismiss()
    }
}
private struct IntroductionIllustration: View {
    let page: String
    @Environment(\.palette) private var palette
    var body: some View {
        Group {
            switch page {
            case "welcome":
                HStack(spacing: 20) {
                    Image(systemName: "play.fill").font(.system(size: 32, weight: .black))
                        .foregroundStyle(palette.onPrimary).frame(width: 88, height: 88)
                        .background(palette.primary, in: Circle()).shadow(color: palette.primary.opacity(0.2), radius: 18, y: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("amp").font(.system(size: 58, weight: .heavy)).tracking(-3)
                        Text("Your music, amplified.").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.onSurfaceVariant)
                    }
                }
            case "library":
                VStack(spacing: 9) {
                    previewRow("All Songs", detail: "Every track, in one place", symbol: "music.note.list")
                    previewRow("Albums & Artists", detail: "The people and records you love", symbol: "square.stack")
                    previewRow("Playlists & Favorites", detail: "Your own listening collections", symbol: "star.fill")
                }
            case "import":
                VStack(spacing: 18) {
                    HStack(spacing: 24) {
                        Image(systemName: "laptopcomputer").font(.system(size: 40))
                        Image(systemName: "wifi").font(.system(size: 25)).foregroundStyle(palette.primary)
                        Image(systemName: "iphone").font(.system(size: 42))
                    }
                    HStack { ForEach(["MP3", "AAC", "ALAC", "FLAC"], id: \.self) { badge($0) } }
                }
            case "listen":
                VStack(spacing: 18) {
                    HStack(spacing: 4) {
                        ForEach(0..<28) { index in
                            Capsule().fill(palette.primary.opacity(index < 13 ? 0.85 : 0.3))
                                .frame(width: 5, height: CGFloat(18 + (index * 19 + 11) % 55))
                        }
                    }.frame(height: 75)
                    HStack(spacing: 12) {
                        symbolButton("backward.fill", side: 40)
                        symbolButton("pause.fill", side: 54)
                        symbolButton("forward.fill", side: 40)
                    }
                }
            case "sound":
                VStack(spacing: 20) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach([44, 68, 90, 64, 102, 76, 50, 66], id: \.self) { height in
                            Capsule().fill(palette.primary.opacity(0.65)).frame(width: 13, height: CGFloat(height))
                        }
                    }.frame(height: 105)
                    HStack { Text("Crossfade").font(.system(size: 13, weight: .semibold)); Spacer(); Text("3 s").font(.caption.monospacedDigit()) }
                        .padding(12).background(palette.primary.opacity(0.08), in: Capsule())
                }
            default:
                VStack(spacing: 18) {
                    HStack(spacing: 10) {
                        ForEach([Color(red: 0.24, green: 0.19, blue: 0.15), Color(red: 0.15, green: 0.20, blue: 0.25), Color(red: 0.29, green: 0.14, blue: 0.17)], id: \.self) { color in
                            RoundedRectangle(cornerRadius: 15, style: .continuous).fill(color).frame(width: 58, height: 76)
                                .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                                .overlay { Image(systemName: "play.fill").font(.callout.weight(.bold)).foregroundStyle(.white.opacity(0.9)) }
                        }
                    }
                    HStack { badge("Your colors"); badge("Your widgets") }
                }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func previewRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(palette.primary).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer(minLength: 0)
        }.padding(10).background(palette.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }
    private func badge(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold)).padding(.horizontal, 11).padding(.vertical, 8)
            .background(palette.primary.opacity(0.1), in: Capsule())
    }
    private func symbolButton(_ symbol: String, side: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: side * 0.4, weight: .black))
            .foregroundStyle(palette.onPrimary).frame(width: side, height: side).background(palette.primary, in: Circle())
    }
}

private struct RadioAvailableKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var radioAvailable: Bool {
        get { self[RadioAvailableKey.self] }
        set { self[RadioAvailableKey.self] = newValue }
    }
}
