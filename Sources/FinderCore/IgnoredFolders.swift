import Foundation

/// Folders whose visits and opens are neither recorded nor shown in Recent Locations.
/// The list lives in the local database (kv `ignored_folders`), never in the repository.
extension FinderStore {
    static let ignoredKey = "ignored_folders"

    /// Normalise: expand "~/", standardise, drop a trailing slash. "/" is refused (it would hide everything).
    public static func normalizedIgnored(_ path: String) -> String? {
        var p = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return (p.isEmpty || p == "/") ? nil : p
    }

    public func ignoredFolders() -> [String] {
        guard let s = kv(Self.ignoredKey), let d = s.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return list
    }

    public func setIgnoredFolders(_ list: [String]) {
        var seen = Set<String>(), clean: [String] = []
        for p in list { if let n = Self.normalizedIgnored(p), seen.insert(n).inserted { clean.append(n) } }
        let data = (try? JSONEncoder().encode(clean)) ?? Data("[]".utf8)
        setKV(Self.ignoredKey, String(decoding: data, as: UTF8.self))
    }

    /// True when `path` is an ignored folder or inside one.
    public static func isIgnored(_ path: String, in list: [String]) -> Bool {
        list.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
    public func isIgnored(_ path: String) -> Bool { Self.isIgnored(path, in: ignoredFolders()) }

    /// Delete recorded folder visits and file opens at or under `folder`. Returns how many rows went.
    @discardableResult
    public func deleteHistory(under folder: String) throws -> Int {
        guard let f = Self.normalizedIgnored(folder) else { return 0 }
        let like = f.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "/%"
        var n = 0
        for t in ["nav_history", "file_opens"] {
            n += try db.query("SELECT COUNT(*) AS n FROM \(t) WHERE path=? OR path LIKE ? ESCAPE '\\'", [.text(f), .text(like)]).first?["n"]?.int.map(Int.init) ?? 0
            try db.exec("DELETE FROM \(t) WHERE path=? OR path LIKE ? ESCAPE '\\'", [.text(f), .text(like)])
        }
        return n
    }
}
