import SwiftUI

private enum SongsControlSize {
    static let hero: CGFloat = 48
    static let tool: CGFloat = 44
    static let icon: CGFloat = 23
    static let gap: CGFloat = 4
}

struct SongsPlayButton: View {
    let title: String
    let symbol: String
    var filled = false
    let action: () -> Void
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Group {
                if filled {
                    Label(title, systemImage: symbol)
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: SongsControlSize.hero)
                        .foregroundStyle(palette.onFilledButton)
                        .background(Capsule().fill(palette.filledButton))
                } else {
                    Label(title, systemImage: symbol)
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: SongsControlSize.hero)
                        .foregroundStyle(palette.onSurface)
                        .glassCapsule(enabled: settings.glassEnabled, interactive: true)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(FloatingControlPressStyle())
        .opacity(enabled ? 1 : 0.4)
    }
}

struct SongsToolLabel: View {
    let title: String
    let symbol: String
    var active = false
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: SongsControlSize.gap) {
            Image(systemName: symbol)
                .font(.system(size: SongsControlSize.icon, weight: .semibold))
                .frame(width: SongsControlSize.tool, height: SongsControlSize.tool)
                .glassCircle(enabled: settings.glassEnabled, interactive: true,
                             tint: active ? palette.primary.opacity(0.28) : nil)
            Text(title).font(.caption).lineLimit(1)
        }
        .foregroundStyle(active ? palette.primary : palette.onSurface)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

struct SongsFilterLabel: View {
    let title: String
    let symbol: String
    var active = false
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: SongsControlSize.gap) {
            Image(systemName: symbol)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(active ? palette.primary : palette.onSurface)
        .glassCapsule(enabled: settings.glassEnabled, interactive: true,
                      tint: active ? palette.primary.opacity(0.26) : nil)
        .contentShape(Capsule())
    }
}
