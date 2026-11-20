import Foundation

/// Both targets resolve the same provisioned group, including identifiers renamed by a signer.
enum PlayerWidgetStorage {
    static let defaultGroup = "group.com.amp.player"
    static let legacyGroup = "group.com.erhu.player"

    static func identifiers(profile: Data?, configured: String = defaultGroup) -> [String] {
        let groups = profile.flatMap(profileGroups) ?? []
        let matching = groups.filter {
            !$0.contains("*") && ($0 == configured || $0.contains("com.amp.player") || $0.contains("com.erhu.player"))
        }
        var result: [String] = []
        for group in matching + [configured, legacyGroup] where !result.contains(group) { result.append(group) }
        return result
    }

    static func profileGroups(_ data: Data) -> [String]? {
        // Provisioning profiles wrap an XML plist in a CMS envelope. No certificate material
        // is exported; only this process's own permitted application groups are inspected.
        let xml: Data
        if data.starts(with: Data("bplist".utf8)) { xml = data }
        else {
            guard let start = data.range(of: Data("<?xml".utf8)),
                  let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
            xml = Data(data[start.lowerBound..<end.upperBound])
        }
        guard let value = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
              let entitlements = value["Entitlements"] as? [String: Any] else { return nil }
        return entitlements["com.apple.security.application-groups"] as? [String]
    }

    static func resolve(identifiers: [String], container: (String) -> URL?) -> (group: String, folder: URL)? {
        for group in identifiers {
            if let folder = container(group) { return (group, folder) }
        }
        return nil
    }

    static let shared: (group: String, folder: URL)? = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "AmpWidgetAppGroup") as? String ?? defaultGroup
        let profile = try? Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision"))
        let storage = resolve(identifiers: identifiers(profile: profile, configured: configured)) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
        if let storage, !FileManager.default.fileExists(atPath: storage.folder.appendingPathComponent("player.json").path),
           let legacy = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: legacyGroup),
           legacy != storage.folder {
            // A patched signer maps each requested group to its own subfolder. Copy the old
            // cover first, then metadata; leave the source available to existing widget entries.
            let source = legacy.appendingPathComponent("player.json")
            if let data = try? Data(contentsOf: source),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let filename = json["artworkFileName"] as? String ?? "cover.jpg"
                if filename == (filename as NSString).lastPathComponent {
                    let destination = storage.folder.appendingPathComponent(filename)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try? FileManager.default.copyItem(at: legacy.appendingPathComponent(filename), to: destination)
                    }
                }
                try? FileManager.default.copyItem(at: source, to: storage.folder.appendingPathComponent("player.json"))
            }
        }
        return storage
    }()
}
