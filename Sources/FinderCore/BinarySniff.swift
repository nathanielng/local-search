import Foundation

/// Says what a binary file is from its first bytes, and shows readable text near the start only when it means something.
public enum BinarySniff {
    public struct Format: Equatable, Sendable {
        public var name: String            // "PDF document"
        public var detail: String?         // "version 1.7"
        public var extensions: Set<String> // names this format normally has; empty = don't check the name
    }

    private static func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }
    private static func has(_ d: [UInt8], _ prefix: [UInt8], at off: Int = 0) -> Bool {
        d.count >= off + prefix.count && Array(d[off..<off + prefix.count]) == prefix
    }
    private static func be32(_ d: [UInt8], _ o: Int) -> UInt32 {
        d.count >= o + 4 ? d[o..<o + 4].reduce(0) { $0 << 8 | UInt32($1) } : 0
    }

    public static func identify(_ head: Data) -> Format? {
        let d = [UInt8](head.prefix(512))
        func f(_ n: String, _ detail: String? = nil, _ ext: [String] = []) -> Format { Format(name: n, detail: detail, extensions: Set(ext)) }

        if has(d, bytes("%PDF-")) {
            let v = String(decoding: d.dropFirst(5).prefix(3), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return f("PDF document", v.isEmpty ? nil : "version \(v)", ["pdf"])
        }
        if has(d, bytes("SQLite format 3\0")) { return f("SQLite database", nil, ["sqlite", "sqlite3", "db", "db3"]) }
        if has(d, [0x7f, 0x45, 0x4c, 0x46]) {
            let bits = d.count > 4 ? (d[4] == 2 ? "64-bit" : "32-bit") : nil
            let kind = d.count > 17 ? (d[16] == 2 ? "executable" : d[16] == 3 ? "shared library" : d[16] == 1 ? "object file" : "file") : "file"
            return f("ELF \(kind)", bits)
        }
        if has(d, [0xCF, 0xFA, 0xED, 0xFE]) || has(d, [0xCE, 0xFA, 0xED, 0xFE]) {
            let kinds: [UInt32: String] = [1: "object file", 2: "executable", 6: "dynamic library", 8: "bundle", 10: "debug symbols"]
            let ft = d.count >= 16 ? UInt32(d[12]) | UInt32(d[13]) << 8 | UInt32(d[14]) << 16 | UInt32(d[15]) << 24 : 0
            return f("Mach-O \(kinds[ft] ?? "binary")", d[0] == 0xCF ? "64-bit" : "32-bit")
        }
        if has(d, [0xCA, 0xFE, 0xBA, 0xBE]) {
            let n = be32(d, 4)
            return n >= 1 && n < 20 ? f("Mach-O universal binary", "\(n) architectures") : f("Java class file")
        }
        if has(d, bytes("bplist00")) { return f("Apple binary property list", nil, ["plist", "webarchive", "strings"]) }
        if has(d, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return f("PNG image", nil, ["png"]) }
        if has(d, bytes("GIF87a")) || has(d, bytes("GIF89a")) { return f("GIF image", String(decoding: d.prefix(6), as: UTF8.self), ["gif"]) }
        if has(d, [0xFF, 0xD8, 0xFF]) { return f("JPEG image", nil, ["jpg", "jpeg", "jpe"]) }
        if has(d, bytes("RIFF")) && d.count >= 12 {
            switch String(decoding: d[8..<12], as: UTF8.self) {
            case "WAVE": return f("WAV audio", nil, ["wav", "wave"])
            case "AVI ": return f("AVI video", nil, ["avi"])
            case "WEBP": return f("WebP image", nil, ["webp"])
            default: return f("RIFF container")
            }
        }
        if has(d, bytes("ID3")) {
            let v = d.count > 5 ? "ID3v2.\(d[3]).\(d[4])" : nil
            return f("MP3 audio with tags", v, ["mp3"])
        }
        if has(d, bytes("fLaC")) { return f("FLAC audio", nil, ["flac"]) }
        if has(d, bytes("OggS")) { return f("Ogg media", nil, ["ogg", "oga", "ogv", "opus"]) }
        if has(d, bytes("ftyp"), at: 4), d.count >= 12 {
            let brand = String(decoding: d[8..<12], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            let kinds = ["M4A": "MPEG-4 audio", "qt": "QuickTime movie", "heic": "HEIC image", "heix": "HEIC image", "mif1": "HEIF image"]
            return f(kinds[brand] ?? "MPEG-4 media", "brand “\(brand)”")
        }
        if has(d, [0x50, 0x4B, 0x03, 0x04]) { return f("Zip-based file", "zip, Office, jar, epub and similar") }
        if has(d, [0x1F, 0x8B]) { return f("gzip compressed data", nil, ["gz", "tgz"]) }
        if has(d, bytes("BZh")) { return f("bzip2 compressed data", nil, ["bz2", "tbz2"]) }
        if has(d, [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return f("xz compressed data", nil, ["xz", "txz"]) }
        if has(d, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return f("7-Zip archive", nil, ["7z"]) }
        if has(d, bytes("Rar!")) { return f("RAR archive", nil, ["rar"]) }
        if has(d, [0x4D, 0x5A]) { return f("Windows program (PE)", nil, ["exe", "dll", "sys", "scr"]) }
        if has(d, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return f("Old Microsoft Office document", "OLE container", ["doc", "xls", "ppt", "msi", "msg"]) }
        if has(d, bytes("%!PS")) { return f("PostScript", nil, ["ps", "eps", "ai"]) }
        if has(d, bytes("wOFF")) || has(d, bytes("wOF2")) { return f("Web font", nil, ["woff", "woff2"]) }
        if has(d, [0x00, 0x01, 0x00, 0x00, 0x00]) || has(d, bytes("OTTO")) || has(d, bytes("true")) { return f("Font file", nil, ["ttf", "otf"]) }
        if has(d, [0x00, 0x00, 0x01, 0x00]) { return f("Windows icon", nil, ["ico"]) }
        if has(d, bytes("8BPS")) { return f("Photoshop document", nil, ["psd"]) }
        if has(d, bytes("II*\0")) || has(d, bytes("MM\0*")) { return f("TIFF image", nil, ["tif", "tiff"]) }
        if has(d, bytes("BM")), d.count > 14 { return f("BMP image", nil, ["bmp"]) }
        if has(d, bytes("\0asm")) { return f("WebAssembly module", nil, ["wasm"]) }
        return nil
    }

    /// A readable run at the very start ("SQLite format 3", "bplist00") when it's long enough to mean something,
    /// plus up to a few word-like strings in the first 512 bytes. Random-looking bytes give nothing.
    public static func readable(_ head: Data) -> (leading: String?, strings: [String]) {
        let d = [UInt8](head.prefix(512))
        func printable(_ b: UInt8) -> Bool { b >= 0x20 && b < 0x7f }
        var lead = 0
        while lead < min(d.count, 64), printable(d[lead]) { lead += 1 }
        let leading = lead >= 4 ? String(decoding: d[0..<lead], as: UTF8.self) : nil

        var runs: [String] = [], cur: [UInt8] = []
        func flush() {
            defer { cur.removeAll() }
            guard cur.count >= 10 else { return }
            let s = String(decoding: cur, as: UTF8.self)
            let letters = s.filter { $0.isLetter || $0 == " " }.count
            guard Double(letters) / Double(s.count) >= 0.7 else { return }      // words, not noise
            runs.append(s.count > 80 ? String(s.prefix(80)) + "…" : s)
        }
        for b in d { if printable(b) { cur.append(b) } else { flush() } }
        flush()
        var out: [String] = []
        for r in runs where r != leading && !(leading?.contains(r) ?? false) && !out.contains(r) { out.append(r); if out.count == 3 { break } }
        return (leading, out)
    }

    /// The lines shown for a file with no text preview, or `fallback` when nothing useful can be said.
    public static func message(path: String, head: Data? = nil, fallback: String) -> String {
        let data = head ?? ((FileHandle(forReadingAtPath: path)).flatMap { h in defer { try? h.close() }; return try? h.read(upToCount: 512) }) ?? Data()
        guard !data.isEmpty else { return fallback }
        var lines: [String] = []
        let fmt = identify(data)
        if let fmt { lines.append(fmt.detail.map { "\(fmt.name) · \($0)" } ?? fmt.name) }
        else { lines.append(fallback) }

        let ext = (path as NSString).pathExtension.lowercased()
        if let fmt, !fmt.extensions.isEmpty, !ext.isEmpty, !fmt.extensions.contains(ext) {
            lines.append("The name ends in .\(ext), but the contents look like \(article(fmt.name)).")
        }
        let r = readable(data)
        if fmt == nil, let l = r.leading { lines.append("Starts with “\(l)”") }   // known formats already say it
        if !r.strings.isEmpty { lines.append("Readable text near the start:\n" + r.strings.map { "  “\($0)”" }.joined(separator: "\n")) }
        return lines.joined(separator: "\n")
    }

    private static func article(_ name: String) -> String {
        let n = name.prefix(1).lowercased()
        return (["a", "e", "i", "o", "u"].contains(n) ? "an " : "a ") + name
    }
}
