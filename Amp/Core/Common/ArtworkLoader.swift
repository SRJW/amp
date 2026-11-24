import CryptoKit
import Foundation
import ImageIO
import Observation
import UIKit

/// Lightweight observable counter bumped only when artwork is explicitly edited/replaced,
/// avoiding hundreds of per-row NotificationCenter Combine subscriptions during 120 Hz scrolling.
@MainActor
@Observable
final class ArtworkChangeBroker {
    static let shared = ArtworkChangeBroker()
    private(set) var version = 0
    private(set) var lastChangedPath: String?

    func notifyChanged(path: String) {
        lastChangedPath = path
        version &+= 1
    }
}

/// Loads embedded cover art (Android's ArtworkLoader): read from the audio file's own tags,
/// decoded and downsampled off the main thread, kept in a size-keyed memory cache and a
/// persistent disk thumbnail cache for fast 60/120 Hz scrolling.
final class ArtworkLoader: @unchecked Sendable {
    static let shared = ArtworkLoader()
    static let didChange = Notification.Name("ArtworkLoader.didChange")

    private static let diskCacheMaxPixels = 500
    private static let diskCacheMaxBytes: Int64 = 80 * 1024 * 1024
    private static let diskCacheMaxFiles = 4_000

    private let revisionsLock = NSLock()
    private var revisions: [String: Int] = [:]

    private final class InFlightLoad: @unchecked Sendable {
        let op = BlockOperation()
        var waiters: [(id: UUID, resume: (UIImage?) -> Void)] = []
    }

    private let inFlightLock = NSLock()
    private var inFlight: [String: InFlightLoad] = [:]

    func revision(for path: String) -> Int { revisionsLock.withLock { revisions[path, default: 0] } }

    private func makeKey(path: String, maxPixels: Int, revision: Int) -> String {
        "\(path)|\(maxPixels)|\(revision)"
    }

    private func makeFileKey(path: String, maxPixels: Int, revision: Int) -> String {
        "file:\(path)|\(maxPixels)|\(revision)"
    }

