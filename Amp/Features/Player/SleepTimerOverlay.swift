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

    static func confirm() {
        confirmGenerator.prepare()
        confirmGenerator.notificationOccurred(.success)
    }

    static func cancel() {
        milestoneGenerator.prepare()
        milestoneGenerator.impactOccurred(intensity: 0.5)
    }
}

/// Poweramp v3–inspired floating Liquid Glass Sleep Timer card:
/// 0–120 min (2h) scrubbable 5-minute tactile ruler with per-step haptics,
/// "Play last song to end" switch, live stop-time / countdown readout, and instant OK / Turn off controls.
struct SleepTimerOverlay: View {
    let onDismiss: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(\.playerReduceMotion) private var reduceMotion
    @State private var selectedMinutes: Int = 30
    @State private var playLastSongToEnd: Bool = true
    @State private var appeared = false

    private static let maxMinutes = 120
    private static let stepMinutes = 5

    var body: some View {
        ZStack {
            // Subtle dim scrim — tapping outside closes cleanly.
            Color.black.opacity(appeared ? 0.36 : 0.0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissAnimated() }

            card
                .padding(.horizontal, 22)
                .scaleEffect(appeared || reduceMotion ? 1.0 : 0.94)
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: appeared || reduceMotion ? 0 : 12)
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

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            rulerControl
            playLastSongRow
            footerButtons
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(0.46))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.42), radius: 28, y: 14)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: player.sleepTimerActive || selectedMinutes > 0 || playLastSongToEnd ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Sleep timer"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(subtitleText(now: context.date))
                            .font(.system(size: 12.5, weight: .regular).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.64))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(formattedDuration(selectedMinutes, endOfTrack: selectedMinutes == 0 && playLastSongToEnd))
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.16), value: selectedMinutes)
            }
        }
    }

    private var rulerControl: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let fraction = CGFloat(selectedMinutes) / CGFloat(Self.maxMinutes)
                let fillWidth = max(fraction * width, selectedMinutes > 0 ? 12 : 0)
                let stepCount = Self.maxMinutes / Self.stepMinutes

                ZStack(alignment: .leading) {
                    // Subtle recessed glass track
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 16)

                    // Luminous active fill bar
                    if selectedMinutes > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.72), Color.white.opacity(0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth, height: 16)
                    }

                    // Poweramp / iOS tactile vertical tick marks across 0–120 min (every 5 min)
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
                                        ? Color.white
                                        : (isFilled ? Color.white.opacity(0.78) : Color.white.opacity(isMajor ? 0.42 : 0.22))
                                )
                                .frame(
                                    width: isCurrent ? 3.5 : (isMajor ? 1.8 : 1.2),
                                    height: isCurrent ? 30 : (isMajor ? 22 : (isQuarter ? 16 : 11))
                                )
                                .shadow(color: isCurrent ? Color.white.opacity(0.75) : .clear, radius: 6)
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
            .foregroundStyle(Color.white.opacity(0.58))
        }
    }

    private var playLastSongRow: some View {
        Toggle(isOn: $playLastSongToEnd) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Play last song to end"))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.white)
                Text(selectedMinutes == 0
                     ? L("Stops when the current track finishes")
                     : L("Finishes the playing song when time expires"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.58))
            }
        }
        .tint(Color.white.opacity(0.88))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            if player.sleepTimerActive {
                Button {
                    player.cancelSleepTimer()
                    SleepTimerHaptics.cancel()
                    dismissAnimated()
                } label: {
                    Text(L("Turn off timer"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.95))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(Color.red.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(Color.red.opacity(0.28), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    dismissAnimated()
                } label: {
                    Text(L("Cancel"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
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
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.white))
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
