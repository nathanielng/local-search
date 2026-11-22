import Foundation

/// A project folder from the local settings.json (`projects`). Like network locations, these live in
/// Application Support and are never part of the repository.
///
/// ```json
/// { "projects": [ { "title": "Client A", "path": "~/Work/client-a" } ] }
/// ```
public struct Project: Sendable, Equatable, Identifiable {
    public var title: String
    public var path: String          // absolute, "~/" expanded
    public var id: String { path }
    public init(title: String, path: String) { self.title = title; self.path = path }
}

public enum Projects {
    public enum AddResult: Sendable { case added, alreadyThere, full, failed }

    public static func load(from url: URL = AppPaths.settingsURL) -> [Project] {
        guard let list = read(url)["projects"] as? [[String: Any]] else { return [] }
        return list.prefix(FinderStore.sidebarLimit).compactMap { d in
            guard let p = d["path"] as? String, !p.isEmpty else { return nil }
            let full = (p as NSString).expandingTildeInPath
            return Project(title: (d["title"] as? String) ?? (full as NSString).lastPathComponent, path: full)
        }
    }

    @discardableResult
    public static func add(path: String, title: String? = nil, at url: URL = AppPaths.settingsURL) -> AddResult {
        var obj = read(url)
        var list = obj["projects"] as? [[String: Any]] ?? []
        let full = (path as NSString).expandingTildeInPath
        if list.contains(where: { (($0["path"] as? String).map { ($0 as NSString).expandingTildeInPath }) == full }) { return .alreadyThere }
        guard list.count < FinderStore.sidebarLimit else { return .full }
        list.append(["title": title ?? (full as NSString).lastPathComponent, "path": full])
        obj["projects"] = list
        return write(obj, to: url) ? .added : .failed
    }

    @discardableResult
    public static func remove(path: String, at url: URL = AppPaths.settingsURL) -> Bool {
        var obj = read(url)
        guard var list = obj["projects"] as? [[String: Any]] else { return false }
        let full = (path as NSString).expandingTildeInPath
        let before = list.count
        list.removeAll { (($0["path"] as? String).map { ($0 as NSString).expandingTildeInPath }) == full }
        guard list.count != before else { return false }
        obj["projects"] = list
        return write(obj, to: url)
    }

    /// Move one project right before or after another (drag to reorder).
    @discardableResult
    public static func move(_ path: String, relativeTo target: String, after: Bool, at url: URL = AppPaths.settingsURL) -> Bool {
        var obj = read(url)
        guard var list = obj["projects"] as? [[String: Any]] else { return false }
        func key(_ d: [String: Any]) -> String? { (d["path"] as? String).map { ($0 as NSString).expandingTildeInPath } }
        guard path != target, let from = list.firstIndex(where: { key($0) == path }) else { return false }
        let item = list.remove(at: from)
        guard let to = list.firstIndex(where: { key($0) == target }) else { return false }
        list.insert(item, at: after ? to + 1 : to)
        obj["projects"] = list
        return write(obj, to: url)
    }

    private static func read(_ url: URL) -> [String: Any] {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    /// Writes the whole object back, so every other key in the file is kept.
    private static func write(_ obj: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
