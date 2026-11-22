import Foundation

public enum AppPaths {
    public static var supportDir: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LocalSearch", isDirectory: true)
        migrateLegacyData(from: base.appendingPathComponent("AgenticFinder", isDirectory: true), to: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// One-time move of the pre-rename data folder (and its database files) to the new name.
    static func migrateLegacyData(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        guard (try? fm.moveItem(at: old, to: new)) != nil else { return }
        for suffix in ["", "-wal", "-shm"] {
            try? fm.moveItem(at: new.appendingPathComponent("agenticfinder.sqlite" + suffix),
                             to: new.appendingPathComponent("localsearch.sqlite" + suffix))
        }
    }
    public static var databaseURL: URL { supportDir.appendingPathComponent("localsearch.sqlite") }
    public static var home: String { NSHomeDirectory() }
}

public func iso8601Now() -> String { iso8601(Date()) }
public func iso8601(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: d)
}
public func parseISO8601(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}
