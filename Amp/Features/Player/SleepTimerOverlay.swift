import SwiftUI
import UIKit

@MainActor
private enum SleepTimerHaptics {
    private static let stepGenerator = UISelectionFeedbackGenerator()
    private static let milestoneGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let confirmGenerator = UINotificationFeedbackGenerator()

    static func step(minutes: Int) {
        if minutes % 30 == 0 {
            milestoneGenerator.prepare()
            milestoneGenerator.impactOccurred(intensity: 0.75)
        } else {
            stepGenerator.prepare()
            stepGenerator.selectionChanged()
        }
    }

    static func toggle() {
        milestoneGenerator.prepare()
        milestoneGenerator.impactOccurred(intensity: 0.55)
    }

    static func confirm() {
        confirmGenerator.prepare()
        confirmGenerator.notificationOccurred(.success)
    }

    static func cancel() {
        milestoneGenerator.prepare()
        milestoneGenerator.impactOccurred(intensity: 0.5)
    }
}

/// Poweramp v3–inspired Sleep Timer card styled natively with AMP's dynamic Now Playing
/// artwork palette (deep chromatic glass, tinted primary pills, and matching ink across Light/Dark/Themes).
struct SleepTimerOverlay: View {
    var dominantColor: Color? = nil
    var controlColors: PlayerBackdropPalette.ControlColors? = nil
    let onDismiss: () -> Void

    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var selectedMinutes: Int = 30
    @State private var playLastSongToEnd: Bool = true
    @State private var appeared = false

    private static let maxMinutes = 120
    private static let stepMinutes = 5

    private struct VisualTokens {
        let surfaceTop: Color
        let surfaceBottom: Color
        let rimTop: Color
        let rimBottom: Color
        let ink: Color
        let secondaryInk: Color
        let primaryFill: Color
        let primaryInk: Color
        let secondaryFill: Color
        let wellFill: Color
        let wellStroke: Color
        let trackFill: Color
        let destructiveFill: Color
        let destructiveInk: Color
        let destructiveStroke: Color
    }

    private var tokens: VisualTokens {
        if let controls = controlColors, let dominantColor, settings.customTheme == nil {
            let stops = PlayerBackdropPalette.deepStops(for: dominantColor)
            let accent = controls.accentInk
            let isMonochrome = settings.playerBackground.controlColorStyle == .monochrome
            let primaryFill: Color
            let primaryInk: Color
            if isMonochrome {
                primaryFill = .white
                primaryInk = Color(red: 0.06, green: 0.06, blue: 0.07)
            } else if colorScheme == .light {
                // Match the exact pastel-tinted transport circles & time pills visible right behind the card.
                primaryFill = controls.buttonFill
                primaryInk = controls.buttonIcon
            } else {
                primaryFill = accent
                primaryInk = stops.bottom
            }
            return VisualTokens(
                surfaceTop: stops.top.opacity(0.90),
                surfaceBottom: stops.bottom.opacity(0.95),
                rimTop: accent.opacity(0.28),
                rimBottom: accent.opacity(0.08),
                ink: accent,
                secondaryInk: accent.opacity(0.66),
                primaryFill: primaryFill,
                primaryInk: primaryInk,
                secondaryFill: accent.opacity(0.12),
                wellFill: accent.opacity(0.08),
                wellStroke: accent.opacity(0.14),
                trackFill: accent.opacity(0.14),
                destructiveFill: Color(red: 0.96, green: 0.34, blue: 0.34).opacity(0.18),
                destructiveInk: Color(red: 1.0, green: 0.52, blue: 0.52),
                destructiveStroke: Color(red: 0.96, green: 0.34, blue: 0.34).opacity(0.32)
            )
        }
        return VisualTokens(
            surfaceTop: palette.surface.opacity(0.96),
            surfaceBottom: palette.background.opacity(0.98),
            rimTop: palette.outline.opacity(0.42),
            rimBottom: palette.outline.opacity(0.16),
            ink: palette.onSurface,
            secondaryInk: palette.onSurfaceVariant,
            primaryFill: palette.primary,
            primaryInk: palette.onPrimary,
            secondaryFill: palette.surfaceVariant,
            wellFill: palette.surfaceVariant.opacity(0.70),
            wellStroke: palette.outline.opacity(0.24),
            trackFill: palette.onSurface.opacity(0.12),
            destructiveFill: Color.red.opacity(0.14),
            destructiveInk: Color.red,
            destructiveStroke: Color.red.opacity(0.28)
        )
    }

