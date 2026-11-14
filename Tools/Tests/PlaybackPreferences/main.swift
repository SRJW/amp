import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
}
let waveform = FullTrackWaveformGeometry(durationMs: 240_000, width: 360)
check(waveform.position(at: 0) == 0, "Static left edge is the beginning")
check(waveform.position(at: 180) == 120_000, "Static midpoint is half the complete song")
check(waveform.position(at: 360) == 240_000, "Static right edge is the end")
check(waveform.position(at: -50) == 0, "Dragging before the file clamps")
check(waveform.position(at: 500) == 240_000, "Dragging beyond the file clamps")
check(waveform.position(at: .nan) == 0, "Invalid coordinates are safe")
check(FullTrackWaveformGeometry(durationMs: 0, width: 0).position(at: 10) == 0, "Unloaded waveform is safe")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: 20_000, incomingRemaining: 30_000) == 5000, "Manual crossfade uses the chosen duration")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: 900, incomingRemaining: 30_000) == 900, "Fit the outgoing tail")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: 20_000, incomingRemaining: 500) == 500, "Fit short incoming songs")
check(PlaybackPreferences.handoffDuration(requested: 0, outgoingRemaining: 20_000, incomingRemaining: 30_000) == 20, "Off preserves the inaudible anti-click handover")
check(PlaybackPreferences.handoffDuration(requested: 5000, outgoingRemaining: -1, incomingRemaining: 30_000) == 1, "Finished tracks cannot create a long phantom fade")
print("Passed \(checks) playback preference and static waveform checks")

// Render buffers update in chunks, while the display must continue moving between them.
var display = PlaybackDisplayTimeline()
let entry = UUID()
var previous: Int64 = 0
var largestStep: Int64 = 0
var smallestStep: Int64 = 1000
for frame in 0...180 {
    let now = Double(frame) / 60
    let audio = Int64(floor(now / 0.1) * 100)
    let shown = display.position(audioMs: audio, entry: entry, uptime: now, durationMs: 60_000, playing: true)
    if frame > 1 {
        let step = shown - previous
        largestStep = max(largestStep, step)
        smallestStep = min(smallestStep, step)
        check(step >= 0 && step <= 30, "A buffered clock never makes a backward or buffer-sized visual jump")
    }
    previous = shown
}
check(smallestStep > 0, "Scrolling advances during frames between render updates")
check(largestStep < 100, "Scrolling does not jump a full audio buffer")
check(abs(previous - 3000) < 100, "Smoothing stays synchronized with the track")
display.reset()
check(display.position(audioMs: 45_000, entry: entry, uptime: 4, durationMs: 60_000, playing: true) == 45_000, "An explicit forward seek is immediate")
display.reset()
check(display.position(audioMs: 5000, entry: entry, uptime: 4.1, durationMs: 60_000, playing: true) == 5000, "An explicit backward seek is immediate")
check(display.position(audioMs: 5020, entry: entry, uptime: 4.2, durationMs: 60_000, playing: false) == 5020, "Pause freezes at the exact audio position")
check(display.position(audioMs: 0, entry: UUID(), uptime: 4.3, durationMs: 60_000, playing: true) == 0, "A different queue entry starts with a fresh clock")
check(display.position(audioMs: 45_000, entry: entry, uptime: 500, durationMs: 60_000, playing: true) == 45_000, "Returning after suspension synchronizes immediately")
check(display.position(audioMs: 59_999, entry: entry, uptime: 501, durationMs: 60_000, playing: true) <= 60_000, "Display never runs beyond the file")
print("Passed \(checks) playback display and preference checks in total")
