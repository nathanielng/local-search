import Foundation

public enum PreviewKind: Equatable, Sendable {
    case markdown, text, image, json, csv(Character), svg, html, archive
    case unsupported(String)
}

public struct TextPreview: Equatable, Sendable {
    public var text: String
    public var truncated: Bool
}

public enum PreviewResult: Equatable, Sendable {
    case text(TextPreview)
    case needsClick(size: Int64)      // over 1 MB: show only when asked
    case withheld(reason: String)     // looks like it holds secrets: show only on "Show Anyway"
    case unsupported(String)
}

/// Rules for the Info & Preview pane. Nothing here touches the UI.
public enum Preview {
    public static let sniffBytes = 8 * 1024
    /// Limits the user can change in Settings (stored in the app's preferences); these are the defaults.
    public static let defaultTextKB = 64, defaultBigMB = 1
    public static var textCap: Int { clamped("previewTextKB", defaultTextKB, 8...1024) * 1024 }
    public static var bigFile: Int64 { Int64(clamped("previewBigMB", defaultBigMB, 1...100)) * 1_048_576 }
    public static var withholdSecrets: Bool { UserDefaults.standard.object(forKey: "previewWithholdSecrets") as? Bool ?? true }

    static func clamped(_ key: String, _ def: Int, _ range: ClosedRange<Int>) -> Int {
        let v = UserDefaults.standard.integer(forKey: key)
        return v == 0 ? def : min(max(v, range.lowerBound), range.upperBound)
    }

    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "bmp", "webp"]
    static let markdownExts: Set<String> = ["md", "markdown", "mdown"]
    static let neverText: Set<String> = ["gz", "dmg", "pkg", "iso", "7z", "rar", "mp3", "m4a", "wav", "mp4", "mov",
                                         "mkv", "avi", "pdf", "app", "dylib", "so", "o", "a", "class", "jar", "sqlite", "db", "ico", "psd"]
    static let secretNames: Set<String> = [".env", ".netrc", "id_rsa", "id_ed25519", "id_ecdsa", "credentials", ".npmrc", ".pypirc"]
    static let secretExts: Set<String> = ["pem", "key", "p12", "pfx", "keystore"]

    public static func kind(forName name: String) -> PreviewKind {
        let ext = (name as NSString).pathExtension.lowercased()
        if markdownExts.contains(ext) { return .markdown }
        if imageExts.contains(ext) { return .image }
        switch ext {
        case "json": return .json
        case "csv": return .csv(",")
        case "tsv": return .csv("\t")
        case "svg": return .svg
        case "html", "htm": return .html
        default: break
        }
        if Archive.isArchive(name) { return .archive }
        if neverText.contains(ext) { return .unsupported("No preview for this kind of file") }
        return .text
    }

    /// A NUL byte, or bytes that are not valid UTF-8, mean a binary file.
    public static func looksBinary(_ head: Data) -> Bool {
        if head.contains(0) { return true }
        if String(data: head, encoding: .utf8) != nil { return false }
        // A multi-byte character cut by the 8 KB boundary is fine; anything else is not.
        for trim in 1...3 where head.count > trim {
            if String(data: head.dropLast(trim), encoding: .utf8) != nil { return false }
        }
        return true
    }

    /// Why this file's contents should be withheld, or nil.
    public static func secretReason(name: String, text: String) -> String? {
        let lower = name.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        if secretNames.contains(lower) || lower.hasPrefix(".env.") || secretExts.contains(ext) {
            return "The file name suggests it holds secrets"
        }
        let patterns = [
            "-----BEGIN [A-Z ]*PRIVATE KEY-----",
            "AKIA[0-9A-Z]{16}",
            "(?i)(api[_-]?key|secret|token|passw(or)?d)[\"']?\\s*[:=]\\s*[\"']?[A-Za-z0-9/+_\\-]{12,}",
        ]
        for p in patterns where text.range(of: p, options: .regularExpression) != nil {
            return "The contents look like they include a key or password"
        }
        return nil
    }

    /// Read a text preview: check the first 8 KB, cap the text at 64 KB, hold back big files and likely secrets.
    public static func loadText(path: String, size: Int64, allowLarge: Bool = false, showSecrets: Bool = false, cap: Int = textCap) -> PreviewResult {
        let name = (path as NSString).lastPathComponent
        guard let h = FileHandle(forReadingAtPath: path) else { return .unsupported("Can't read this file") }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: sniffBytes)) ?? Data()
        if head.isEmpty { return .text(TextPreview(text: "", truncated: false)) }
        if looksBinary(head) { return .unsupported("Binary file") }
        if size > bigFile && !allowLarge { return .needsClick(size: size) }
        try? h.seek(toOffset: 0)
        let data = (try? h.read(upToCount: cap)) ?? head
        var text = String(decoding: data, as: UTF8.self)
        if !showSecrets, withholdSecrets, let why = secretReason(name: name, text: text) { return .withheld(reason: why) }
        let truncated = size > Int64(cap)
        if truncated, text.last == "\u{FFFD}" { text.removeLast() }
        return .text(TextPreview(text: text, truncated: truncated))
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(Int, String)
    case bullet(String)
    case code(String)
    case paragraph(String)
    case rule
}

