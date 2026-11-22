import Foundation

public enum HistoryKind: String, Sendable, CaseIterable { case folder, fileOpen, fileOp, command }

public struct HistoryEntry: Identifiable, Sendable, Equatable {
    public var id: String
    public var kind: HistoryKind
    public var at: String          // ISO 8601 UTC
    public var title: String
    public var detail: String
    public var folder: String?     // folder to open on double-click
    var table: String, column: String, key: DBValue
}

extension HistoryEntry {
    static let opSymbols = ["copy": "📋", "move": "➡️", "trash": "🗑️", "rename": "✏️", "create": "➕"]

    /// What the History window shows: the leading operation word becomes a symbol.
    /// `title` keeps the plain word (CSV export and search use it).
    public var displayTitle: String {
        guard kind == .fileOp, let space = title.firstIndex(of: " ") else {
            if kind == .fileOp, let sym = Self.opSymbols[title] { return sym }
            return title
        }
        let word = String(title[..<space])
        guard let sym = Self.opSymbols[word] else { return title }
        return sym + title[space...]
    }
}

extension FinderStore {
    public func logFileOp(batch: String, op: String, src: String?, dst: String?, result: String, actor: String) throws {
        try db.exec("INSERT INTO file_ops(batch_id,op,src,dst,result,actor,at) VALUES(?,?,?,?,?,?,?)",
                    [.text(batch), .text(op), src.map { .text($0) } ?? .null, dst.map { .text($0) } ?? .null,
                     .text(result), .text(actor), .text(iso8601Now())])
    }

