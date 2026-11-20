import Foundation

/// Last successfully read widget entry, private to its extension. A transient shared-group
/// lookup or file read must not replace the existing widget with an empty dark placeholder.
struct PlayerWidgetArchive: Codable {
    var snapshot: PlayerWidgetSnapshot
    var artwork: Data?
    static func load(in folder: URL) -> Self? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("last-entry.json")) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save(in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent("last-entry.json"), options: options)
    }
}