    var body: some View {
        let style = tokens
        ZStack {
            // Subtle dim scrim — tapping outside closes cleanly.
            Color.black.opacity(appeared ? 0.34 : 0.0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissAnimated() }

            card(style: style)
                .padding(.horizontal, 20)
                .scaleEffect(appeared || reduceMotion ? 1.0 : 0.94)
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: appeared || reduceMotion ? 0 : 14)
        }
        .onAppear {
            initializeFromPlayer()
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    appeared = true
                }
            }
        }
    }

    private func card(style: VisualTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(alignment: .leading, spacing: 18) {
            header(style: style)
            rulerControl(style: style)
            playLastSongRow(style: style)
            footerButtons(style: style)
        }
        .padding(20)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [style.surfaceTop, style.surfaceBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [style.rimTop, style.rimBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.9
            )
        }
        .shadow(color: .black.opacity(0.36), radius: 28, y: 14)
    }

    private func header(style: VisualTokens) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 11) {
                    Image(systemName: player.sleepTimerActive || selectedMinutes > 0 || playLastSongToEnd ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(style.primaryInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(style.primaryFill))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Sleep timer"))
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(style.ink)
                        Text(subtitleText(now: context.date))
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(style.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(formattedDuration(selectedMinutes, endOfTrack: selectedMinutes == 0 && playLastSongToEnd))
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(style.primaryInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(style.primaryFill))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.16), value: selectedMinutes)
            }
        }
    }

    private func rulerControl(style: VisualTokens) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let fraction = CGFloat(selectedMinutes) / CGFloat(Self.maxMinutes)
                let fillWidth = max(fraction * width, selectedMinutes > 0 ? 12 : 0)
                let stepCount = Self.maxMinutes / Self.stepMinutes

                ZStack(alignment: .leading) {
                    // Recessed tinted track
                    Capsule()
                        .fill(style.trackFill)
                        .frame(height: 16)

                    // Luminous palette-matched active fill bar
                    if selectedMinutes > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [style.primaryFill.opacity(0.78), style.primaryFill],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth, height: 16)
                    }

                    // Poweramp-style vertical tick marks across 0–120 min (every 5 min)
                    HStack(spacing: 0) {
                        ForEach(0...stepCount, id: \.self) { index in
                            let mins = index * Self.stepMinutes
                            let isMajor = mins % 30 == 0
                            let isQuarter = mins % 15 == 0
                            let isCurrent = mins == selectedMinutes && selectedMinutes > 0
                            let isFilled = mins <= selectedMinutes && selectedMinutes > 0
                            Capsule()
                                .fill(
                                    isCurrent
                                        ? style.primaryFill
                                        : (isFilled
                                            ? style.primaryInk.opacity(0.45)
                                            : style.ink.opacity(isMajor ? 0.42 : 0.22))
                                )
                                .frame(
                                    width: isCurrent ? 3.5 : (isMajor ? 1.8 : 1.2),
                                    height: isCurrent ? 30 : (isMajor ? 22 : (isQuarter ? 16 : 11))
                                )
                                .shadow(color: isCurrent ? style.primaryFill.opacity(0.65) : .clear, radius: 6)
                            if index < stepCount {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(width: width, height: 32)
                }
                .frame(width: width, height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clamped = min(max(value.location.x / width, 0), 1)
                            let rawMinutes = Double(clamped) * Double(Self.maxMinutes)
                            let snapped = Int((rawMinutes / Double(Self.stepMinutes)).rounded()) * Self.stepMinutes
                            let bounded = min(max(snapped, 0), Self.maxMinutes)
                            if bounded != selectedMinutes {
                                selectedMinutes = bounded
                                SleepTimerHaptics.step(minutes: bounded)
                            }
                        }
                )
            }
            .frame(height: 36)

            // Milestone labels: 0m · 30m · 1h · 1h 30m · 2h
            HStack {
                Text("0m")
                Spacer()
                Text("30m")
                Spacer()
                Text("1h")
                Spacer()
                Text("1h 30m")
                Spacer()
                Text("2h")
            }
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .foregroundStyle(style.secondaryInk)
        }
    }

    private func playLastSongRow(style: VisualTokens) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                playLastSongToEnd.toggle()
            }
            SleepTimerHaptics.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Play last song to end"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(style.ink)
                    Text(selectedMinutes == 0
                         ? L("Stops when the current track finishes")
                         : L("Finishes the playing song when time expires"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(style.secondaryInk)
                }
                Spacer(minLength: 8)
                // Sleek AMP-tinted capsule toggle matching the player's transport pill aesthetic.
                ZStack(alignment: playLastSongToEnd ? .trailing : .leading) {
                    Capsule()
                        .fill(playLastSongToEnd ? style.primaryFill : style.ink.opacity(0.18))
                        .frame(width: 48, height: 28)
                    Circle()
                        .fill(playLastSongToEnd ? style.primaryInk : style.ink.opacity(0.82))
                        .frame(width: 22, height: 22)
                        .padding(3)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(style.wellFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style.wellStroke, lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(playLastSongToEnd ? L("On") : L("Off"))
    }

    private func footerButtons(style: VisualTokens) -> some View {
        HStack(spacing: 12) {
            if player.sleepTimerActive {
                Button {
                    player.cancelSleepTimer()
                    SleepTimerHaptics.cancel()
                    dismissAnimated()
                } label: {
                    Text(L("Turn off timer"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(style.destructiveInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(style.destructiveFill))
                        .overlay(Capsule().strokeBorder(style.destructiveStroke, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    dismissAnimated()
                } label: {
                    Text(L("Cancel"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(style.ink.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(style.secondaryFill))
                        .overlay(Capsule().strokeBorder(style.wellStroke, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }

            let canApply = selectedMinutes > 0 || playLastSongToEnd
            Button {
                if canApply {
                    player.setSleepTimer(minutes: selectedMinutes, playLastSongToEnd: playLastSongToEnd)
                    SleepTimerHaptics.confirm()
                } else {
                    player.cancelSleepTimer()
                    SleepTimerHaptics.cancel()
                }
                dismissAnimated()
            } label: {
                Text(canApply ? L("Start") : L("OK"))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(style.primaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(style.primaryFill))
            }
            .buttonStyle(.plain)
        }
    }

    private func initializeFromPlayer() {
        playLastSongToEnd = player.sleepTimerPlayLastSongToEnd
        if let deadline = player.sleepTimerDeadline {
            let remainingMinutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
            let snapped = Int((Double(remainingMinutes) / Double(Self.stepMinutes)).rounded()) * Self.stepMinutes
            selectedMinutes = min(max(snapped, Self.stepMinutes), Self.maxMinutes)
        } else if player.sleepTimerEndOfTrack {
            selectedMinutes = 0
            playLastSongToEnd = true
        } else {
            selectedMinutes = min(max(player.sleepTimerConfiguredMinutes, Self.stepMinutes), Self.maxMinutes)
        }
    }

    private func dismissAnimated() {
        if reduceMotion {
            onDismiss()
            return
        }
        withAnimation(.easeOut(duration: 0.20)) {
            appeared = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            onDismiss()
        }
    }

    private func formattedDuration(_ minutes: Int, endOfTrack: Bool) -> String {
        if minutes == 0 {
            return endOfTrack ? L("End of track") : L("Off")
        }
        if minutes < 60 {
            return "\(minutes) min"
        }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }

    private func subtitleText(now: Date) -> String {
        if let deadline = player.sleepTimerDeadline, deadline > now {
            let totalSeconds = max(0, Int(deadline.timeIntervalSince(now)))
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            let remaining = h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%d:%02d", m, s)
            return L("Active: %@ left", remaining)
        }
        if player.sleepTimerEndOfTrack && selectedMinutes == 0 {
            return L("Active: End of track")
        }
        if selectedMinutes > 0 {
            let stopTime = now.addingTimeInterval(TimeInterval(selectedMinutes * 60))
            return L("Stops at %@", stopTime.formatted(date: .omitted, time: .shortened))
        }
        return playLastSongToEnd ? L("Stops when the current track finishes") : L("Timer off")
    }
}
