import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum SettingsPageRoute: String, Hashable { case appearance, language, visualizer, playback, library, metadata, about, playerBackground, imageCredits }

struct SettingsDestinationView: View {
    let page: SettingsPageRoute
    var body: some View {
        Group {
            switch page {
            case .appearance: AppearanceSettingsView()
            case .language: LanguageSettingsView()
            case .visualizer: VisualizerSettingsView()
            case .playback: PlaybackSettingsView()
            case .library: LibrarySettingsView()
            case .metadata: MetadataSettingsView()
            case .about: AboutSettingsView()
            case .playerBackground: PlayerBackgroundSettingsView()
            case .imageCredits: ImageCreditsView()
            }
        }.modifier(ToolPageAppearance())
    }
}

/// The Android settings groups, adapted to the controls and tools available on iOS.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        SettingsPage {
            SettingsGroup(L("Personalize")) {
                SettingsLink(L("Themes & Appearance"), subtitle: L("Colors, themes and appearance"), icon: "paintpalette.fill", page: .appearance)
                Divider().padding(.leading, 72)
                SettingsLink(L("Language"), subtitle: settings.language == .system ? "\(L("System default")) (\(settings.language.resolved.nativeName))" : settings.language.nativeName, icon: "globe", page: .language)
                    .accessibilityIdentifier("settingsLanguage")
            }
            SettingsGroup(L("Sound")) {
                SettingsLink(L("Playback"), subtitle: L("Song transitions and waveform mode"), icon: "play.circle", page: .playback)
                Divider().padding(.leading, 72)
                SettingsLink(L("Audio & Equalizer"), subtitle: L("8-band equalizer, presets and audio effects"), icon: "slider.vertical.3", tool: .equalizer)
                Divider().padding(.leading, 72)
                SettingsLink(L("Visualizer"), subtitle: L("Style and feel of the Now Playing visualizer"), icon: "waveform", page: .visualizer)
            }
            SettingsGroup(L("Library")) {
                SettingsLink(L("Music Library"), subtitle: L("Music folder, scanning and your collection"), icon: "folder.fill", page: .library)
                    .accessibilityIdentifier("settingsMusicLibrary")
                Divider().padding(.leading, 72)
                SettingsLink(L("Metadata & Artwork"), subtitle: L("Tags, cover art and online sources"), icon: "number", page: .metadata)
            }
            SettingsGroup(L("About")) {
                SettingsLink(L("About amp"), subtitle: L("Version, privacy and source code"), icon: "info.circle.fill", page: .about)
            }
        }
        .navigationTitle(L("Settings"))
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 26) { content }
                .padding(Spacing.lg)
                .padding(.bottom, AppNavigationMetrics.reservedHeight + Spacing.lg)
        }
        .modifier(ToolPageAppearance())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsChoice<Leading: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let choose: () -> Void
    @ViewBuilder let leading: Leading
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Spacing.lg) {
                leading.frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(palette.onSurface)
                    Text(subtitle).font(.subheadline).foregroundStyle(palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(selected ? palette.primary : palette.onSurfaceVariant)
            }
            .padding(Spacing.lg)
            .frame(minHeight: 88)
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsValueRow<Value: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: Spacing.lg) {
            SettingsIcon(symbol: icon)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            value.labelsHidden()
        }
        .padding(Spacing.lg)
    }
}

private struct ThemeSwatch: View {
    let choice: ThemeChoice
    @Environment(PlayerController.self) private var player
    @Environment(\.palette) private var palette

    var body: some View {
        switch choice {
        case .system:
            Image(systemName: "circle.lefthalf.filled").resizable().foregroundStyle(palette.onSurface)
        case .light:
            Circle().fill(.white).overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                .overlay(Circle().fill(.black.opacity(0.8)).padding(13))
        case .dark:
            Circle().fill(.black).overlay(Circle().strokeBorder(.white.opacity(0.2)))
                .overlay(Circle().fill(.white).padding(13))
        case .artwork:
            if let song = player.state.currentSong {
                SongArtworkView(song: song, maxPixels: 100).clipShape(Circle())
            } else {
                Circle().fill(AngularGradient(colors: [.cyan, .blue, .purple, .pink, .cyan], center: .center))
            }
        }
    }
}

private extension ThemeChoice {
    var settingsDescription: String {
        switch self {
        case .system: "Light or dark, following your iPhone"
        case .light: "A bright, clean appearance"
        case .dark: "A darker look for your library"
        case .artwork: "Artwork colors, following light or dark mode"
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.horizontal, Spacing.lg)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

private struct SettingsIcon: View {
    let symbol: String
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.onSurface)
            .frame(width: size, height: size)
            .background(palette.onSurface.opacity(0.09), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct SettingsLink: View {
    let title: String
    let subtitle: String
    let icon: String
    let route: Route
    @Environment(\.palette) private var palette

    init(_ title: String, subtitle: String, icon: String, page: SettingsPageRoute) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.route = .settingsPage(page)
    }

    init(_ title: String, subtitle: String, icon: String, tool: Tool) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.route = .tool(tool)
    }

    var body: some View {
        NavigationLink(value: route) { row }.pressable()
    }

    private var row: some View {
        HStack(spacing: Spacing.lg) {
            SettingsIcon(symbol: icon)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(palette.onSurface)
                Text(subtitle).font(.subheadline).foregroundStyle(palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onSurfaceVariant)
                .accessibilityHidden(true)
        }
        .padding(Spacing.lg)
        .frame(minHeight: 88)
        .contentShape(Rectangle())
    }
}

private struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var importingTheme = false
    @State private var themeMessage: String?

