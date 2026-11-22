import Foundation

public struct VisitRecord: Sendable, Equatable {
    public var tabID: String, path: String, source: String, at: String
}

public struct FolderStat: Sendable, Equatable {
    public var path: String
    public var visits: Int
    public var estimatedSeconds: Double
}

public struct SidebarItem: Sendable, Equatable {
    public var path: String, title: String
}

/// SQLite persistence shared by the app and the MCP server.
public final class FinderStore: @unchecked Sendable {
    public static let schemaVersion = 6
    public let db: Database

    private let settingsURL: URL?

    /// `settingsURL` is only read when the database is first created (to seed special folders).
    public init(path: String = AppPaths.databaseURL.path, settingsURL: URL? = nil) throws {
        db = try Database(path: path)
        self.settingsURL = settingsURL
        try migrate()
    }

    // MARK: Schema

    private func migrate() throws {
        let v = try db.query("PRAGMA user_version").first?["user_version"]?.int ?? 0
        guard v < Int64(Self.schemaVersion) else { return }
        try db.transaction {
            for sql in Self.schema { try db.exec(sql) }
            try db.exec("PRAGMA user_version = \(Self.schemaVersion)")
        }
        if v == 0 { try seedDefaults() }
    }

    static let schema = [
        """
        CREATE TABLE IF NOT EXISTS tabs(
          id TEXT PRIMARY KEY, position INTEGER NOT NULL, path TEXT NOT NULL,
          back TEXT NOT NULL DEFAULT '[]', forward TEXT NOT NULL DEFAULT '[]',
          sort_key TEXT NOT NULL DEFAULT 'name', sort_asc INTEGER NOT NULL DEFAULT 1,
          selection TEXT NOT NULL DEFAULT '[]',
          is_selected INTEGER NOT NULL DEFAULT 0,
          closed_at TEXT, created_at TEXT NOT NULL)
        """,
        """
        CREATE TABLE IF NOT EXISTS nav_history(
          id INTEGER PRIMARY KEY AUTOINCREMENT, tab_id TEXT NOT NULL,
          path TEXT NOT NULL, source TEXT NOT NULL, visited_at TEXT NOT NULL)
        """,
        "CREATE INDEX IF NOT EXISTS nav_path ON nav_history(path)",
        "CREATE INDEX IF NOT EXISTS nav_time ON nav_history(visited_at)",
        "CREATE TABLE IF NOT EXISTS favorites(id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT UNIQUE NOT NULL, title TEXT NOT NULL, position INTEGER NOT NULL)",
        "CREATE TABLE IF NOT EXISTS special_folders(id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT UNIQUE NOT NULL, title TEXT NOT NULL, position INTEGER NOT NULL)",
        "CREATE TABLE IF NOT EXISTS recent_hidden(path TEXT PRIMARY KEY)",
        """
        CREATE TABLE IF NOT EXISTS file_ops(
          id INTEGER PRIMARY KEY AUTOINCREMENT, batch_id TEXT NOT NULL, op TEXT NOT NULL,
          src TEXT, dst TEXT, result TEXT NOT NULL, actor TEXT NOT NULL, at TEXT NOT NULL)
        """,
        """
        CREATE TABLE IF NOT EXISTS command_runs(
          id INTEGER PRIMARY KEY AUTOINCREMENT, tab_id TEXT, folder TEXT, command TEXT NOT NULL,
          exit_code INTEGER, started_at TEXT NOT NULL, ended_at TEXT)
        """,
        "CREATE TABLE IF NOT EXISTS file_opens(id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL, opened_at TEXT NOT NULL, app TEXT)",
        "CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)",
    ]

    private func seedDefaults() throws {
        let h = AppPaths.home
        for (i, n) in ["Desktop", "Documents", "Downloads"].enumerated() {
            try addFavorite(path: "\(h)/\(n)", title: n, position: i)
        }
        try addFavorite(path: "/Applications", title: "Applications", position: 3)
        // Special folders are personal, so they are never hard-coded: a new database takes them from the
        // local settings.json (`special_folders`: [{"title": …, "path": …}]), if present.
        if let url = settingsURL { try seedSpecialFolders(from: url) }
    }

    /// Reads `special_folders` from a settings.json. Paths may start with `~/`. Missing file or key: nothing happens.
    public func seedSpecialFolders(from url: URL) throws {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["special_folders"] as? [[String: Any]] else { return }
        for item in list.prefix(Self.sidebarLimit) {
            guard let path = item["path"] as? String else { continue }
            let full = (path as NSString).expandingTildeInPath
            try addSpecialFolder(path: full, title: item["title"] as? String)
        }
    }

    @discardableResult
    public func addSpecialFolder(path: String, title: String? = nil) throws -> Bool {
        let count = try db.query("SELECT COUNT(*) AS n FROM special_folders").first?["n"]?.int ?? 0
        guard count < Int64(Self.sidebarLimit) else { return false }
        try db.exec("INSERT OR IGNORE INTO special_folders(path,title,position) VALUES(?,?,?)",
                    [.text(path), .text(title ?? (path as NSString).lastPathComponent), .int(count)])
        return true
    }