public enum MarkdownBlocks {
    /// A small block parser for the preview: headings, bullets, fenced code, rules and paragraphs.
    /// Inline styling (bold, links, code spans) is left to the renderer.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var para: [String] = []
        var code: [String]?
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let t = line.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if t.hasPrefix("```") { out.append(.code(code!.joined(separator: "\n"))); code = nil } else { code!.append(line) }
                continue
            }
            if t.hasPrefix("```") { flush(); code = []; continue }
            if t.isEmpty { flush(); continue }
            if let m = t.range(of: "^#{1,6} ", options: .regularExpression) {
                flush()
                out.append(.heading(t.distance(from: t.startIndex, to: m.upperBound) - 1, String(t[m.upperBound...])))
            } else if t.range(of: "^(-{3,}|\\*{3,}|_{3,})$", options: .regularExpression) != nil {
                flush(); out.append(.rule)
            } else if let m = t.range(of: "^([-*+]|\\d+[.)]) ", options: .regularExpression) {
                flush(); out.append(.bullet(String(t[m.upperBound...])))
            } else {
                para.append(t)
            }
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }
}

public enum JSONPreview {
    public static let maxBytes = 512 * 1024
    /// Pretty-printed JSON, or nil when the text isn't valid JSON.
    public static func pretty(_ text: String) -> String? {
        guard let d = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return nil }
        return String(decoding: out, as: UTF8.self)
    }
}

public struct CSVTable: Equatable, Sendable {
    public var rows: [[String]]
    public var moreRows: Bool
    public var moreColumns: Bool
}

public enum CSVPreview {
    public static let maxRows = 50, maxColumns = 20

    /// First 50 rows by 20 columns, with quoted fields and doubled quotes handled.
    public static func parse(_ text: String, delimiter: Character) -> CSVTable {
        var rows: [[String]] = []
        var row: [String] = [], field = ""
        var quoted = false, moreRows = false, moreCols = false
        let chars = Array(text)
        var i = 0
        func endField() { row.append(field); field = "" }
        func endRow() -> Bool {
            endField()
            if row.count > maxColumns { moreCols = true; row = Array(row.prefix(maxColumns)) }
            rows.append(row); row = []
            return rows.count >= maxRows
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" { if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false } }
                else { field.append(c) }
            } else if c == "\"" && field.isEmpty { quoted = true }
            else if c == delimiter { endField() }
            else if c == "\n" || c == "\r\n" { if endRow() { moreRows = i + 1 < chars.count && chars[(i + 1)...].contains { !$0.isNewline }; return CSVTable(rows: rows, moreRows: moreRows, moreColumns: moreCols) } }
            else if c == "\r" { }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { _ = endRow() }
        return CSVTable(rows: rows, moreRows: moreRows, moreColumns: moreCols)
    }
}

public enum Archive {
    public static let maxEntries = 200
    public static let timeout: TimeInterval = 3

    public static func isArchive(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasSuffix(".zip") || n.hasSuffix(".tar") || n.hasSuffix(".tar.gz") || n.hasSuffix(".tgz")
    }

    /// The first 200 entry names. The listing tool is killed after 3 seconds. Nil when it can't be read.
    public static func list(path: String) -> (entries: [String], truncated: Bool)? {
        let isZip = path.lowercased().hasSuffix(".zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: isZip ? "/usr/bin/unzip" : "/usr/bin/tar")
        p.arguments = isZip ? ["-Z1", path] : ["-tf", path]
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        var buffer = Data(), truncated = false
        while true {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if buffer.filter({ $0 == 10 }).count > maxEntries { truncated = true; p.terminate(); break }
        }
        killer.cancel()
        p.waitUntilExit()
        var lines = String(decoding: buffer, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if lines.count > maxEntries { lines = Array(lines.prefix(maxEntries)); truncated = true }
        if lines.isEmpty && p.terminationStatus != 0 { return nil }
        return (lines, truncated)
    }
}
