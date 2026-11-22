import Foundation

public struct QuickFindResult: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var score: Double
}

/// Ranking for Quick Find: how well the name matches, where the item is, and how often you use it.
public enum QuickFind {
    static let noise = ["/Library/", "/.Trash/", "/node_modules/", "/.git/", "/.build/", "/DerivedData/", "/Caches/", "/.cache/", "/__pycache__/"]

    /// Every word must match the name (or, weakly, a parent folder). Returns nil when one doesn't.
    static func nameScore(name: String, path: String, words: [String]) -> Double? {
        let lname = name.lowercased(), lpath = path.lowercased()
        let tokens = lname.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var total = 0.0
        for w in words {
            if lname.hasPrefix(w) { total += 40 }
            else if tokens.contains(where: { $0.hasPrefix(w) }) { total += 30 }
            else if lname.contains(w) { total += 20 }
            else if lpath.contains(w) { total += 5 }
            else { return nil }
        }
        var score = total / Double(words.count)
        if lname == words.joined(separator: " ") || (lname as NSString).deletingPathExtension == words.joined(separator: " ") { score += 60 }
        return score
    }

    /// Rank candidate paths for `query`. `frecency` maps a path to its recency-weighted use.
    public static func rank(paths: [String], query: String, currentFolder: String?, frecency: [String: Double],
                            home: String = AppPaths.home, limit: Int = 50) -> [QuickFindResult] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let fm = FileManager.default
        var seen = Set<String>(), out: [QuickFindResult] = []
        for p in paths where seen.insert(p).inserted {
            let name = (p as NSString).lastPathComponent
            guard var score = nameScore(name: name, path: p, words: words) else { continue }
            if let c = currentFolder, p.hasPrefix(c == "/" ? "/" : c + "/") { score += 15 }
            if p.hasPrefix(home + "/") { score += 3 }
            score += max(0, 8 - Double(p.split(separator: "/").count) * 0.5) // shallower paths first
            if noise.contains(where: { p.contains($0) }) { score -= 40 }
            let parent = (p as NSString).deletingLastPathComponent
            let f = (frecency[p] ?? 0) + 0.5 * (frecency[parent] ?? 0)
            score += min(35, 12 * log2(1 + f))
            var isDir: ObjCBool = false
            fm.fileExists(atPath: p, isDirectory: &isDir)
            out.append(QuickFindResult(path: p, name: name, isDirectory: isDir.boolValue, score: score))
        }
        return Array(out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.path.count < $1.path.count }.prefix(limit))
    }

    /// With no query yet: your most used folders and files.
    public static func recents(frecency: [String: Double], limit: Int = 15) -> [QuickFindResult] {
        let fm = FileManager.default
        return frecency.sorted { $0.value > $1.value }.prefix(limit * 2).compactMap { p, f in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir) else { return nil }
            return QuickFindResult(path: p, name: (p as NSString).lastPathComponent, isDirectory: isDir.boolValue, score: f)
        }.prefix(limit).map { $0 }
    }
}

extension FinderStore {
    /// Recency-weighted use per path: each visit counts 1 (file opens 2) and halves every 7 days.
    public func frecencyScores(now: Date = Date()) throws -> [String: Double] {
        var scores: [String: Double] = [:]
        func add(_ sql: String, _ weight: Double, _ pathKey: String, _ timeKey: String) throws {
            for r in try db.query(sql) {
                guard let p = r[pathKey]?.string, let t = r[timeKey]?.string.flatMap(parseISO8601) else { continue }
                let days = max(0, now.timeIntervalSince(t) / 86400)
                scores[p, default: 0] += weight * pow(0.5, days / 7)
            }
        }
        try add("SELECT path, visited_at FROM nav_history", 1, "path", "visited_at")
        try add("SELECT path, opened_at FROM file_opens", 2, "path", "opened_at")
        return scores
    }
}

/// Spotlight name search, capped so a broad query can't flood the list.
public enum MDFind {
    public static let maxLines = 400

    /// `kMDItemFSName == "*word*"cd && …` — case and diacritic insensitive, every word must match.
    public static func expression(for query: String) -> String? {
        let words = query.split(separator: " ").map { w in
            String(w).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        guard !words.isEmpty else { return nil }
        return words.map { "kMDItemFSName == \"*\($0)*\"cd" }.joined(separator: " && ")
    }

    public static func lines(from data: Data, limit: Int = maxLines) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(limit).map(String.init)
    }

    private final class Box: @unchecked Sendable {
        let process = Process()
        func stop() { if process.isRunning { process.terminate() } }
    }

    /// Runs mdfind inside `onlyIn`; cancelling the task kills the process. At most `maxLines` results.
    public static func search(query: String, onlyIn: String = AppPaths.home, limit: Int = maxLines) async -> [String] {
        guard let expr = expression(for: query) else { return [] }
        let box = Box()
        box.process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        box.process.arguments = ["-onlyin", onlyIn, expr]
        let pipe = Pipe()
        box.process.standardOutput = pipe
        box.process.standardError = FileHandle.nullDevice
        return await withTaskCancellationHandler {
            guard (try? box.process.run()) != nil else { return [] }
            var out: [String] = []
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    out.append(line)
                    if out.count >= limit { break }
                }
            } catch {}
            box.stop()
            return Task.isCancelled ? [] : out
        } onCancel: { box.stop() }
    }
}