    public func removeSpecialFolder(path: String) throws { try db.exec("DELETE FROM special_folders WHERE path=?", [.text(path)]) }

    // MARK: Tabs

    public func saveTabs(_ tabs: [TabState], selected: UUID?) throws {
        let enc = JSONEncoder()
        func j<T: Encodable>(_ v: T) -> String { String(data: (try? enc.encode(v)) ?? Data("[]".utf8), encoding: .utf8)! }
        try db.transaction {
            for (i, t) in tabs.enumerated() {
                try db.exec("""
                INSERT INTO tabs(id,position,path,back,forward,sort_key,sort_asc,selection,is_selected,closed_at,created_at)
                VALUES(?,?,?,?,?,?,?,?,?,NULL,?)
                ON CONFLICT(id) DO UPDATE SET position=excluded.position, path=excluded.path, back=excluded.back,
                  forward=excluded.forward, sort_key=excluded.sort_key, sort_asc=excluded.sort_asc,
                  selection=excluded.selection, is_selected=excluded.is_selected, closed_at=NULL
                """, [.text(t.id.uuidString), .int(Int64(i)), .text(t.path), .text(j(t.back)), .text(j(t.forward)),
                      .text(t.sortKey), .int(t.sortAscending ? 1 : 0), .text(j(t.selection)),
                      .int(t.id == selected ? 1 : 0), .text(iso8601Now())])
            }
        }
    }

    /// Mark a tab closed. Its history rows stay.
    public func closeTab(_ id: UUID, state: TabState) throws {
        try saveTabs([state], selected: nil)
        try db.exec("UPDATE tabs SET closed_at=?, position=-1, is_selected=0 WHERE id=?", [.text(iso8601Now()), .text(id.uuidString)])
        try db.exec("""
        UPDATE tabs SET closed_at='1970-01-01T00:00:00.000Z' WHERE closed_at IS NOT NULL AND id NOT IN
          (SELECT id FROM tabs WHERE closed_at IS NOT NULL ORDER BY closed_at DESC LIMIT 100)
        """)
    }

    public func loadOpenTabs() throws -> (tabs: [TabState], selected: UUID?) {
        let rows = try db.query("SELECT * FROM tabs WHERE closed_at IS NULL ORDER BY position")
        var selected: UUID?
        let tabs = rows.compactMap { Self.tab(from: $0) }
        for r in rows where r["is_selected"]?.int == 1 { selected = UUID(uuidString: r["id"]?.string ?? "") }
        return (tabs, selected)
    }

    /// Most recently closed tabs, newest first (original UUID and stacks).
    public func closedTabs(limit: Int = 100) throws -> [TabState] {
        try db.query("SELECT * FROM tabs WHERE closed_at IS NOT NULL AND closed_at > '1971' ORDER BY closed_at DESC LIMIT ?",
                     [.int(Int64(limit))]).compactMap { Self.tab(from: $0) }
    }

    static func tab(from r: [String: DBValue]) -> TabState? {
        guard let idS = r["id"]?.string, let id = UUID(uuidString: idS), let path = r["path"]?.string else { return nil }
        func arr(_ k: String) -> [String] {
            (try? JSONDecoder().decode([String].self, from: Data((r[k]?.string ?? "[]").utf8))) ?? []
        }
        return TabState(id: id, path: path, back: arr("back"), forward: arr("forward"),
                        sortKey: r["sort_key"]?.string ?? "name", sortAscending: r["sort_asc"]?.int != 0,
                        selection: arr("selection"))
    }

    // MARK: History

    public func logVisit(tabID: UUID, path: String, source: NavSource) throws {
        try db.exec("INSERT INTO nav_history(tab_id,path,source,visited_at) VALUES(?,?,?,?)",
                    [.text(tabID.uuidString), .text(path), .text(source.rawValue), .text(iso8601Now())])
    }

    public func navigationHistory(limit: Int = 100, search: String? = nil) throws -> [VisitRecord] {
        var sql = "SELECT * FROM nav_history"
        var args: [DBValue] = []
        if let s = search, !s.isEmpty { sql += " WHERE path LIKE ?"; args.append(.text("%\(s)%")) }
        sql += " ORDER BY id DESC LIMIT ?"; args.append(.int(Int64(limit)))
        return try db.query(sql, args).map {
            VisitRecord(tabID: $0["tab_id"]?.string ?? "", path: $0["path"]?.string ?? "",
                        source: $0["source"]?.string ?? "", at: $0["visited_at"]?.string ?? "")
        }
    }