    private let cache = NSCache<NSString, UIImage>()
    private let misses = NSCache<NSString, NSNumber>()
    private let decodeQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "amp.artwork.decode"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 6
        return q
    }()
    private let prefetchQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "amp.artwork.prefetch"
        q.qualityOfService = .utility
        q.maxConcurrentOperationCount = 2
        return q
    }()
    private let diskWriteQueue = DispatchQueue(label: "amp.artwork.disk", qos: .utility)
    private let thumbDirectory: URL
    private let writeCountLock = NSLock()
    private var diskWritesSincePrune = 0

    private init() {
        cache.countLimit = 800
        cache.totalCostLimit = 80 * 1024 * 1024
        misses.countLimit = 4_000
        let dir = LibraryPaths.cachesFolder.appendingPathComponent("amp-artwork-thumbs", isDirectory: true)
        thumbDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    /// The cover of the file at [url], at most [maxPixels] on its longer side, or nil.
    func image(for url: URL, maxPixels: Int) async -> UIImage? {
        let path = url.path
        let rev = revision(for: path)
        let key = makeKey(path: path, maxPixels: maxPixels, revision: rev)
        let missKey = "\(path)|\(rev)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if misses.object(forKey: missKey as NSString) != nil { return nil }
        return await loadCoalesced(key: key, queue: decodeQueue) { [weak self] isCancelled in
            guard let self, !isCancelled() else { return nil }
            return self.decodeAudioCover(url: url, path: path, maxPixels: maxPixels, revision: rev, key: key, missKey: missKey, isCancelled: isCancelled)
        }
    }

    /// A cached image without loading (for drawing the first frame without a flash).
    func cachedImage(for url: URL, maxPixels: Int, fallbackSizes: [Int] = []) -> UIImage? {
        let path = url.path
        let rev = revision(for: path)
        if let exact = cache.object(forKey: makeKey(path: path, maxPixels: maxPixels, revision: rev) as NSString) {
            return exact
        }
        for size in fallbackSizes where size != maxPixels {
            if let image = cache.object(forKey: makeKey(path: path, maxPixels: size, revision: rev) as NSString) { return image }
        }
        return nil
    }

    /// An image file (custom artist or playlist cover) at [path], downsampled.
    func image(atPath path: String, maxPixels: Int) async -> UIImage? {
        let rev = revision(for: path)
        let key = makeFileKey(path: path, maxPixels: maxPixels, revision: rev)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        return await loadCoalesced(key: key, queue: decodeQueue) { [weak self] isCancelled in
            guard let self, !isCancelled() else { return nil }
            return self.decodeFileCover(path: path, maxPixels: maxPixels, revision: rev, key: key, isCancelled: isCancelled)
        }
    }

    func cachedImage(atPath path: String, maxPixels: Int) -> UIImage? {
        let rev = revision(for: path)
        return cache.object(forKey: makeFileKey(path: path, maxPixels: maxPixels, revision: rev) as NSString)
    }

    /// Low-priority background warmup for upcoming rows/tiles during fast scrolling.
    func prefetch(urls: [URL], maxPixels: Int) {
        guard !urls.isEmpty else { return }
        if prefetchQueue.operationCount > 32 { prefetchQueue.cancelAllOperations() }
        var seen = Set<String>()
        for url in urls {
            let path = url.path
            guard seen.insert(path).inserted else { continue }
            let rev = revision(for: path)
            let key = makeKey(path: path, maxPixels: maxPixels, revision: rev)
            let missKey = "\(path)|\(rev)"
            if cache.object(forKey: key as NSString) != nil || misses.object(forKey: missKey as NSString) != nil { continue }
            let op = BlockOperation()
            op.addExecutionBlock { [weak self, weak op] in
                guard let self, let op, !op.isCancelled else { return }
                if self.cache.object(forKey: key as NSString) != nil || self.misses.object(forKey: missKey as NSString) != nil { return }
                _ = self.decodeAudioCover(url: url, path: path, maxPixels: maxPixels, revision: rev, key: key, missKey: missKey) { op.isCancelled }
            }
            prefetchQueue.addOperation(op)
        }
    }

    /// Low-priority background warmup for artist/playlist cover files.
    func prefetchFiles(paths: [String], maxPixels: Int) {
        guard !paths.isEmpty else { return }
        if prefetchQueue.operationCount > 32 { prefetchQueue.cancelAllOperations() }
        var seen = Set<String>()
        for path in paths {
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            let rev = revision(for: path)
            let key = makeFileKey(path: path, maxPixels: maxPixels, revision: rev)
            if cache.object(forKey: key as NSString) != nil { continue }
            let op = BlockOperation()
            op.addExecutionBlock { [weak self, weak op] in
                guard let self, let op, !op.isCancelled else { return }
                if self.cache.object(forKey: key as NSString) != nil { return }
                _ = self.decodeFileCover(path: path, maxPixels: maxPixels, revision: rev, key: key) { op.isCancelled }
            }
            prefetchQueue.addOperation(op)
        }
    }

    func forget(path: String) {
        revisionsLock.withLock { revisions[path, default: 0] += 1 }
        // Versioned keys isolate this file in memory and disk cache, including reads already in flight.
        Task { @MainActor in ArtworkChangeBroker.shared.notifyChanged(path: path) }
        NotificationCenter.default.post(name: Self.didChange, object: path)
    }

    /// Clears in-memory thumbnails (disk thumbnails remain for fast cold reload).
    func clearMemoryCache() {
        cache.removeAllObjects()
    }

    static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: Coalesced bounded decoding + disk thumbnail cache

    private func loadCoalesced(
        key: String,
        queue: OperationQueue,
        work: @escaping @Sendable (@escaping () -> Bool) -> UIImage?
    ) async -> UIImage? {
        if Task.isCancelled { return nil }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                enum Registration { case cancelledEarly, joinedExisting, start(InFlightLoad) }
                let registration: Registration = inFlightLock.withLock {
                    if Task.isCancelled { return .cancelledEarly }
                    if let existing = inFlight[key] {
                        existing.waiters.append((waiterID, { continuation.resume(returning: $0) }))
                        return .joinedExisting
                    }
                    let load = InFlightLoad()
                    load.waiters.append((waiterID, { continuation.resume(returning: $0) }))
                    inFlight[key] = load
                    return .start(load)
                }
                let load: InFlightLoad
                switch registration {
                case .cancelledEarly:
                    continuation.resume(returning: nil)
                    return
                case .joinedExisting:
                    return
                case .start(let created):
                    load = created
                }
                let op = load.op
                op.addExecutionBlock { [weak self, weak op] in
                    guard let self else { return }
                    let result = (op?.isCancelled == true) ? nil : work { op?.isCancelled == true }
                    let waiters = self.inFlightLock.withLock { () -> [(id: UUID, resume: (UIImage?) -> Void)] in
                        guard self.inFlight[key] === load else { return [] }
                        self.inFlight.removeValue(forKey: key)
                        let pending = load.waiters
                        load.waiters.removeAll()
                        return pending
                    }
                    for waiter in waiters { waiter.resume(result) }
                }
                op.completionBlock = { [weak self] in
                    guard let self else { return }
                    let leftover = self.inFlightLock.withLock { () -> [(id: UUID, resume: (UIImage?) -> Void)] in
                        guard self.inFlight[key] === load else { return [] }
                        self.inFlight.removeValue(forKey: key)
                        let pending = load.waiters
                        load.waiters.removeAll()
                        return pending
                    }
                    for waiter in leftover { waiter.resume(nil) }
                }
                queue.addOperation(op)
            }
        } onCancel: {
            let cancelled: ((UIImage?) -> Void)? = inFlightLock.withLock {
                guard let entry = inFlight[key],
                      let idx = entry.waiters.firstIndex(where: { $0.id == waiterID }) else { return nil }
                let removed = entry.waiters.remove(at: idx)
                if entry.waiters.isEmpty {
                    inFlight.removeValue(forKey: key)
                    entry.op.cancel()
                }
                return removed.resume
            }
            cancelled?(nil)
        }
    }

    private func decodeAudioCover(
        url: URL,
        path: String,
        maxPixels: Int,
        revision: Int,
        key: String,
        missKey: String,
        isCancelled: () -> Bool
    ) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if isCancelled() { return nil }
        let thumbURL = maxPixels <= Self.diskCacheMaxPixels ? diskThumbnailURL(path: path, maxPixels: maxPixels, revision: revision) : nil
        if let thumbURL, let diskImage = readDiskThumbnail(at: thumbURL, maxPixels: maxPixels) {
            storeInMemory(diskImage, forKey: key)
            return diskImage
        }
        if isCancelled() { return nil }
        guard let data = TagReader.artwork(url) else {
            misses.setObject(1, forKey: missKey as NSString)
            return nil
        }
        if isCancelled() { return nil }
        guard let image = Self.downsample(data, maxPixels: maxPixels) else { return nil }
        storeInMemory(image, forKey: key)
        if let thumbURL { writeDiskThumbnail(image, to: thumbURL) }
        return image
    }

    private func decodeFileCover(
        path: String,
        maxPixels: Int,
        revision: Int,
        key: String,
        isCancelled: () -> Bool
    ) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if isCancelled() { return nil }
        let thumbURL = maxPixels <= Self.diskCacheMaxPixels ? diskThumbnailURL(path: path, maxPixels: maxPixels, revision: revision) : nil
        if let thumbURL, let diskImage = readDiskThumbnail(at: thumbURL, maxPixels: maxPixels) {
            storeInMemory(diskImage, forKey: key)
            return diskImage
        }
        if isCancelled() { return nil }
        guard let data = FileManager.default.contents(atPath: path),
              !isCancelled(),
              let image = Self.downsample(data, maxPixels: maxPixels) else { return nil }
        storeInMemory(image, forKey: key)
        if let thumbURL { writeDiskThumbnail(image, to: thumbURL) }
        return image
    }

    private func storeInMemory(_ image: UIImage, forKey key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func diskThumbnailURL(path: String, maxPixels: Int, revision: Int) -> URL {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let raw = "\(path)|\(maxPixels)|\(revision)|\(Int64(mtime))|\(size)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return thumbDirectory.appendingPathComponent("\(hex).jpg")
    }

    private func readDiskThumbnail(at url: URL, maxPixels: Int) -> UIImage? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return Self.downsample(data, maxPixels: maxPixels)
    }

    private func writeDiskThumbnail(_ image: UIImage, to url: URL) {
        diskWriteQueue.async { [weak self] in
            guard let self, let jpeg = image.jpegData(compressionQuality: 0.84) else { return }
            try? jpeg.write(to: url, options: [.atomic])
            let shouldPrune: Bool = self.writeCountLock.withLock {
                self.diskWritesSincePrune += 1
                if self.diskWritesSincePrune >= 80 {
                    self.diskWritesSincePrune = 0
                    return true
                }
                return false
            }
            if shouldPrune { self.pruneDiskCacheIfNeeded() }
        }
    }

    private func pruneDiskCacheIfNeeded() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? fm.contentsOfDirectory(at: thumbDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        var totalBytes: Int64 = 0
        var entries: [(url: URL, date: Date, size: Int64)] = []
        entries.reserveCapacity(urls.count)
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? .distantPast
            totalBytes += size
            entries.append((url, date, size))
        }
        guard totalBytes > Self.diskCacheMaxBytes || entries.count > Self.diskCacheMaxFiles else { return }
        entries.sort { $0.date < $1.date }
        let targetBytes = Self.diskCacheMaxBytes * 3 / 4
        let targetFiles = Self.diskCacheMaxFiles * 3 / 4
        var remainingCount = entries.count
        for entry in entries {
            guard totalBytes > targetBytes || remainingCount > targetFiles else { break }
            try? fm.removeItem(at: entry.url)
            totalBytes -= entry.size
            remainingCount -= 1
        }
    }
}
