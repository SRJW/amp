import Darwin
import Foundation

/// Watches the app's music folder (and its subdirectories) via kernel VNODE events so files added
/// through the Files app, AirDrop, Finder, or other apps appear automatically without pull-to-refresh.
final class MusicFolderWatcher: @unchecked Sendable {
    private static let maxWatchedDirectories = 128
    private static let debounceInterval: DispatchTimeInterval = .milliseconds(350)
    private static let settleFollowUpInterval: DispatchTimeInterval = .milliseconds(1500)

    private let folder: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "amp.music.folder.watcher", qos: .utility)

    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var debounceWork: DispatchWorkItem?
    private var settleWork: DispatchWorkItem?
    private var isRunning = false

    init(folder: URL = LibraryPaths.musicFolder, onChange: @escaping @Sendable () -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.refreshWatchedDirectoriesLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.debounceWork?.cancel()
            self.debounceWork = nil
            self.settleWork?.cancel()
            self.settleWork = nil
            for source in self.sources.values {
                source.cancel()
            }
            self.sources.removeAll()
        }
    }

    private func refreshWatchedDirectoriesLocked() {
        guard isRunning else { return }
        let directories = collectDirectories()
        let desired = Set(directories)

        for (path, source) in sources where !desired.contains(path) {
            source.cancel()
            sources.removeValue(forKey: path)
        }

        for path in directories where sources[path] == nil {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleChangeLocked()
            }
            source.setCancelHandler {
                close(fd)
            }
            sources[path] = source
            source.resume()
        }
    }

    private func scheduleChangeLocked() {
        guard isRunning else { return }
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.refreshWatchedDirectoriesLocked()
            self.onChange()
            self.scheduleSettleCheckIfNeededLocked()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    /// If a large file (e.g. FLAC/ALAC via Files or AirDrop) was still being written when the first
    /// directory event fired, run one lightweight follow-up scan once the copy finishes settling.
    private func scheduleSettleCheckIfNeededLocked() {
        settleWork?.cancel()
        guard hasRecentlyModifiedFile() else { return }
        let followUp = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.refreshWatchedDirectoriesLocked()
            self.onChange()
        }
        settleWork = followUp
        queue.asyncAfter(deadline: .now() + Self.settleFollowUpInterval, execute: followUp)
    }

    private func hasRecentlyModifiedFile() -> Bool {
        let cutoff = Date().addingTimeInterval(-2.5)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        for case let url as URL in enumerator where LibraryScanner.audioExtensions.contains(url.pathExtension.lowercased()) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            if (values.fileSize ?? 0) == 0 { return true }
            if let modified = values.contentModificationDate, modified > cutoff { return true }
        }
        return false
    }

    private func collectDirectories() -> [String] {
        var result: [String] = [folder.path]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }

        // Prefer shallower directories first if a library has more subdirectories than the cap.
        var subdirectories: [(path: String, depth: Int)] = []
        let rootDepth = folder.pathComponents.count
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory == true else { continue }
            subdirectories.append((url.path, max(0, url.pathComponents.count - rootDepth)))
        }
        subdirectories.sort { a, b in
            if a.depth != b.depth { return a.depth < b.depth }
            return a.path < b.path
        }
        for entry in subdirectories.prefix(Self.maxWatchedDirectories - 1) {
            result.append(entry.path)
        }
        return result
    }
}
