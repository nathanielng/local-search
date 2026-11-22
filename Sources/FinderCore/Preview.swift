import Foundation

public enum PreviewKind: Equatable, Sendable {
    case markdown, text, image
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
    public static let textCap = 64 * 1024
    public static let bigFile: Int64 = 1_048_576

    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "bmp", "webp"]
    static let markdownExts: Set<String> = ["md", "markdown", "mdown"]
    static let neverText: Set<String> = ["zip", "gz", "tgz", "tar", "dmg", "pkg", "iso", "7z", "rar", "mp3", "m4a", "wav", "mp4", "mov",
                                         "mkv", "avi", "pdf", "app", "dylib", "so", "o", "a", "class", "jar", "sqlite", "db", "ico", "psd"]
    static let secretNames: Set<String> = [".env", ".netrc", "id_rsa", "id_ed25519", "id_ecdsa", "credentials", ".npmrc", ".pypirc"]
    static let secretExts: Set<String> = ["pem", "key", "p12", "pfx", "keystore"]

    public static func kind(forName name: String) -> PreviewKind {
        let ext = (name as NSString).pathExtension.lowercased()
        if markdownExts.contains(ext) { return .markdown }
        if imageExts.contains(ext) { return .image }
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
    public static func loadText(path: String, size: Int64, allowLarge: Bool = false, showSecrets: Bool = false) -> PreviewResult {
        let name = (path as NSString).lastPathComponent
        guard let h = FileHandle(forReadingAtPath: path) else { return .unsupported("Can't read this file") }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: sniffBytes)) ?? Data()
        if head.isEmpty { return .text(TextPreview(text: "", truncated: false)) }
        if looksBinary(head) { return .unsupported("Binary file") }
        if size > bigFile && !allowLarge { return .needsClick(size: size) }
        try? h.seek(toOffset: 0)
        let data = (try? h.read(upToCount: textCap)) ?? head
        var text = String(decoding: data, as: UTF8.self)
        if !showSecrets, let why = secretReason(name: name, text: text) { return .withheld(reason: why) }
        let truncated = size > Int64(textCap)
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
