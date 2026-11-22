import Foundation

/// A web page that opens in the default browser (`web_locations` in the local settings.json).
/// Only https:// addresses are accepted; they are never navigated as folders.
///
/// ```json
/// { "web_locations": [ { "title": "Wiki", "url": "https://wiki.example/home", "notes": "team docs", "symbol": "book" } ] }
/// ```
public struct WebLocation: Sendable, Equatable, Identifiable {
    public var title: String
    public var url: String
    public var notes: String
    public var symbol: String
    public var id: String { url }
    public init(title: String, url: String, notes: String = "", symbol: String = "globe") {
        self.title = title; self.url = url; self.notes = notes; self.symbol = symbol
    }
}

public enum WebLocations {
    public static let limit = 2000
    /// The sidebar shows this many, then "All N Web Locations…".
    public static let sidebarCount = 10
    public enum AddResult: Sendable { case added, alreadyThere, invalid, full, failed }

    /// A valid https URL, or nil.
    public static func validURL(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), u.scheme?.lowercased() == "https", let h = u.host, !h.isEmpty else { return nil }
        return u
    }

    public static func load(from url: URL = AppPaths.settingsURL) -> [WebLocation] {
        guard let list = SettingsFile.read(url)["web_locations"] as? [[String: Any]] else { return [] }
        var out: [WebLocation] = []
        for d in list.prefix(limit) {
            guard let s = d["url"] as? String, let u = validURL(s) else { continue }
            out.append(WebLocation(title: (d["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? u.host ?? s,
                                   url: u.absoluteString, notes: d["notes"] as? String ?? "",
                                   symbol: (d["symbol"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "globe"))
        }
        return out
    }

    @discardableResult
    public static func add(title: String, url: String, notes: String = "", at file: URL = AppPaths.settingsURL) -> AddResult {
        guard let u = validURL(url) else { return .invalid }
        var obj = SettingsFile.read(file)
        var list = obj["web_locations"] as? [[String: Any]] ?? []
        if list.contains(where: { ($0["url"] as? String) == u.absoluteString }) { return .alreadyThere }
        guard list.count < limit else { return .full }
        var item: [String: Any] = ["title": title.isEmpty ? (u.host ?? u.absoluteString) : title, "url": u.absoluteString]
        if !notes.isEmpty { item["notes"] = notes }
        list.append(item)
        obj["web_locations"] = list
        return SettingsFile.write(obj, to: file) ? .added : .failed
    }

    @discardableResult
    public static func remove(url: String, at file: URL = AppPaths.settingsURL) -> Bool {
        var obj = SettingsFile.read(file)
        guard var list = obj["web_locations"] as? [[String: Any]] else { return false }
        let before = list.count
        list.removeAll { ($0["url"] as? String) == url }
        guard list.count != before else { return false }
        obj["web_locations"] = list
        return SettingsFile.write(obj, to: file)
    }

    /// Every word must match the title, URL or notes (case-insensitive).
    public static func search(_ items: [WebLocation], _ query: String) -> [WebLocation] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { i in
            let hay = (i.title + " " + i.url + " " + i.notes).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
}
