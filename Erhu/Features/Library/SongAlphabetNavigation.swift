import SwiftUI

enum SongAlphabet {
    static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]
    static func key(_ title: String) -> String {
        let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased()
        guard let first = normalized.trimmingCharacters(in: .whitespacesAndNewlines).first,
              ("A"..."Z").contains(String(first)) else { return "#" }
        return String(first)
    }
    static func anchors(_ songs: [Song]) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for song in songs where result[key(song.title)] == nil { result[key(song.title)] = song.id }
        return result
    }

    /// Empty letters still have a position in the index; seek to the next populated group.
    static func target(for letter: String, anchors: [String: Int64]) -> Int64? {
        guard let index = letters.firstIndex(of: letter) else { return nil }
        let resolved = letters[index...].first { anchors[$0] != nil }
            ?? letters[...index].last { anchors[$0] != nil }
        return resolved.flatMap { anchors[$0] }
    }
}

enum SongAlphabetMetrics {
    static let width: CGFloat = 44
    static let rowHeight: CGFloat = 14
    static let maximumHeight: CGFloat = 360
    static let letterSize: CGFloat = 10
    static let bubbleSize: CGFloat = 64
    static let bubbleTextSize: CGFloat = 38
    static let bubbleGap: CGFloat = 4
    static let scrollDuration = 0.16
    static let bubbleDuration = 0.12
    static let accessibilityLabel = "Song alphabet index"
}

enum SongAlphabetPreferences {
    static let hapticsKey = "library.alphabet.haptics"
    static let defaultHaptics = true
    static let hapticsTitle = "Alphabet scrolling haptics"
    static let hapticsDescription = "A brief tap when you move to another letter in the alphabet index."
}

struct SongAlphabetIndex: View {
    let songs: [Song]
    let scrollTo: (Int64) -> Void
    @AppStorage(SongAlphabetPreferences.hapticsKey) private var hapticsEnabled = SongAlphabetPreferences.defaultHaptics
    @State private var active: String?
    @State private var scrubbing = false
    @State private var touchY: CGFloat = 0
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let anchors = SongAlphabet.anchors(songs)
        let available = SongAlphabet.letters.filter { anchors[$0] != nil }
        Group {
            if available.count > 1 {
                index(anchors: anchors)
                .frame(width: SongAlphabetMetrics.width,
                       height: min(CGFloat(SongAlphabet.letters.count) * SongAlphabetMetrics.rowHeight, SongAlphabetMetrics.maximumHeight))
                .animation(reduceMotion ? nil : .easeOut(duration: SongAlphabetMetrics.bubbleDuration), value: scrubbing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SongAlphabetMetrics.accessibilityLabel)
                .accessibilityIdentifier("songAlphabetIndex")
                .accessibilityValue(active ?? available.first ?? "")
                .accessibilityAdjustableAction { direction in
                    let current = available.firstIndex(of: active ?? "") ?? 0
                    let index = min(max(current + (direction == .increment ? 1 : -1), 0), available.count - 1)
                    active = available[index]
                    if let id = anchors[available[index]] { scrollTo(id) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: active, condition: shouldPlaySelection)
    }

    private func index(anchors: [String: Int64]) -> some View {
        GeometryReader { geometry in
            let rowHeight = geometry.size.height / CGFloat(SongAlphabet.letters.count)
            VStack(spacing: 0) {
                ForEach(SongAlphabet.letters, id: \.self) { letter in
                    Text(letter).font(.system(size: SongAlphabetMetrics.letterSize, weight: .bold))
                        .opacity(anchors[letter] == nil ? 0.25 : 1)
                        .frame(width: SongAlphabetMetrics.width, height: rowHeight)
                        .background {
                            if scrubbing && active == letter {
                                Capsule().fill(palette.primary.opacity(0.16))
                            }
                        }
                }
            }
            .foregroundStyle(palette.primary)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in move(to: value.location.y, height: geometry.size.height, anchors: anchors) }
                .onEnded { _ in scrubbing = false; active = nil })
            .overlay(alignment: .topLeading) {
                if scrubbing, let active { bubble(active) }
            }
        }
    }

    private func bubble(_ letter: String) -> some View {
        Text(letter).font(.system(size: SongAlphabetMetrics.bubbleTextSize, weight: .bold))
            .foregroundStyle(palette.onSurface)
            .frame(width: SongAlphabetMetrics.bubbleSize, height: SongAlphabetMetrics.bubbleSize)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
            .position(x: -SongAlphabetMetrics.bubbleSize / 2 - SongAlphabetMetrics.bubbleGap, y: touchY)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func move(to y: CGFloat, height: CGFloat, anchors: [String: Int64]) {
        let rowHeight = height / CGFloat(SongAlphabet.letters.count)
        let index = min(max(Int(y / max(rowHeight, 1)), 0), SongAlphabet.letters.count - 1)
        touchY = min(max(y, SongAlphabetMetrics.bubbleSize / 2), height - SongAlphabetMetrics.bubbleSize / 2)
        scrubbing = true
        let letter = SongAlphabet.letters[index]
        if active != letter, let id = SongAlphabet.target(for: letter, anchors: anchors) {
            active = letter
            scrollTo(id)
        }
    }

    private func shouldPlaySelection(_ previous: String?, _ next: String?) -> Bool {
        hapticsEnabled && scrubbing && previous != nil && next != nil && previous != next
    }
}
