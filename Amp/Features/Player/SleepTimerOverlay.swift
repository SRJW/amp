import SwiftUI
import UIKit

@MainActor
private enum SleepTimerHaptics {
    private static let stepGenerator = UISelectionFeedbackGenerator()
    private static let milestoneGenerator = UIImpactFeedbackGenerator(style: .light)

    static func step(minutes: Int) {
        if minutes == 0 || minutes % 30 == 0 {
            milestoneGenerator.prepare()
            milestoneGenerator.impactOccurred(intensity: 0.72)
        } else {
            stepGenerator.prepare()
            stepGenerator.selectionChanged()
        }
    }

    static func tap() {
        milestoneGenerator.prepare()
        milestoneGenerator.impactOccurred(intensity: 0.55)
    }
}

/// Minimalist iOS 26 / iOS 27 native Liquid Glass Sleep Timer pill:
/// - No Cancel / Start dialog box — changes apply live as you slide or tap, and tapping outside dismisses.
/// - Native `.glassSurface(cornerRadius: 30)` refraction floating directly above the secondary bar.
/// - Clean iOS Control Center–style scrubbable capsule slider (0–120 min in 5-min tactile ticks)
///   plus one-tap quick chips (Off, End of song, 15m, 30m, 45m, 1h, 2h) and a compact "Finish last song" pill.
struct SleepTimerOverlay: View {
    var dominantColor: Color? = nil
    var controlColors: PlayerBackdropPalette.ControlColors? = nil
    let onDismiss: () -> Void

    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.playerReduceMotion) private var reduceMotion

    @State private var selectedMinutes: Int = 0
    @State private var finishLastSong: Bool = true
    @State private var isEndOfSongOnly: Bool = false
    @State private var appeared = false

    private static let maxMinutes = 120
    private static let stepMinutes = 5

    private var primaryInk: Color {
        colorScheme == .light ? Color.black.opacity(0.88) : Color.white
    }

    private var secondaryInk: Color {
        colorScheme == .light ? Color.black.opacity(0.52) : Color.white.opacity(0.58)
    }

    private var subtleFill: Color {
        colorScheme == .light ? Color.black.opacity(0.07) : Color.white.opacity(0.11)
    }

    private var activeFill: Color {
        if let controls = controlColors, settings.customTheme == nil {
            return colorScheme == .light ? controls.buttonIcon : controls.accentInk
        }
        return primaryInk
    }

    private var activeChipInk: Color {
        colorScheme == .light ? .white : Color(white: 0.08)
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            // Float naturally right above the secondary customizable action bar (which sits at 0.692 * height).
            let bottomClearance = max(height * 0.34, 240)

            ZStack(alignment: .bottom) {
                // Ultra-lightweight tap-outside catcher (barely dims so Now Playing stays vibrant).
                Color.black.opacity(appeared ? 0.14 : 0.0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissAnimated() }

                floatingCapsule
                    .padding(.horizontal, 18)
                    .padding(.bottom, bottomClearance)
                    .scaleEffect(appeared || reduceMotion ? 1.0 : 0.92, anchor: .bottom)
                    .opacity(appeared ? 1.0 : 0.0)
                    .offset(y: appeared || reduceMotion ? 0 : 10)
            }
        }
        .onAppear {
            syncFromPlayer()
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    appeared = true
                }
            }
        }
    }

    private var floatingCapsule: some View {
        GlassGroup(spacing: 8, enabled: settings.glassEnabled) {
            VStack(spacing: 14) {
                headerRow
                sliderTrack
                presetsAndOptionRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassSurface(
                cornerRadius: 32,
                enabled: settings.glassEnabled,
                interactive: true
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 22, y: 10)
        }
    }

    // MARK: - Top Row (Icon + Title + Live Value / Countdown)

    private var headerRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let isActive = selectedMinutes > 0 || isEndOfSongOnly
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isActive ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? primaryInk : secondaryInk)
                    .contentTransition(.symbolEffect(.replace))

                Text(L("Sleep timer"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryInk)

                if let status = liveStatusText(now: context.date) {
                    Text("· " + status)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(readoutLabel)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isActive ? primaryInk : secondaryInk)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.16), value: selectedMinutes)
                    .animation(.snappy(duration: 0.16), value: isEndOfSongOnly)
            }
        }
    }

    // MARK: - Native iOS 27 Control Center / Segmented-style Capsule Slider

    private var sliderTrack: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = CGFloat(selectedMinutes) / CGFloat(Self.maxMinutes)
            let fillWidth = selectedMinutes > 0 ? max(fraction * width, 24) : 0
            let stepCount = Self.maxMinutes / Self.stepMinutes

            ZStack(alignment: .leading) {
                // Recessed capsule track (like UISegmentedControl groove)
                Capsule()
                    .fill(subtleFill)
                    .frame(height: 36)

                // Raised Liquid Glass thumb fill (matches the selected thumb in Control Color)
                if selectedMinutes > 0 {
                    Group {
                        if #available(iOS 26.0, *), settings.glassEnabled {
                            Capsule()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.72))
                                .glassEffect(.regular, in: .capsule)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 5, y: 1)
                        } else {
                            Capsule()
                                .fill(activeFill.opacity(colorScheme == .dark ? 0.88 : 0.82))
                        }
                    }
                    .frame(width: fillWidth, height: 32)
                    .padding(.leading, 2)
                }

                // Subtle internal micro-ticks every 15m / 30m
                HStack(spacing: 0) {
                    ForEach(0...stepCount, id: \.self) { index in
                        let mins = index * Self.stepMinutes
                        let isMajor = mins % 30 == 0
                        let isQuarter = mins % 15 == 0
                        Capsule()
                            .fill(primaryInk.opacity(isMajor ? 0.32 : (isQuarter ? 0.18 : 0.09)))
                            .frame(
                                width: isMajor ? 1.6 : 1.1,
                                height: isMajor ? 14 : (isQuarter ? 10 : 6)
                            )
                        if index < stepCount {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: width, height: 36)
            }
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clamped = min(max(value.location.x / width, 0), 1)
                        let raw = Double(clamped) * Double(Self.maxMinutes)
                        let snapped = Int((raw / Double(Self.stepMinutes)).rounded()) * Self.stepMinutes
                        let bounded = min(max(snapped, 0), Self.maxMinutes)
                        if bounded != selectedMinutes || isEndOfSongOnly {
                            selectedMinutes = bounded
                            isEndOfSongOnly = false
                            SleepTimerHaptics.step(minutes: bounded)
                            applyLive()
                        }
                    }
            )
        }
        .frame(height: 36)
    }

    // MARK: - Segmented Liquid Glass Quick Chips + "End of track" Pill

    private var presetsAndOptionRow: some View {
        HStack(spacing: 6) {
            presetChip(title: L("Off"), isSelected: selectedMinutes == 0 && !isEndOfSongOnly) {
                selectedMinutes = 0
                isEndOfSongOnly = false
                SleepTimerHaptics.step(minutes: 0)
                applyLive()
            }

            ForEach([15, 30, 60, 120], id: \.self) { mins in
                presetChip(
                    title: mins < 60 ? "\(mins)m" : "\(mins / 60)h",
                    isSelected: !isEndOfSongOnly && selectedMinutes == mins
                ) {
                    selectedMinutes = mins
                    isEndOfSongOnly = false
                    SleepTimerHaptics.tap()
                    applyLive()
                }
            }

            Spacer(minLength: 2)

            // Compact iOS segmented-glass toggle pill: End of track
            let endActive = selectedMinutes == 0 ? isEndOfSongOnly : finishLastSong
            Button {
                SleepTimerHaptics.tap()
                if selectedMinutes == 0 {
                    isEndOfSongOnly.toggle()
                    if isEndOfSongOnly { finishLastSong = true }
                } else {
                    finishLastSong.toggle()
                }
                applyLive()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: endActive ? "checkmark.circle.fill" : "music.note")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(L("End of track"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(endActive ? primaryInk : secondaryInk)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    glassThumbBackground(isSelected: endActive)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Play last song to end"))
            .accessibilityValue(endActive ? L("On") : L("Off"))
        }
    }

    private func presetChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? primaryInk : secondaryInk)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    glassThumbBackground(isSelected: isSelected)
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func glassThumbBackground(isSelected: Bool) -> some View {
        if isSelected {
            if #available(iOS 26.0, *), settings.glassEnabled {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.72))
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 5, y: 1)
            } else {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.10))
            }
        } else {
            Capsule()
                .fill(subtleFill)
        }
    }

    // MARK: - Live State Sync

    private func syncFromPlayer() {
        finishLastSong = player.sleepTimerPlayLastSongToEnd
        if let deadline = player.sleepTimerDeadline {
            let remaining = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
            let snapped = Int((Double(remaining) / Double(Self.stepMinutes)).rounded()) * Self.stepMinutes
            selectedMinutes = min(max(snapped, Self.stepMinutes), Self.maxMinutes)
            isEndOfSongOnly = false
        } else if player.sleepTimerEndOfTrack {
            selectedMinutes = 0
            isEndOfSongOnly = true
            finishLastSong = true
        } else {
            selectedMinutes = 0
            isEndOfSongOnly = false
        }
    }

    private func applyLive() {
        if selectedMinutes > 0 {
            player.setSleepTimer(minutes: selectedMinutes, playLastSongToEnd: finishLastSong)
        } else if isEndOfSongOnly {
            player.setSleepTimerEndOfTrack()
        } else {
            player.cancelSleepTimer()
        }
    }

    private func dismissAnimated() {
        if reduceMotion {
            onDismiss()
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            appeared = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            onDismiss()
        }
    }

    private var readoutLabel: String {
        if selectedMinutes == 0 {
            return isEndOfSongOnly ? L("End of track") : L("Off")
        }
        if selectedMinutes < 60 {
            return "\(selectedMinutes) min"
        }
        let h = selectedMinutes / 60
        let m = selectedMinutes % 60
        return m == 0 ? "\(h) h" : "\(h)h \(m)m"
    }

    private func liveStatusText(now: Date) -> String? {
        if let deadline = player.sleepTimerDeadline, deadline > now {
            let totalSeconds = max(0, Int(deadline.timeIntervalSince(now)))
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%d:%02d", m, s)
        }
        return nil
    }
}