    var body: some View {
        SettingsPage {
            SettingsGroup(L("App theme")) {
                ForEach(ThemeChoice.allCases) { choice in
                    SettingsChoice(title: L(choice.label), subtitle: L(choice.settingsDescription),
                                   selected: settings.customTheme == nil && settings.theme == choice, choose: {
                        settings.useCustomTheme(nil)
                        settings.theme = choice
                    }) { ThemeSwatch(choice: choice) }
                }
                ForEach(settings.importedThemes) { theme in
                    SettingsChoice(title: theme.name, subtitle: L("By %@", theme.author),
                                   selected: settings.customTheme?.id == theme.id, choose: { settings.useCustomTheme(theme.id) }) {
                        Circle().fill(theme.palette.surface).overlay(Circle().fill(theme.palette.primary).padding(10))
                    }
                }
            }
            SettingsGroup(L("Your themes")) {
                Button { importingTheme = true } label: {
                    Label(L("Import a theme…"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.lg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let theme = settings.customTheme {
                    Button(role: .destructive) { settings.deleteTheme(theme.id) } label: {
                        Label(L("Delete %@", theme.name), systemImage: "trash")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.lg)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let themeMessage { Text(themeMessage).font(.footnote).foregroundStyle(.secondary).padding(Spacing.lg) }
            }
            SettingsGroup(L("Typeface")) {
                Picker(L("App font"), selection: Binding(get: { settings.typeface }, set: { settings.typeface = $0 })) {
                    ForEach(AppTypeface.allCases) { font in Text(L(font.label)).fontDesign(font.design).tag(font) }
                }.padding(Spacing.lg)
            }
            SettingsGroup(L("Display")) {
                Toggle(L("Bold text"), isOn: Binding(get: { settings.boldText }, set: { settings.boldText = $0 }))
                    .accessibilityIdentifier("settingsBoldText").padding(Spacing.lg)
                Divider().padding(.leading, Spacing.lg)
                Toggle(L("Glass surfaces"), isOn: Binding(get: { settings.glassEnabled }, set: { settings.glassEnabled = $0 }))
                    .accessibilityIdentifier("settingsGlassEnabled").padding(Spacing.lg)
            }
            PlayerBackgroundSettingsLink()
            Text(L("For system appearance and transparency options, open iPhone Settings → Accessibility → Display & Text Size. Liquid Glass options also depend on your iOS version."))
                .font(.footnote).foregroundStyle(.secondary)
            Text(L("Import custom colors from a theme ZIP or manifest.json."))
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $importingTheme, allowedContentTypes: [.zip, .json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let theme = try ThemeImporter.theme(from: try Data(contentsOf: url))
                settings.importTheme(theme)
                themeMessage = L("Imported %@.", theme.name)
            } catch {
                themeMessage = error.localizedDescription
            }
        }
        .navigationTitle(L("Themes & Appearance"))
    }
}

private struct LanguageSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        let activeLocale = settings.language.locale
        SettingsPage {
            SettingsGroup(L("Automatic")) {
                languageRow(
                    title: L("System default"),
                    subtitle: "\(L("Follows your iPhone language")) · \(AppLanguage.system.resolved.nativeName)",
                    selected: settings.language == .system,
                    accessibilityId: "language.system",
                    action: { settings.language = .system }
                ) {
                    SettingsIcon(symbol: "globe")
                }
            }
            SettingsGroup(L("Languages")) {
                ForEach(Array(AppLanguage.supportedLanguages.enumerated()), id: \.element.id) { index, language in
                    if index > 0 {
                        Divider().padding(.leading, 72)
                    }
                    languageRow(
                        title: language.nativeName,
                        subtitle: language.localizedName(in: activeLocale),
                        selected: settings.language == language,
                        accessibilityId: "language.\(language.rawValue)",
                        action: { settings.language = language }
                    ) {
                        Text(language.shortCode)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.onSurface)
                            .frame(width: 40, height: 40)
                            .background(palette.onSurface.opacity(0.09), in: Circle())
                    }
                }
            }
            Text(L("Changes apply immediately across amp. Song titles, artist names, and album metadata always stay in their original language."))
                .font(.footnote)
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
        }
        .navigationTitle(L("Language"))
    }

    private func languageRow<Leading: View>(
        title: String,
        subtitle: String,
        selected: Bool,
        accessibilityId: String,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.lg) {
                leading().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.onSurface)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier(accessibilityId)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PlayerBackgroundSettingsLink: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    private var summary: String {
        let style = L(settings.playerBackground.gradientStyle.label)
        if settings.playerBackground.navBarCapsule {
            return "\(style) · \(L(PlayerBackgroundControls.navBarCapsule))"
        }
        return style
    }

    var body: some View {
        SettingsGroup(L("Now Playing")) {
            NavigationLink(value: Route.settingsPage(.playerBackground)) {
                HStack(spacing: Spacing.md) {
                    SettingsIcon(symbol: "sparkles.rectangle.stack")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(PlayerBackgroundControls.title))
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.onSurface)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(palette.onSurfaceVariant)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .padding(Spacing.lg)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsPlayerBackgroundEntry")
        }
    }
}

private struct PlayerBackgroundSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerController.self) private var player
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewPalette = LyricsPalette.fallback

    private var gradientColor: Binding<Color> {
        Binding(get: { Color(argb: settings.playerBackground.gradientColor) }, set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            var appearance = settings.playerBackground
            func byte(_ component: CGFloat) -> UInt32 { UInt32((min(max(component, 0), 1) * 255).rounded()) }
            appearance.gradientColor = 0xFF000000 | byte(r) << 16 | byte(g) << 8 | byte(b)
            settings.playerBackground = appearance
        })
    }

    private func value(_ key: WritableKeyPath<PlayerBackgroundSettings, Double>) -> Binding<Double> {
        Binding(get: { settings.playerBackground[keyPath: key] }, set: {
            var appearance = settings.playerBackground
            appearance[keyPath: key] = $0
            settings.playerBackground = appearance
        })
    }

    private var navBarCapsule: Binding<Bool> {
        Binding(get: { settings.playerBackground.navBarCapsule }, set: {
            var appearance = settings.playerBackground
            appearance.navBarCapsule = $0
            settings.playerBackground = appearance
        })
    }

    private var controlColorStyle: Binding<PlayerControlColorStyle> {
        Binding(get: { settings.playerBackground.controlColorStyle }, set: {
            var appearance = settings.playerBackground
            appearance.controlColorStyle = $0
            settings.playerBackground = appearance
        })
    }

    private var dominantColor: Color {
        if player.state.currentSong != nil {
            return Color(argb: previewPalette.artworkDominant)
        }
        return Color(red: 0.72, green: 0.36, blue: 0.34)
    }

    var body: some View {
        let appearance = settings.playerBackground
        let blurActive = appearance.gradientStyle == .frostedArtwork || appearance.details > 0
        VStack(spacing: 0) {
            pinnedPreviewHeader(appearance: appearance)
            Rectangle()
                .fill(palette.outline.opacity(0.35))
                .frame(height: 0.5)
            ScrollView {
                VStack(spacing: 24) {
                    SettingsGroup(L(PlayerBackgroundControls.blurStyleSection)) {
                        ForEach(Array(PlayerGradientStyle.allCases.enumerated()), id: \.element.id) { index, style in
                            if index > 0 { Divider().padding(.leading, 68) }
                            SettingsChoice(
                                title: L(style.label),
                                subtitle: L(style.description),
                                selected: appearance.gradientStyle == style,
                                choose: {
                                    var updated = settings.playerBackground
                                    updated.gradientStyle = style
                                    settings.playerBackground = updated
                                }
                            ) {
                                PlayerBackgroundStyleSwatch(style: style, dominant: dominantColor)
                            }
                            .accessibilityIdentifier("settingsPlayerGradientStyle.\(style.rawValue)")
                        }
                    }
                    .accessibilityIdentifier("settingsPlayerGradientStyle")

                    SettingsGroup(L(PlayerBackgroundControls.controlsSection)) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Toggle(L(PlayerBackgroundControls.navBarCapsule), isOn: navBarCapsule)
                                .accessibilityIdentifier("settingsPlayerNavBarCapsule")
                            Text(L(PlayerBackgroundControls.navBarCapsuleDescription))
                                .font(.footnote)
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        .padding(Spacing.lg)
                        Divider().padding(.leading, Spacing.lg)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(L(PlayerBackgroundControls.controlColorStyle))
                                .font(.body)
                                .foregroundStyle(palette.onSurface)
                            Picker(L(PlayerBackgroundControls.controlColorStyle), selection: controlColorStyle) {
                                ForEach(PlayerControlColorStyle.allCases) { style in
                                    Text(L(style.label)).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("settingsPlayerControlColorStyle")
                            Text(L(PlayerBackgroundControls.controlColorStyleDescription))
                                .font(.caption)
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        .padding(Spacing.lg)
                        Divider().padding(.leading, Spacing.lg)
                        sliderRow(
                            L(PlayerBackgroundControls.buttonOpacity),
                            description: L(PlayerBackgroundControls.buttonOpacityDescription),
                            key: \.buttonOpacity,
                            range: PlayerBackgroundControls.unitRange
                        )
                    }

                    SettingsGroup(L(PlayerBackgroundControls.fineTuningSection)) {
                        sliderRow(
                            L(PlayerBackgroundControls.fade),
                            description: L(PlayerBackgroundControls.fadeDescription),
                            key: \.fadeStart,
                            range: PlayerBackgroundControls.unitRange
                        )
                        Divider().padding(.leading, Spacing.lg)
                        sliderRow(
                            L(PlayerBackgroundControls.blur),
                            description: blurActive
                                ? L(PlayerBackgroundControls.blurDescription)
                                : L("Increase Background details above 0% or use Frosted artwork to adjust blur."),
                            key: \.blur,
                            range: PlayerBackgroundControls.blurRange,
                            percent: false
                        )
                        .opacity(blurActive ? 1 : 0.48)
                        .disabled(!blurActive)
                        Divider().padding(.leading, Spacing.lg)
                        sliderRow(
                            L(PlayerBackgroundControls.details),
                            description: L(PlayerBackgroundControls.detailsDescription),
                            key: \.details,
                            range: PlayerBackgroundControls.unitRange
                        )
                        Divider().padding(.leading, Spacing.lg)
                        sliderRow(
                            L(PlayerBackgroundControls.intensity),
                            description: L(PlayerBackgroundControls.intensityDescription),
                            key: \.intensity,
                            range: PlayerBackgroundControls.unitRange
                        )
                        Divider().padding(.leading, Spacing.lg)
                        sliderRow(
                            L(PlayerBackgroundControls.saturation),
                            description: L(PlayerBackgroundControls.saturationDescription),
                            key: \.saturation,
                            range: PlayerBackgroundControls.saturationRange
                        )
                        Divider().padding(.leading, Spacing.lg)
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            sliderContent(
                                L(PlayerBackgroundControls.gradient),
                                description: L(PlayerBackgroundControls.gradientDescription),
                                key: \.gradient,
                                range: PlayerBackgroundControls.unitRange,
                                percent: true
                            )
                            ColorPicker(L(PlayerBackgroundControls.gradientColor), selection: gradientColor, supportsOpacity: false)
                        }
                        .padding(Spacing.lg)
                    }

                    SettingsGroup("") {
                        Button {
                            settings.playerBackground = PlayerBackgroundSettings()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text(L(PlayerBackgroundControls.reset))
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.primary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
                .padding(.bottom, AppNavigationMetrics.reservedHeight + Spacing.lg)
            }
        }
        .modifier(ToolPageAppearance())
        .navigationTitle(L(PlayerBackgroundControls.title))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: player.state.currentSong?.url) {
            guard let url = player.state.currentSong?.url else { return }
            let sampled = await LyricsPaletteCache.shared.palette(for: url)
            guard !Task.isCancelled else { return }
            previewPalette = sampled
        }
    }

    private func pinnedPreviewHeader(appearance: PlayerBackgroundSettings) -> some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            PlayerBackgroundMiniPreview(
                song: player.state.currentSong,
                dominant: dominantColor,
                appearance: appearance,
                colorScheme: colorScheme,
                glassEnabled: settings.glassEnabled,
                usesArtworkControls: settings.customTheme == nil,
                customPalette: settings.customTheme?.palette
            )
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(L("Live preview"))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.primary)
                Text(L(appearance.gradientStyle.label))
                    .font(.headline)
                    .foregroundStyle(palette.onSurface)
                Text(L(appearance.gradientStyle.description))
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    previewMetric(L(PlayerBackgroundControls.controlColorStyle), L(appearance.controlColorStyle.label))
                    previewMetric(L(PlayerBackgroundControls.buttonOpacity), "\(Int(appearance.buttonOpacity * 100))%")
                    previewMetric(L(PlayerBackgroundControls.navBarCapsule), appearance.navBarCapsule ? L("On") : L("Off"))
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(palette.background)
    }

    private func previewMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.onSurfaceVariant)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.onSurface)
        }
    }

    private func sliderRow(
        _ title: String,
        description: String,
        key: WritableKeyPath<PlayerBackgroundSettings, Double>,
        range: ClosedRange<Double>,
        percent: Bool = true
    ) -> some View {
        sliderContent(title, description: description, key: key, range: range, percent: percent)
            .padding(Spacing.lg)
    }

    private func sliderContent(
        _ title: String,
        description: String,
        key: WritableKeyPath<PlayerBackgroundSettings, Double>,
        range: ClosedRange<Double>,
        percent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LabeledContent(title, value: percent ? "\(Int(settings.playerBackground[keyPath: key] * 100))%" : "\(Int(settings.playerBackground[keyPath: key]))")
            Slider(value: value(key), in: range).accessibilityLabel(title)
            Text(description)
                .font(.caption)
                .foregroundStyle(palette.onSurfaceVariant)
        }
    }
}