    private static func match(_ cols: [String], _ search: String) -> (String, [DBValue]) {
        let words = search.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ("", []) }
        let hay = cols.map { "COALESCE(\($0),'')" }.joined(separator: "||' '||")
        return (" WHERE " + words.map { _ in "(\(hay)) LIKE ?" }.joined(separator: " AND "),
                words.map { .text("%\($0)%") })
    }

    private func dir(_ p: String?) -> String? { p.map { ($0 as NSString).deletingLastPathComponent } }

    /// Newest first. Every search word must match somewhere in the row.
    public func history(_ kind: HistoryKind, search: String = "", limit: Int = 500) throws -> [HistoryEntry] {
        let lim = DBValue.int(Int64(limit))
        switch kind {
        case .folder:
            let (w, a) = Self.match(["path", "source"], search)
            return try db.query("SELECT id,path,source,visited_at FROM nav_history\(w) ORDER BY id DESC LIMIT ?", a + [lim]).map {
                HistoryEntry(id: "nav:\($0["id"]?.int ?? 0)", kind: .folder, at: $0["visited_at"]?.string ?? "",
                             title: $0["path"]?.string ?? "", detail: $0["source"]?.string ?? "",
                             folder: $0["path"]?.string, table: "nav_history", column: "id", key: $0["id"] ?? .null)
            }
        case .fileOpen:
            let (w, a) = Self.match(["path", "app"], search)
            return try db.query("SELECT id,path,app,opened_at FROM file_opens\(w) ORDER BY id DESC LIMIT ?", a + [lim]).map {
                HistoryEntry(id: "open:\($0["id"]?.int ?? 0)", kind: .fileOpen, at: $0["opened_at"]?.string ?? "",
                             title: $0["path"]?.string ?? "", detail: $0["app"]?.string ?? "",
                             folder: dir($0["path"]?.string), table: "file_opens", column: "id", key: $0["id"] ?? .null)
            }
        case .fileOp:
            let (w, a) = Self.match(["op", "src", "dst", "result", "actor"], search)
            return try db.query("SELECT * FROM file_ops\(w) ORDER BY id DESC LIMIT ?", a + [lim]).map {
                let src = $0["src"]?.string, dst = $0["dst"]?.string
                let title = [($0["op"]?.string ?? ""), src ?? "", dst.map { "→ " + $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
                return HistoryEntry(id: "op:\($0["id"]?.int ?? 0)", kind: .fileOp, at: $0["at"]?.string ?? "", title: title,
                                    detail: "\($0["result"]?.string ?? "") · \($0["actor"]?.string ?? "")",
                                    folder: dst.map { ($0 as NSString).deletingLastPathComponent } ?? dir(src),
                                    table: "file_ops", column: "id", key: $0["id"] ?? .null)
            }
        case .command:
            let (w, a) = Self.match(["command", "folder"], search)
            return try db.query("SELECT * FROM command_runs\(w) ORDER BY id DESC LIMIT ?", a + [lim]).map {
                let code = $0["exit_code"]?.int.map { "exit \($0)" } ?? "running"
                return HistoryEntry(id: "cmd:\($0["id"]?.int ?? 0)", kind: .command, at: $0["started_at"]?.string ?? "",
                                    title: $0["command"]?.string ?? "", detail: code, folder: $0["folder"]?.string,
                                    table: "command_runs", column: "id", key: $0["id"] ?? .null)
            }
        }
    }

    /// Everything merged, newest first; file operations of one batch collapse into one row.
    public func timeline(search: String = "", limit: Int = 500) throws -> [HistoryEntry] {
        var all = try history(.folder, search: search, limit: limit) + history(.fileOpen, search: search, limit: limit)
            + history(.command, search: search, limit: limit)
        let (w, a) = Self.match(["op", "src", "dst", "result", "actor"], search)
        let rows = try db.query("SELECT * FROM file_ops\(w) ORDER BY id DESC LIMIT ?", a + [.int(Int64(limit))])
        var order: [String] = [], groups: [String: [[String: DBValue]]] = [:]
        for r in rows { let b = r["batch_id"]?.string ?? ""; if groups[b] == nil { order.append(b) }; groups[b, default: []].append(r) }
        for b in order {
            let g = groups[b]!, first = g[0]
            let dst = first["dst"]?.string, op = first["op"]?.string ?? ""
            let done = g.filter { $0["result"]?.string == "done" }.count
            let title = g.count == 1
                ? [op, first["src"]?.string ?? "", dst.map { "→ " + $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
                : "\(op) \(g.count) items → \(dst ?? "")"
            all.append(HistoryEntry(id: "batch:\(b)", kind: .fileOp, at: first["at"]?.string ?? "", title: title,
                                    detail: "\(done)/\(g.count) done · \(first["actor"]?.string ?? "")",
                                    folder: dst.map { ($0 as NSString).deletingLastPathComponent } ?? dir(first["src"]?.string),
                                    table: "file_ops", column: "batch_id", key: .text(b)))
        }
        return Array(all.sorted { $0.at > $1.at }.prefix(limit))
    }

    public func delete(_ entry: HistoryEntry) throws {
        try db.exec("DELETE FROM \(entry.table) WHERE \(entry.column)=?", [entry.key])
    }

    public func clear(_ kind: HistoryKind?) throws {
        let tables = kind.map { [Self.table(for: $0)] } ?? HistoryKind.allCases.map(Self.table(for:))
        for t in tables { try db.exec("DELETE FROM \(t)") }
    }

    private static func table(for k: HistoryKind) -> String {
        switch k { case .folder: "nav_history"; case .fileOpen: "file_opens"; case .fileOp: "file_ops"; case .command: "command_runs" }
    }

    /// Retention: drop rows older than `days` (0 = keep everything).
    public func purgeHistory(olderThanDays days: Int, now: Date = Date()) throws {
        guard days > 0 else { return }
        let cutoff = iso8601(now.addingTimeInterval(-Double(days) * 86400))
        for (t, c) in [("nav_history", "visited_at"), ("file_opens", "opened_at"), ("file_ops", "at"), ("command_runs", "started_at")] {
            try db.exec("DELETE FROM \(t) WHERE \(c) < ?", [.text(cutoff)])
        }
    }

    public static func csv(_ entries: [HistoryEntry]) -> String {
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let local = DateFormatter(); local.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        var out = "kind,time_utc,time_local,item,detail,folder\n"
        for e in entries {
            let l = parseISO8601(e.at).map { local.string(from: $0) } ?? ""
            out += [e.kind.rawValue, e.at, l, e.title, e.detail, e.folder ?? ""].map(esc).joined(separator: ",") + "\n"
        }
        return out
    }
}
