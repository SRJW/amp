import SwiftUI

struct ReleaseCheckView: View {
    @State private var checker = ReleaseChecker.shared
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                switch checker.state {
                case .idle:
                    Text(L("Check GitHub Releases for a newer build."))
                        .foregroundStyle(palette.onSurface)
                case .checking:
                    ProgressView(L("Checking releases…"))
                        .foregroundStyle(palette.onSurface)
                        .tint(palette.primary)
                case .current:
                    Label(L("You have the latest published release for this variant"), systemImage: "checkmark.circle")
                        .foregroundStyle(palette.onSurface)
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(palette.onSurfaceVariant)
                case .available(let release):
                    Label("\(release.tag_name) \(L("is available"))", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .foregroundStyle(palette.onSurface)
                    if let notes = release.body?.nonBlank {
                        Text(LocalizedStringKey(notes))
                            .font(.footnote)
                            .foregroundStyle(palette.onSurface)
                            .textSelection(.enabled)
                    }
                    Text(L("Install the IPA using SideStore or AltStore. amp cannot install itself."))
                        .font(.footnote)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            if case .available(let release) = checker.state {
                Divider().padding(.leading, Spacing.lg)
                Link(destination: release.html_url) {
                    SettingsActionLabel(title: L("Release notes"), icon: "doc.text", accessory: "arrow.up.right")
                }
                if let url = release.download(animated: BuildVariant.animated) {
                    Divider().padding(.leading, Spacing.lg)
                    Link(destination: url) {
                        SettingsActionLabel(
                            title: L("Download IPA"),
                            icon: "arrow.down.circle",
                            accessory: "arrow.up.right"
                        )
                    }
                }
            }
            Divider().padding(.leading, Spacing.lg)
            Button { Task { await checker.check(manual: true) } } label: {
                SettingsActionLabel(title: L("Check for updates"), icon: "arrow.clockwise")
            }.disabled(checker.state == .checking)
            Divider().padding(.leading, Spacing.lg)
            Link(destination: URL(string: "https://github.com/SRJW/amp/releases")!) {
                SettingsActionLabel(title: L("All releases"), icon: "shippingbox", accessory: "arrow.up.right")
            }
            if let checkedAt = checker.checkedAt {
                Text("\(L("Last checked")) \(checkedAt.formatted())")
                    .font(.caption)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding([.horizontal, .bottom], Spacing.lg)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