private struct PlayerBackgroundStyleSwatch: View {
    let style: PlayerGradientStyle
    let dominant: Color

    var body: some View {
        switch style {
        case .classic:
            Circle()
                .fill(LinearGradient(colors: [dominant, Color(red: 0.10, green: 0.06, blue: 0.06)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        case .deepChromatic:
            let stops = PlayerBackdropPalette.deepStops(for: dominant)
            Circle()
                .fill(LinearGradient(colors: [stops.top, stops.mid, stops.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
        case .frostedArtwork:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [dominant.opacity(0.95), dominant.opacity(0.55), Color(red: 0.16, green: 0.12, blue: 0.14)],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 24
                    )
                )
                .overlay {
                    Image(systemName: "aqi.medium")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.24), lineWidth: 1))
        }
    }
}

private struct PlayerBackgroundMiniPreview: View {
    let song: Song?
    let dominant: Color
    let appearance: PlayerBackgroundSettings
    let colorScheme: ColorScheme
    let glassEnabled: Bool
    let usesArtworkControls: Bool
    let customPalette: AppPalette?

    private var controlColors: PlayerBackdropPalette.ControlColors? {
        guard usesArtworkControls else { return nil }
        return PlayerBackdropPalette.controlColors(
            for: dominant,
            style: appearance.gradientStyle,
            scheme: colorScheme,
            colorStyle: appearance.controlColorStyle
        )
    }

    private var circleOpacity: Double {
        appearance.buttonOpacity.clamped(0, 1)
    }

    private var buttonFill: Color {
        let base: Color = controlColors?.buttonFill ?? customPalette?.filledButton ?? .black
        return base.opacity(circleOpacity)
    }

    private var buttonIcon: Color {
        if circleOpacity < 0.35 {
            return controlColors?.accentInk ?? .white
        }
        if let controlColors { return controlColors.buttonIcon }
        if let customPalette { return customPalette.onFilledButton }
        return .white
    }

    private var navIconColor: Color {
        if let controlColors {
            let useOpaqueCapsuleInk = appearance.navBarCapsule && !glassEnabled
            return useOpaqueCapsuleInk ? controlColors.navIcon : controlColors.accentInk.opacity(0.85)
        }
        return .white.opacity(0.88)
    }

    private var navCapsuleFill: Color {
        let base = controlColors?.navCapsule ?? Color.black.opacity(0.55)
        guard glassEnabled else { return base }
        return base.opacity(colorScheme == .light ? 0.24 : 0.36)
    }

    private var accentInk: Color {
        controlColors?.accentInk ?? .white
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PlayerFullBleedBackground(
                dominant: dominant,
                appearance: appearance,
                showsStatusProtection: false,
                artworkHeightFraction: 0.56
            ) {
                if let song {
                    SongArtworkView(song: song, maxPixels: 500)
                } else {
                    sampleArtwork
                }
            }
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                VStack(spacing: 1) {
                    Text(song?.title ?? L("Live preview"))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song?.artist ?? "amp")
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)

                // Mini waveform + 5 transport controls
                ZStack {
                    HStack(spacing: 1.8) {
                        ForEach(Array([0.35, 0.72, 0.55, 0.92, 0.64, 0.48, 0.85, 0.96, 0.60, 0.78, 0.42, 0.68, 0.50, 0.80, 0.36].enumerated()), id: \.offset) { idx, level in
                            Capsule()
                                .fill(accentInk.opacity(idx < 7 ? 0.34 : 0.72))
                                .frame(width: 2.2, height: CGFloat(level) * 24)
                        }
                    }
                    HStack(spacing: 3) {
                        Circle()
                            .fill(buttonFill)
                            .frame(width: 11, height: 11)
                            .overlay {
                                Image(systemName: "arrowtriangle.left.fill")
                                    .font(.system(size: 4.5, weight: .black))
                                    .foregroundStyle(buttonIcon)
                            }
                        Circle()
                            .fill(buttonFill)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 6.5, weight: .black))
                                    .foregroundStyle(buttonIcon)
                            }
                        Circle()
                            .fill(buttonFill)
                            .frame(width: 23, height: 23)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9.5, weight: .black))
                                    .foregroundStyle(buttonIcon)
                            }
                        Circle()
                            .fill(buttonFill)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 6.5, weight: .black))
                                    .foregroundStyle(buttonIcon)
                            }
                        Circle()
                            .fill(buttonFill)
                            .frame(width: 11, height: 11)
                            .overlay {
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 4.5, weight: .black))
                                    .foregroundStyle(buttonIcon)
                            }
                    }
                }
                .frame(height: 28)

                Text("FLAC · 44.1 KHZ")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(accentInk.opacity(0.80))
                    .padding(.bottom, appearance.navBarCapsule ? 2 : 0)

                // Mini 4-icon bottom navigation bar with live contour capsule
                HStack {
                    PlayerLibraryGlyph().scaleEffect(0.28).frame(width: 14, height: 14)
                    Spacer()
                    PlayerEqualizerGlyph().scaleEffect(0.28).frame(width: 14, height: 14)
                    Spacer()
                    PlayerSearchGlyph().scaleEffect(0.28).frame(width: 14, height: 14)
                    Spacer()
                    PlayerQueueGlyph().scaleEffect(0.28).frame(width: 14, height: 14)
                }
                .foregroundStyle(navIconColor)
                .padding(.horizontal, 12)
                .frame(height: 18)
                .background {
                    if appearance.navBarCapsule {
                        Capsule()
                            .fill(navCapsuleFill)
                            .overlay {
                                if glassEnabled {
                                    Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                                }
                            }
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.bottom, 7)
            }
        }
        .frame(width: 124, height: 204)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    private var sampleArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.56, blue: 0.48),
                    Color(red: 0.68, green: 0.28, blue: 0.34),
                    Color(red: 0.30, green: 0.16, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: .center, startRadius: 2, endRadius: 56))
                .offset(x: -18, y: -22)
            Circle()
                .fill(Color(red: 0.96, green: 0.72, blue: 0.62).opacity(0.45))
                .frame(width: 72, height: 72)
                .offset(x: 24, y: 12)
        }
    }
}

