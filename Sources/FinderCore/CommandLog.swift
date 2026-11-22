import Foundation

extension FinderStore {
    /// Record that a command started; returns the row to finish later.
    public func logCommandStart(tabID: UUID?, folder: String, command: String) -> Int64? {
        do {
            try db.exec("INSERT INTO command_runs(tab_id,folder,command,started_at) VALUES(?,?,?,?)",
                        [tabID.map { .text($0.uuidString) } ?? .null, .text(folder), .text(command), .text(iso8601Now())])
            return db.lastInsertRowID
        } catch { return nil }
    }
    public func logCommandEnd(id: Int64, exitCode: Int32) {
        try? db.exec("UPDATE command_runs SET exit_code=?, ended_at=? WHERE id=?", [.int(Int64(exitCode)), .text(iso8601Now()), .int(id)])
    }
}
