import SwiftUI

/// The playing track's A–B loop and its saved bookmarks.
struct MarksSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var bookmarks: [TrackBookmark] = []
    @State private var renaming: TrackBookmark?
    @State private var name = ""

    var body: some View {
        let song = player.state.currentSong
        let loop = player.state.abLoop?.songId == song?.id ? player.state.abLoop : nil
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.sm) {
                        Button(loop?.startMs.map { "A · \(formatDuration($0))" } ?? L("Set A")) { report(player.setLoopStart()) }
                        Button(loop?.endMs.map { "B · \(formatDuration($0))" } ?? L("Set B")) { report(player.setLoopEnd()) }
                    }
                    .buttonStyle(.bordered)
                    Toggle(L("Loop"), isOn: Binding(get: { loop?.enabled == true }, set: { report(player.setLoopEnabled($0)) }))
                        .disabled(loop?.isComplete != true)
                    Button(L("Clear"), role: .destructive) { player.clearLoop() }
                        .disabled(loop == nil)
                } header: {
                    Text(L("A–B loop"))
                } footer: {
                    Text(L("Set A and B while listening. Looping jumps back to A each time playback reaches B."))
                }.toolSectionAppearance()
                Section {
                    Button {
                        addBookmark()
                    } label: {
                        Label(L("Add at %@", formatDuration(player.clock.positionMs)), systemImage: "bookmark")
                    }
                    .disabled(song == nil)
                    if bookmarks.isEmpty {
                        Text(song == nil ? L("Nothing is playing.") : L("No bookmarks for this track yet.")).foregroundStyle(palette.onSurfaceVariant)
                    }
                    ForEach(bookmarks) { bookmark in
                        Button { if bookmark.songId == player.state.currentSong?.id { player.seek(to: bookmark.positionMs) } } label: {
                            HStack {
                                Text(formatDuration(bookmark.positionMs)).monospacedDigit().foregroundStyle(palette.primary)
                                Text(bookmark.label.isBlank ? L("Bookmark") : bookmark.label).foregroundStyle(palette.onSurface)
                                Spacer()
                            }
                        }
                        .accessibilityHint("Plays from \(formatDuration(bookmark.positionMs))")
                        .swipeActions {
                            Button(role: .destructive) { delete(bookmark) } label: { Label(L("Delete"), systemImage: "trash") }
                            Button {
                                name = bookmark.label
                                renaming = bookmark
                            } label: { Label(L("Rename"), systemImage: "pencil") }
                        }
                    }
                } header: {
                    Text(L("Bookmarks"))
                }.toolSectionAppearance()
            }
            .modifier(ToolPageAppearance())
            .navigationTitle(L("Bookmarks & A–B loop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L("Done")) { dismiss() } }
            .alert(L("Name bookmark"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(L("Name"), text: $name)
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Save")) {
                    if let bookmark = renaming { try? library.database.renameBookmark(id: bookmark.id, label: name.trimmed) }
                    load()
                }
            }
        }
        .task(id: song?.id) { load() }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        guard let id = player.state.currentSong?.id else {
            bookmarks = []
            return
        }
        bookmarks = (try? library.database.bookmarks(songId: id)) ?? []
    }

    private func addBookmark() {
        guard let song = player.state.currentSong else { return }
        do {
            _ = try library.database.addBookmark(songId: song.id, positionMs: player.currentPositionMs())
            load()
        } catch {
            actions.show("Couldn't save the bookmark: \(error.localizedDescription)")
        }
    }

    private func delete(_ bookmark: TrackBookmark) {
        try? library.database.deleteBookmark(id: bookmark.id)
        load()
    }

    private func report(_ edit: AbLoopEdit) {
        switch edit {
        case .ok: break
        case .noTrack: actions.show("Nothing is playing")
        case .aNotBeforeB: actions.show("A must be at least a second before B")
        case .notReady: actions.show("Set A and B first")
        case .unsupported: actions.show("Looping is not available")
        }
    }
}