private struct VisualizerSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.playbackPalette) private var playbackPalette
    @State private var showingVisualizer = false

    var body: some View {
        @Bindable var settings = settings
        SettingsPage {
            SettingsGroup(L("Style")) {
                ForEach(VisualizerMode.allCases, id: \.self) { mode in
                    SettingsChoice(title: L(mode.label), subtitle: L(description(mode)), selected: settings.visualizer.mode == mode,
                                   choose: { settings.visualizer.mode = mode }) {
                        SettingsIcon(symbol: mode == .circularSpectrum ? "circle.dotted" : mode == .spectrumBars ? "chart.bar.fill" : "waveform")
                    }
                }
            }
            SettingsGroup(L("Response")) {
                SettingsValueRow(title: L("Sensitivity"), icon: "waveform.path") {
                    Picker(L("Sensitivity"), selection: $settings.visualizer.sensitivity) {
                        Text(L("Low")).tag(VisualizerSensitivity.low)
                        Text(L("Normal")).tag(VisualizerSensitivity.normal)
                        Text(L("High")).tag(VisualizerSensitivity.high)
                    }
                }
                SettingsValueRow(title: L("Smoothing"), icon: "slider.horizontal.3") {
                    Picker(L("Smoothing"), selection: $settings.visualizer.smoothing) {
                        Text(L("Responsive")).tag(VisualizerSmoothing.responsive)
                        Text(L("Balanced")).tag(VisualizerSmoothing.balanced)
                        Text(L("Smooth")).tag(VisualizerSmoothing.smooth)
                    }
                }
                SettingsValueRow(title: L("Reduce motion"), icon: "figure.walk.motion") {
                    Toggle(L("Reduce motion"), isOn: $settings.visualizer.reduceMotion)
                }
            }
            SettingsGroup(L("Now Playing")) {
                Button { showingVisualizer = true } label: {
                    Label(L("Open visualizer"), systemImage: "waveform")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.lg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingVisualizer) {
            VisualizerView().environment(\.palette, playbackPalette).tint(playbackPalette.primary)
        }
        .navigationTitle(L("Visualizer"))
    }

    private func description(_ mode: VisualizerMode) -> String {
        switch mode {
        case .spectrumBars: "Frequency bars that follow the music"
        case .circularSpectrum: "A spectrum around the album artwork"
        case .oscilloscope: "A flowing waveform of the audio"
        }
    }
}

private struct LibrarySettingsView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage(SongAlphabetPreferences.hapticsKey) private var alphabetHaptics = SongAlphabetPreferences.defaultHaptics

    var body: some View {
        SettingsPage {
            SettingsGroup(L("Music folder")) {
                HStack(spacing: Spacing.lg) {
                    SettingsIcon(symbol: "folder.fill")
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(L("On My iPhone › amp")).font(.headline)
                        Text(L("Add music with Files, the + button, or Wi-Fi Transfer.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(Spacing.lg)
            }
            SettingsGroup(L("Navigation")) {
                SettingsValueRow(title: L(SongAlphabetPreferences.hapticsTitle), icon: "hand.tap") {
                    Toggle(L(SongAlphabetPreferences.hapticsTitle), isOn: $alphabetHaptics)
                }
                Text(L(SongAlphabetPreferences.hapticsDescription))
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], Spacing.lg)
            }
            SettingsGroup(L("Scan")) {
                Button { library.scan() } label: {
                    HStack(spacing: Spacing.lg) {
                        SettingsIcon(symbol: "arrow.clockwise")
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(L("Rescan library now")).font(.headline)
                            Text(L("Find new, changed and removed music")).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(Spacing.lg)
                }
                .buttonStyle(.plain)
                .disabled(library.isScanning)
                if let progress = library.scanProgress {
                    HStack(spacing: Spacing.md) {
                        ProgressView()
                        Text(L("Scanning %d of %d…", progress.scanned, progress.total))
                            .foregroundStyle(.secondary)
                    }.padding(Spacing.lg)
                }
            }
            SettingsGroup(L("Your collection")) {
                SettingsValueRow(title: L("Songs"), icon: "music.note") { Text("\(library.songs.count)").monospacedDigit() }
                SettingsValueRow(title: L("Albums"), icon: "square.stack") { Text("\(library.albums.count)").monospacedDigit() }
                SettingsValueRow(title: L("Artists"), icon: "person.2") { Text("\(library.artists.count)").monospacedDigit() }
            }
        }
        .navigationTitle(L("Music Library"))
    }
}

private struct MetadataSettingsView: View {
    var body: some View {
        SettingsPage {
            SettingsGroup(L("Tags & cover art")) {
                SettingsLink(L("Auto Fix Tags"), subtitle: L("Correct tags and fill in missing details"), icon: "wand.and.stars", tool: .autoFixTags)
                SettingsLink(L("Artwork Fetcher"), subtitle: L("Find album covers or change artist photos"), icon: "photo.on.rectangle.angled", tool: .artworkFetcher)
                // The tool exists only in the animated-art branch; never offer a dead destination.
                if let motion = Tool(rawValue: "animatedArtwork"), Tool.available.contains(motion) {
                    SettingsLink(L(motion.label), subtitle: L("Manage your downloaded album covers"), icon: motion.icon, tool: motion)
                }
            }
            Text(L("Metadata and artwork searches use keyless iTunes Search, MusicBrainz, Deezer, Wikidata and Wikimedia Commons. No API keys are needed."))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle(L("Metadata & Artwork"))
    }
}

private struct AboutSettingsView: View {
    @Environment(\.colorScheme) private var themeScheme
    @State private var showingIntroduction = false
    var body: some View {
        SettingsPage {
            SettingsGroup("amp") {
                HStack(spacing: Spacing.lg) {
                    Image("AmpLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("amp").font(.title3.weight(.semibold))
                        Text(L("Your music, on your iPhone.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.sm)
                }.padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                LabeledContent(L("Version"), value: AppBuildVersion.version(in: Bundle.main.infoDictionary ?? [:])).padding(Spacing.lg)
                LabeledContent(L("Build"), value: AppBuildVersion.build(in: Bundle.main.infoDictionary ?? [:])).padding(Spacing.lg)
                LabeledContent(L("Release"), value: AppBuildVersion.release(in: Bundle.main.infoDictionary ?? [:]) ?? L("Development")).padding(Spacing.lg)
                Text(L("amp plays your local music with full-screen artwork, playlists, synced lyrics, an equalizer, Transition Studio and Home Screen widgets."))
                    .font(.footnote).foregroundStyle(.secondary).padding([.horizontal, .bottom], Spacing.lg)
            }
            PlayerWidgetStatusSettings()
            SettingsGroup(L("Privacy")) {
                Label(L("Music stays on your iPhone"), systemImage: "iphone").padding(Spacing.lg)
                Text(L("Your music files and library index stay on this device. Online lyrics, metadata and artwork searches use the song or artist details needed for the request."))
                    .font(.footnote).foregroundStyle(.secondary).padding([.horizontal, .bottom], Spacing.lg)
            }
            SettingsGroup(L("Project")) {
                NavigationLink(value: Route.settingsPage(.imageCredits)) {
                    SettingsActionLabel(title: L("Image credits"), icon: "photo.on.rectangle")
                }
                Divider().padding(.leading, Spacing.lg)
                Button { showingIntroduction = true } label: {
                    SettingsActionLabel(title: L("Introduction & tool guide"), icon: "book.closed")
                }
                Divider().padding(.leading, Spacing.lg)
                Link(destination: URL(string: "https://github.com/SRJW/amp")!) {
                    SettingsActionLabel(title: L("Source code on GitHub"), icon: "chevron.left.forwardslash.chevron.right", accessory: "arrow.up.right")
                }
                Divider().padding(.leading, Spacing.lg)
                Link(destination: URL(string: "https://github.com/SRJW/amp/releases")!) {
                    SettingsActionLabel(title: L("Download amp releases"), icon: "shippingbox", accessory: "arrow.up.right")
                }
                Divider().padding(.leading, Spacing.lg)
                Link(destination: URL(string: "https://github.com/SRJW/amp/issues")!) {
                    SettingsActionLabel(title: L("Report an amp issue"), icon: "bubble.left", accessory: "arrow.up.right")
                }
                Text("amp is maintained in SRJW/amp. Based on Erhu for iOS by Mohammed Azeemulla Khan, with original Android contributions by Lochan Thakke and Kshitij Kekunnaya. Original licenses and image credits remain applicable.")
                    .font(.footnote).foregroundStyle(.secondary).padding(Spacing.lg)
            }
            SettingsGroup(L("Updates")) { ReleaseCheckView() }
        }
        .navigationTitle(L("About amp"))
        .sheet(isPresented: $showingIntroduction) { IntroductionView().preferredColorScheme(themeScheme) }
    }
}

private struct PlayerWidgetStatusSettings: View {
    @Environment(PlayerController.self) private var player
    @State private var sharedTitle = ""
    @State private var error: String?

    var body: some View {
        SettingsGroup(L("Home Screen widget")) {
            Text(L("Touch and hold your Home Screen → Edit → Add Widget → amp. Swipe to choose amp · Cover focus, amp · Compact or amp · Immersive. Each style adapts to your artwork's colors and lets you control playback without opening amp."))
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, Spacing.lg).padding(.top, Spacing.lg)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let storage = PlayerWidgetStorage.shared {
                    Label(L("Shared storage available"), systemImage: "checkmark.circle")
                    Text(L("Last shared song: %@", sharedTitle)).font(.subheadline)
                    Text(storage.group).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Label(L("Shared storage unavailable"), systemImage: "exclamationmark.triangle")
                    Text(L("When signing in FlareStore, preserve the widget extension and a matching App Group for both targets. Without that permission, iOS prevents the widget from reading the current song."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button(L("Refresh widget")) {
                    player.refreshSystemPlayback()
                    readStatus()
                }.buttonStyle(.bordered)
            }.padding(Spacing.lg)
        }
        .onAppear { readStatus() }
    }

    private func readStatus() {
        sharedTitle = PlayerWidgetSnapshot.load().title
        error = PlayerWidgetPublisher.lastError
    }
}

private enum TransitionStyleOption: String, CaseIterable, Identifiable {
    case smartBlend
    case crossfade
    case bassSwap

    var id: String { rawValue }

    var preset: TransitionPreset {
        switch self {
        case .smartBlend: .blend
        case .crossfade: .fade
        case .bassSwap: .bassSwap
        }
    }

    var titleKey: String {
        switch self {
        case .smartBlend: "Smart Blend"
        case .crossfade: "Crossfade"
        case .bassSwap: "Bass Swap"
        }
    }

    var descriptionKey: String {
        switch self {
        case .smartBlend: "Smooth DJ-style overlap with bass swap and filter sweeps between tracks."
        case .crossfade: "Simple song transitions from one to the next for a set duration."
        case .bassSwap: "Swaps low frequencies cleanly at the midpoint so beats don't clash."
        }
    }

    static func matching(_ spec: TransitionSpec?) -> TransitionStyleOption {
        guard let spec else { return .crossfade }
        switch spec.preset {
        case .blend: return .smartBlend
        case .bassSwap: return .bassSwap
        default: return .crossfade
        }
    }
}

struct PlaybackSettingsView: View {
    @Environment(TransitionSettingsStore.self) private var transitions
    @Environment(\.palette) private var palette
    @AppStorage(PlaybackPreferences.waveformKey) private var waveformMode = PlaybackPreferences.defaultWaveform

    private var isTransitionsEnabled: Bool {
        transitions.config.global.masterEnabled && transitions.config.global.defaultChoice.specOrNil != nil
    }

    private var transitionsEnabledBinding: Binding<Bool> {
        Binding(get: {
            isTransitionsEnabled
        }, set: { enabled in
            var global = transitions.config.global
            // Keep masterEnabled true so per-album / per-playlist Transition Studio rules remain active.
            global.masterEnabled = true
            if enabled {
                if global.defaultChoice.specOrNil == nil {
                    var spec = TransitionSpec.preset(.fade)
                    spec.durationMs = 4_000
                    global.defaultChoice = .custom(spec)
                }
            } else {
                global.defaultChoice = .off
            }
            transitions.setGlobal(global)
        })
    }

    private var selectedStyle: TransitionStyleOption {
        TransitionStyleOption.matching(transitions.config.global.defaultChoice.specOrNil)
    }

    private var durationSeconds: Int {
        let ms = transitions.config.global.defaultChoice.specOrNil?.durationMs ?? 4_000
        return max(1, min(12, Int((Double(ms) / 1000.0).rounded())))
    }

    private var durationBinding: Binding<Double> {
        Binding(get: {
            Double(durationSeconds)
        }, set: { seconds in
            var global = transitions.config.global
            let base = global.defaultChoice.specOrNil ?? TransitionSpec.preset(selectedStyle.preset)
            var spec = base
            spec.durationMs = Int(seconds.rounded()) * 1000
            global.defaultChoice = .custom(spec)
            global.masterEnabled = true
            transitions.setGlobal(global)
        })
    }

    private func selectStyle(_ style: TransitionStyleOption) {
        var global = transitions.config.global
        var base = global.defaultChoice.specOrNil ?? TransitionSpec()
        if global.defaultChoice.specOrNil == nil {
            base.durationMs = 4_000
        }
        global.defaultChoice = .custom(TransitionSpec.preset(style.preset, base: base))
        global.masterEnabled = true
        transitions.setGlobal(global)
    }

    var body: some View {
        SettingsPage {
            // Top master toggle card + footer caption (matching Song Transitions layout)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle(L("Song Transitions"), isOn: transitionsEnabledBinding)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 14)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityIdentifier("songTransitionsToggle")
                Text(L("Beginnings and endings of songs blend together seamlessly. Albums and playlists with Transition Studio rules keep their own settings."))
                    .font(.footnote)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.horizontal, Spacing.lg)
            }

            // Transition Style card + footer caption
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SettingsGroup(L("Transition Style")) {
                    ForEach(Array(TransitionStyleOption.allCases.enumerated()), id: \.element.id) { index, style in
                        if index > 0 {
                            Divider().padding(.leading, 68)
                        }
                        transitionStyleRow(style)
                    }
                }
                Text(L("Open Transition Studio inside any album or playlist to customize curves, filters, and cue points."))
                    .font(.footnote)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.horizontal, Spacing.lg)
            }
            .opacity(isTransitionsEnabled ? 1 : 0.48)
            .disabled(!isTransitionsEnabled)

            // Crossfade Duration card with 1s–12s slider and tick dots
            SettingsGroup(L("Crossfade Duration")) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(durationSeconds == 1 ? L("1 second") : L("%d seconds", durationSeconds))
                        .font(.subheadline)
                        .foregroundStyle(palette.onSurfaceVariant)
                        .monospacedDigit()
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Text(L("1s"))
                            .font(.subheadline)
                            .foregroundStyle(palette.onSurfaceVariant)
                            .monospacedDigit()
                            .padding(.top, 6)
                        VStack(spacing: 4) {
                            Slider(value: durationBinding, in: PlaybackPreferences.crossfadeRange, step: PlaybackPreferences.crossfadeStep)
                                .accessibilityLabel(L("Crossfade duration"))
                                .accessibilityIdentifier("crossfadeDuration")
                            HStack(spacing: 0) {
                                ForEach(1...12, id: \.self) { tick in
                                    Circle()
                                        .fill(palette.onSurfaceVariant.opacity(tick == durationSeconds ? 0.85 : 0.32))
                                        .frame(width: 3, height: 3)
                                    if tick < 12 {
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                        Text(L("12s"))
                            .font(.subheadline)
                            .foregroundStyle(palette.onSurfaceVariant)
                            .monospacedDigit()
                            .padding(.top, 6)
                    }
                }
                .padding(Spacing.lg)
            }
            .opacity(isTransitionsEnabled ? 1 : 0.48)
            .disabled(!isTransitionsEnabled)

            // Granular automatic / manual transition rules
            SettingsGroup(L("When to transition")) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Picker(L("Automatic song changes"), selection: Binding(
                        get: { transitions.config.global.automaticMode ?? .all },
                        set: { mode in var global = transitions.config.global; global.automaticMode = mode; transitions.setGlobal(global) })) {
                        ForEach(AutomaticCrossfadeMode.allCases, id: \.self) { Text(L($0.label)).tag($0) }
                    }
                    Divider()
                    Picker(L("Manual song changes"), selection: Binding(
                        get: { transitions.config.global.manualMode ?? (transitions.config.global.defaultChoice.specOrNil == nil ? .off : .custom) },
                        set: { mode in
                            var global = transitions.config.global
                            global.manualMode = mode
                            if mode == .custom, global.defaultChoice.specOrNil == nil {
                                if global.automaticMode == nil { global.automaticMode = .off }
                                var spec = TransitionSpec()
                                spec.durationMs = 4_000
                                global.defaultChoice = .custom(spec)
                            }
                            if mode != .off { global.masterEnabled = true }
                            transitions.setGlobal(global)
                        })) {
                        ForEach(ManualCrossfadeMode.allCases.filter { $0 != .linked }, id: \.self) { Text(L($0.label)).tag($0) }
                    }
                    if transitions.config.global.manualMode == .short {
                        Divider()
                        LabeledContent(L("Short manual crossfade"), value: "\(transitions.config.global.shortManualDurationMs ?? 500) ms")
                        Slider(value: Binding(
                            get: { Double(transitions.config.global.shortManualDurationMs ?? 500) },
                            set: { duration in
                                var global = transitions.config.global
                                global.shortManualDurationMs = Int(duration)
                                transitions.setGlobal(global)
                            }), in: 500...2_000, step: 100)
                            .accessibilityLabel(L("Short manual crossfade duration"))
                    }
                    Divider()
                    Button(L("Restore crossfade defaults")) { transitions.setGlobal(GlobalTransitionSettings()) }
                        .foregroundStyle(palette.primary)
                        .frame(minHeight: 36)
                }
                .padding(Spacing.lg)
            }

            SettingsGroup(L("Waveform")) {
                Picker(L("Mode"), selection: $waveformMode) {
                    ForEach(PlayerWaveformMode.allCases) { mode in Text(L(mode.label)).tag(mode.rawValue) }
                }
                .pickerStyle(.inline)
                .padding(Spacing.lg)
                .accessibilityIdentifier("waveformMode")
            }
        }
        .navigationTitle(L("Song Transitions"))
    }

    private func transitionStyleRow(_ style: TransitionStyleOption) -> some View {
        let isSelected = selectedStyle == style
        return Button { selectStyle(style) } label: {
            HStack(spacing: 14) {
                transitionStyleBadge(style, selected: isSelected)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(style.titleKey))
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.onSurface)
                    Text(L(style.descriptionKey))
                        .font(.subheadline)
                        .foregroundStyle(palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.primary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier("transitionStyle.\(style.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func transitionStyleBadge(_ style: TransitionStyleOption, selected: Bool) -> some View {
        let fill = selected ? palette.onSurface.opacity(0.75) : palette.onSurface.opacity(0.28)
        let glyphColor = selected ? palette.surface : palette.onSurface.opacity(0.9)
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
            switch style {
            case .smartBlend:
                ZStack {
                    Circle()
                        .fill(glyphColor.opacity(0.5))
                        .frame(width: 14, height: 14)
                        .offset(x: -5)
                    Circle()
                        .fill(glyphColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().fill(fill).frame(width: 4, height: 4))
                        .offset(x: 5)
                }
            case .crossfade:
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(glyphColor)
            case .bassSwap:
                Image(systemName: "waveform.path")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(glyphColor)
            }
        }
        .frame(width: 36, height: 36)
    }
}