    /// Folders ranked by estimated time: the gap to the next visit, capped at 30 minutes.
    public func foldersVisited(limit: Int = 50, gapCap: TimeInterval = 1800) throws -> [FolderStat] {
        let rows = try db.query("SELECT path, visited_at FROM nav_history ORDER BY id")
        var stats: [String: (Int, Double)] = [:]
        for (i, r) in rows.enumerated() {
            guard let p = r["path"]?.string, let t = r["visited_at"]?.string.flatMap(parseISO8601) else { continue }
            var gap = gapCap
            if i + 1 < rows.count, let n = rows[i + 1]["visited_at"]?.string.flatMap(parseISO8601) {
                gap = min(max(n.timeIntervalSince(t), 0), gapCap)
            }
            let cur = stats[p] ?? (0, 0)
            stats[p] = (cur.0 + 1, cur.1 + gap)
        }
        return stats.map { FolderStat(path: $0.key, visits: $0.value.0, estimatedSeconds: $0.value.1) }
            .sorted { $0.estimatedSeconds > $1.estimatedSeconds }.prefix(limit).map { $0 }
    }

    public func deleteVisits(toFolder path: String) throws {
        try db.exec("DELETE FROM nav_history WHERE path=?", [.text(path)])
    }

    public func clearHistory() throws { try db.exec("DELETE FROM nav_history") }

    // MARK: Sidebar lists

    public func favorites() throws -> [SidebarItem] { try items("favorites") }
    public func specialFolders() throws -> [SidebarItem] { try items("special_folders") }

    private func items(_ table: String) throws -> [SidebarItem] {
        try db.query("SELECT path,title FROM \(table) ORDER BY position, id").map {
            SidebarItem(path: $0["path"]?.string ?? "", title: $0["title"]?.string ?? "")
        }
    }

    public static let sidebarLimit = 20

    @discardableResult
    public func addFavorite(path: String, title: String? = nil, position: Int? = nil) throws -> Bool {
        let count = try db.query("SELECT COUNT(*) AS n FROM favorites").first?["n"]?.int ?? 0
        guard count < Int64(Self.sidebarLimit) else { return false }
        let pos = Int64(position ?? Int(count))
        try db.exec("INSERT OR IGNORE INTO favorites(path,title,position) VALUES(?,?,?)",
                    [.text(path), .text(title ?? (path as NSString).lastPathComponent), .int(pos)])
        return true
    }

    /// Add a favorite right before `before`, right after `after`, or at the end. An existing favorite is left where it is.
    @discardableResult
    public func insertFavorite(path: String, after: String?, before: String? = nil, title: String? = nil) throws -> Bool {
        let items = try favorites()
        guard !items.contains(where: { $0.path == path }) else { return true }
        guard items.count < Self.sidebarLimit else { return false }
        var order = items.map { ($0.path, $0.title) }
        let new = (path, title ?? (path as NSString).lastPathComponent)
        if let b = before, let i = order.firstIndex(where: { $0.0 == b }) { order.insert(new, at: i) }
        else if let a = after, let i = order.firstIndex(where: { $0.0 == a }) { order.insert(new, at: i + 1) }
        else { order.append(new) }
        try db.transaction {
            try db.exec("DELETE FROM favorites")
            for (i, o) in order.enumerated() {
                try db.exec("INSERT INTO favorites(path,title,position) VALUES(?,?,?)", [.text(o.0), .text(o.1), .int(Int64(i))])
            }
        }
        return true
    }

    /// Reorder by dragging: put `path` just before or after `target` within the same list.
    @discardableResult
    public func moveFavorite(_ path: String, relativeTo target: String, after: Bool) throws -> Bool {
        try reorder("favorites", path, target, after)
    }

    @discardableResult
    public func moveSpecialFolder(_ path: String, relativeTo target: String, after: Bool) throws -> Bool {
        try reorder("special_folders", path, target, after)
    }

    private func reorder(_ table: String, _ path: String, _ target: String, _ after: Bool) throws -> Bool {
        var order = try items(table).map(\.path)
        guard path != target, order.contains(path), order.contains(target) else { return false }
        order.removeAll { $0 == path }
        let i = order.firstIndex(of: target)!
        order.insert(path, at: after ? i + 1 : i)
        try db.transaction {
            for (n, p) in order.enumerated() {
                try db.exec("UPDATE \(table) SET position=? WHERE path=?", [.int(Int64(n)), .text(p)])
            }
        }
        return true
    }

    public func removeFavorite(path: String) throws { try db.exec("DELETE FROM favorites WHERE path=?", [.text(path)]) }

    public func isFavorite(_ path: String) -> Bool {
        ((try? db.query("SELECT 1 AS x FROM favorites WHERE path=?", [.text(path)])) ?? []).isEmpty == false
    }

    // MARK: kv

    public func kv(_ key: String) -> String? {
        try? db.query("SELECT value FROM kv WHERE key=?", [.text(key)]).first?["value"]?.string
    }
    public func setKV(_ key: String, _ value: String) {
        try? db.exec("INSERT INTO kv(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(key), .text(value)])
    }
    public func deleteKV(_ key: String) { try? db.exec("DELETE FROM kv WHERE key=?", [.text(key)]) }
}
