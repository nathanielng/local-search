import Foundation

/// A OneDrive folder: found under ~/Library/CloudStorage, or added by hand (`onedrive_folders` in the
/// local settings.json).
public struct CloudFolder: Sendable, Equatable, Identifiable {
    public var title: String
    public var path: String
    public var manual: Bool
    public var id: String { path }
    public init(title: String, path: String, manual: Bool = false) { self.title = title; self.path = path; self.manual = manual }
}

public enum Cloud {
    /// The OneDrive app: standalone and Mac App Store builds. Used only to show a "running" dot.
    public static let oneDriveBundleIDs = ["com.microsoft.OneDrive", "com.microsoft.OneDrive-mac"]

    public static var storageDir: URL { URL(fileURLWithPath: AppPaths.home).appendingPathComponent("Library/CloudStorage") }

    /// "OneDrive" stays "OneDrive"; "OneDrive-Name" becomes "OneDrive – Name".
    public static func title(forFolderName name: String) -> String {
        guard name.hasPrefix("OneDrive-") else { return name }
        return "OneDrive – " + name.dropFirst("OneDrive-".count)
    }

    public static func discover(in dir: URL = storageDir) -> [CloudFolder] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("OneDrive") }.sorted().compactMap { n in
            let u = dir.appendingPathComponent(n)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return CloudFolder(title: title(forFolderName: n), path: u.path)
        }
    }

    /// Discovered folders first, then manual ones (a manual path that was also discovered is listed once).
    public static func load(settings: URL = AppPaths.settingsURL, storage: URL = storageDir) -> [CloudFolder] {
        var out = discover(in: storage)
        let list = SettingsFile.read(settings)["onedrive_folders"] as? [[String: Any]] ?? []
        for d in list {
            guard let p = d["path"] as? String, !p.isEmpty else { continue }
            let full = (p as NSString).expandingTildeInPath
            guard !out.contains(where: { $0.path == full }) else { continue }
            out.append(CloudFolder(title: (d["title"] as? String) ?? (full as NSString).lastPathComponent, path: full, manual: true))
        }
        return Array(out.prefix(FinderStore.sidebarLimit))
    }

    @discardableResult
    public static func add(path: String, title: String? = nil, settings: URL = AppPaths.settingsURL) -> Bool {
        var obj = SettingsFile.read(settings)
        var list = obj["onedrive_folders"] as? [[String: Any]] ?? []
        let full = (path as NSString).expandingTildeInPath
        guard !list.contains(where: { ($0["path"] as? String).map { ($0 as NSString).expandingTildeInPath } == full }) else { return false }
        list.append(["title": title ?? (full as NSString).lastPathComponent, "path": full])
        obj["onedrive_folders"] = list
        return SettingsFile.write(obj, to: settings)
    }

    @discardableResult
    public static func remove(path: String, settings: URL = AppPaths.settingsURL) -> Bool {
        var obj = SettingsFile.read(settings)
        guard var list = obj["onedrive_folders"] as? [[String: Any]] else { return false }
        let full = (path as NSString).expandingTildeInPath
        let before = list.count
        list.removeAll { ($0["path"] as? String).map { ($0 as NSString).expandingTildeInPath } == full }
        guard list.count != before else { return false }
        obj["onedrive_folders"] = list
        return SettingsFile.write(obj, to: settings)
    }
}
