import SwiftUI

/// Embedded cover art of an audio file, loaded off the main thread, with a quiet placeholder.
struct SongArtworkView: View {
    let url: URL?
    var maxPixels = 300
    var placeholder = "music.note"
    var contentMode: ContentMode = .fill
    var immersiveHero = false
    @Environment(\.palette) private var palette
    @State private var image: UIImage?
    @State private var imageRequest = ""
    private static let fallbacks = [600, 320, 144]

    var body: some View {
        let changeVersion = ArtworkChangeBroker.shared.version
        let path = url?.path ?? ""
        let request = "\(path)|\(maxPixels)|\(changeVersion)"
        let displayed = imageRequest == request ? image
            : url.flatMap { ArtworkLoader.shared.cachedImage(for: $0, maxPixels: maxPixels, fallbackSizes: Self.fallbacks) }
        ZStack {
            if let displayed {
                if immersiveHero {
                    PlayerAlbumArtwork(image: displayed)
                } else if contentMode == .fit {
                    Image(uiImage: displayed).resizable().scaledToFit()
                } else {
                    FillImage(image: displayed)
                }
            } else {
                Rectangle().fill(palette.surfaceVariant)
                Image(systemName: placeholder)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
        }
        .task(id: request) {
            let token = request
            guard let url else {
                image = nil
                imageRequest = token
                return
            }
            if let exact = ArtworkLoader.shared.cachedImage(for: url, maxPixels: maxPixels) {
                image = exact
                imageRequest = token
                return
            }
            if let fallback = ArtworkLoader.shared.cachedImage(for: url, maxPixels: maxPixels, fallbackSizes: Self.fallbacks) {
                image = fallback
            }
            let loaded = await ArtworkLoader.shared.image(for: url, maxPixels: maxPixels)
            guard !Task.isCancelled else { return }
            image = loaded
            imageRequest = token
        }
    }
}

extension SongArtworkView {
    init(song: Song?, maxPixels: Int = 300, contentMode: ContentMode = .fill) {
        self.init(url: song?.url, maxPixels: maxPixels, contentMode: contentMode)
    }
}

/// An album's cover: its first song's embedded art.
struct AlbumArtworkView: View {
    let albumId: Int64
    var maxPixels = 320
    var immersiveHero = false
    @Environment(LibraryStore.self) private var library

    var body: some View {
        SongArtworkView(url: library.albumCoverSong[albumId]?.url, maxPixels: maxPixels, placeholder: "square.stack", immersiveHero: immersiveHero)
    }
}

/// A picture file (custom playlist cover, artist photo) or a fallback.
struct FileImageView<Fallback: View>: View {
    let path: String?
    var maxPixels = 320
    @ViewBuilder let fallback: () -> Fallback
    @State private var image: UIImage?
    @State private var imageRequest = ""

    var body: some View {
        let changeVersion = ArtworkChangeBroker.shared.version
        let resolvedPath = path.map(LibraryPaths.resolveImage)
        let request = "\(resolvedPath ?? "")|\(maxPixels)|\(changeVersion)"
        let displayed = imageRequest == request ? image : resolvedPath.flatMap {
            ArtworkLoader.shared.cachedImage(atPath: $0, maxPixels: maxPixels)
        }
        ZStack {
            if let displayed { FillImage(image: displayed) } else { fallback() }
        }
        .task(id: request) {
            let token = request
            guard let resolvedPath else {
                image = nil
                imageRequest = token
                return
            }
            if let cached = ArtworkLoader.shared.cachedImage(atPath: resolvedPath, maxPixels: maxPixels) {
                image = cached
                imageRequest = token
                return
            }
            let loaded = await ArtworkLoader.shared.image(atPath: resolvedPath, maxPixels: maxPixels)
            guard !Task.isCancelled else { return }
            image = loaded
            imageRequest = token
        }
    }
}

/// A playlist's cover: the user's own artwork, or the default playlist cover.
struct PlaylistCoverView: View {
    let playlist: Playlist
    @Environment(\.palette) private var palette

    var body: some View {
        FileImageView(path: playlist.artworkPath) {
            ZStack {
                Rectangle().fill(palette.surfaceVariant)
                Image(systemName: "music.note.list").font(.system(size: 28)).foregroundStyle(palette.onSurfaceVariant)
            }
        }
    }
}

/// An artist's picture, or their monogram.
struct ArtistArtworkView: View {
    let artist: Artist
    var fontSize: CGFloat = 36
    var maxPixels = 400

    var body: some View {
        FileImageView(path: artist.artworkPath, maxPixels: maxPixels) { ArtistMonogram(name: artist.name, fontSize: fontSize) }
    }
}

/// The first letter of a name on a tone picked from the name, so each artist keeps theirs.
struct ArtistMonogram: View {
    let name: String
    var fontSize: CGFloat = 18
    @Environment(\.palette) private var palette

    var body: some View {
        let letter = name.trimmed.first.map { String($0).uppercased() } ?? "?"
        ZStack {
            Rectangle().fill(palette.surfaceVariant)
            Text(letter).font(.system(size: fontSize, weight: .bold)).foregroundStyle(palette.onSurface)
        }
    }
}

/// A picture filling exactly the space it is given, cropped to it. A bare scaledToFill image
/// reports its overflowing size, so a non-square cover would widen whatever holds it.
struct FillImage: View {
    let image: UIImage

    var body: some View {
        Color.clear
            .overlay { Image(uiImage: image).resizable().scaledToFill() }
            .clipped()
    }
}
