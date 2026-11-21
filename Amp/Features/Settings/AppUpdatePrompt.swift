import SwiftUI

struct AppUpdatePrompt: View {
    let release: AppRelease
    let checker: ReleaseChecker
    @Environment(\.openURL) private var openURL
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Label(L("An update is available"), systemImage: "arrow.down.circle.fill")
                        .font(.title2.bold())
                        .foregroundStyle(palette.onSurface)
                    Text(release.name?.nonBlank ?? release.tag_name)
                        .font(.headline)
                        .foregroundStyle(palette.onSurface)
                    Text(release.tag_name)
                        .font(.caption)
                        .foregroundStyle(palette.onSurfaceVariant)
                    if let published = release.published_at, let date = ISO8601DateFormatter().date(from: published) {
                        Text("\(L("Released")) \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    Text(LocalizedStringKey(release.body?.nonBlank ?? L("A newer version of amp is ready to download.")))
                        .foregroundStyle(palette.onSurface)
                        .textSelection(.enabled)
                    Link(L("View release on GitHub"), destination: release.html_url)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.primary)
                    Text(L("Download the IPA for your current artwork variant and install it with your usual iOS installer."))
                        .font(.footnote)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
            }
            .modifier(ToolPageAppearance())
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: Spacing.sm) {
                    if let url = release.download(animated: BuildVariant.animated) {
                        Button { openURL(url); checker.dismissPrompt() } label: {
                            Label(L("Download update"), systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(palette.onFilledButton)
                        }
                        .modifier(PaletteFilledButton())
                        .tint(palette.filledButton)
                    }
                    Button { checker.dismissPrompt() } label: {
                        Text(L("Skip for now"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.onSurface)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { checker.dismissPrompt(ignore: true) } label: {
                        Text(L("Do not show this version again"))
                            .font(.footnote)
                            .foregroundStyle(palette.onSurfaceVariant)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .controlSize(.large)
                .padding(Spacing.lg)
                .background(palette.surface)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.outline.opacity(0.35)).frame(height: 0.5)
                }
            }
            .navigationTitle(L("amp update"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(palette.background)
    }
}
