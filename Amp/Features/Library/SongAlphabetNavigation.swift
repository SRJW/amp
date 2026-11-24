import SwiftUI

enum SongAlphabet {
    static let letters = ["#"] + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    static func key(_ title: String) -> String {
        let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased()
        guard let first = normalized.trimmingCharacters(in: .whitespacesAndNewlines).first,
              ("A"..."Z").contains(String(first)) else { return "#" }
        return String(first)
    }
    static func anchors(_ songs: [Song], key: (Song) -> String = \.title) -> [String: Int64] {
        anchors(songs, id: \.id, title: key)
    }

    static func anchors<Item, ID: Hashable>(_ items: [Item], id: (Item) -> ID, title: (Item) -> String) -> [String: ID] {
        var result: [String: ID] = [:]
        for item in items {
            let letter = key(title(item))
            if result[letter] == nil { result[letter] = id(item) }
        }
        return result
    }

    /// Empty letters still have a position in the index; seek to the next populated group.
    static func target(for letter: String, anchors: [String: Int64]) -> Int64? {
        targetAnchor(for: letter, anchors: anchors)
    }

    static func targetAnchor<ID>(for letter: String, anchors: [String: ID]) -> ID? {
        guard let index = letters.firstIndex(of: letter) else { return nil }
        let resolved = letters[index...].first { anchors[$0] != nil }
            ?? letters[...index].last { anchors[$0] != nil }
        return resolved.flatMap { anchors[$0] }
    }
}

enum SongAlphabetMetrics {
    static let width: CGFloat = 24
    static let rowHeight: CGFloat = 20
    static let maximumHeight: CGFloat = 620
    static let letterSize: CGFloat = 10.5
    static let bubbleSize: CGFloat = 68
    static let bubbleTextSize: CGFloat = 42
    static let bubbleGap: CGFloat = 18
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
    var key: (Song) -> String = \.title
    let scrollTo: (Int64) -> Void

    var body: some View {
        AlphabetIndexView(anchors: SongAlphabet.anchors(songs, key: key), scrollTo: scrollTo)
    }
}

struct AlphabetIndexView<ID: Hashable>: View {
    let anchors: [String: ID]
    let scrollTo: (ID) -> Void
    @AppStorage(SongAlphabetPreferences.hapticsKey) private var hapticsEnabled = SongAlphabetPreferences.defaultHaptics
    @State private var active: String?
    @State private var scrubbing = false
    @State private var touchY: CGFloat = 0
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let available = SongAlphabet.letters.filter { anchors[$0] != nil }
        Group {
            if available.count > 1 {
                index(anchors: anchors)
                    .frame(width: SongAlphabetMetrics.width)
                    .frame(maxHeight: min(CGFloat(SongAlphabet.letters.count) * SongAlphabetMetrics.rowHeight, SongAlphabetMetrics.maximumHeight))
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
                    .padding(.vertical, Spacing.sm)
            }
        }
        .sensoryFeedback(.selection, trigger: active, condition: shouldPlaySelection)
    }

    private func index(anchors: [String: ID]) -> some View {
        GeometryReader { geometry in
            let rowHeight = geometry.size.height / CGFloat(SongAlphabet.letters.count)
            VStack(spacing: 0) {
                ForEach(SongAlphabet.letters, id: \.self) { letter in
                    let isActive = scrubbing && active == letter
                    let hasTarget = anchors[letter] != nil
                    Text(letter)
                        .font(.system(size: isActive ? SongAlphabetMetrics.letterSize + 1.5 : SongAlphabetMetrics.letterSize,
                                      weight: isActive ? .heavy : .semibold))
                        .foregroundStyle(isActive
                            ? (colorScheme == .dark ? Color.white : palette.onSurface)
                            : palette.primary.opacity(hasTarget ? 0.90 : 0.28))
                        .frame(width: SongAlphabetMetrics.width, height: rowHeight)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(palette.primary.opacity(0.22))
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in move(to: value.location.y, height: geometry.size.height, anchors: anchors) }
                .onEnded { value in
                    move(to: value.location.y, height: geometry.size.height, anchors: anchors)
                    scrubbing = false
                })
            .overlay(alignment: .topLeading) {
                if scrubbing, let active { bubble(active) }
            }
        }
    }

    private func bubble(_ letter: String) -> some View {
        let fill = colorScheme == .dark ? Color(white: 0.24).opacity(0.94) : palette.surface.opacity(0.96)
        let stroke = colorScheme == .dark ? Color.white.opacity(0.12) : palette.outline.opacity(0.30)
        return Text(letter)
            .font(.system(size: SongAlphabetMetrics.bubbleTextSize, weight: .bold))
            .foregroundStyle(colorScheme == .dark ? Color.white : palette.onSurface)
            .frame(width: SongAlphabetMetrics.bubbleSize, height: SongAlphabetMetrics.bubbleSize)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
            .position(x: -SongAlphabetMetrics.bubbleSize / 2 - SongAlphabetMetrics.bubbleGap, y: touchY)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func move(to y: CGFloat, height: CGFloat, anchors: [String: ID]) {
        let rowHeight = height / CGFloat(SongAlphabet.letters.count)
        let index = min(max(Int(y / max(rowHeight, 1)), 0), SongAlphabet.letters.count - 1)
        touchY = min(max(y, SongAlphabetMetrics.bubbleSize / 2), height - SongAlphabetMetrics.bubbleSize / 2)
        scrubbing = true
        let letter = SongAlphabet.letters[index]
        if active != letter, let id = SongAlphabet.targetAnchor(for: letter, anchors: anchors) {
            active = letter
            scrollTo(id)
        }
    }

    private func shouldPlaySelection(_ previous: String?, _ next: String?) -> Bool {
        hapticsEnabled && scrubbing && previous != nil && next != nil && previous != next
    }
}
