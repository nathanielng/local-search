import Foundation

/// Keeps secrets out of previews, copy-as-text and model prompts.
public enum SecretGuard {
    static let secretNames: Set<String> = [".env", ".envrc", ".netrc", ".npmrc", ".pypirc", "credentials", "credentials.json",
                                           "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "secrets.json", "secrets.yml", "secrets.yaml"]
    static let secretExtensions: Set<String> = ["pem", "key", "p12", "pfx", "keystore", "jks", "ppk", "kdbx"]
    static let secretFolders: Set<String> = [".ssh", ".aws", ".gnupg"]
    static let patterns: [NSRegularExpression] = [
        #"AKIA[0-9A-Z]{16}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)aws_secret_access_key"#,
        #"(?i)(api[_-]?key|secret|token|passw(or)?d)["']?\s*[:=]\s*["']?[A-Za-z0-9/+_\-.]{16,}"#,
        #"gh[pousr]_[A-Za-z0-9]{30,}"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public static func isSecretPath(_ path: String) -> Bool {
        let comps = path.split(separator: "/").map(String.init)
        guard let name = comps.last?.lowercased() else { return false }
        if secretNames.contains(name) || name.hasPrefix(".env.") { return true }
        if secretExtensions.contains((name as NSString).pathExtension) { return true }
        return comps.dropLast().contains { secretFolders.contains($0) }
    }

    public static func looksSecret(content: String) -> Bool {
        let range = NSRange(content.startIndex..., in: content)
        return patterns.contains { $0.firstMatch(in: content, range: range) != nil }
    }

    /// Binary if the first 8 KB holds a NUL byte or isn't valid UTF-8 (a cut multibyte tail is fine).
    public static func isBinary(_ data: Data) -> Bool {
        let head = data.prefix(8192)
        if head.contains(0) { return true }
        for cut in 0...3 where head.count > cut {
            if String(data: head.dropLast(cut), encoding: .utf8) != nil { return false }
        }
        return head.isEmpty ? false : true
    }
}

public enum CopyText {
    public static let perFileLimit = 200 * 1024
    public static let totalLimit = 1024 * 1024

    public struct Output: Sendable {
        public var text: String
        public var included: [String]
        public var skipped: [(path: String, reason: String)]
    }

    /// File text for pasting into an AI chat. Several files each get a `===== /path =====` line.
    public static func build(paths: [String]) -> Output {
        var included: [(String, String)] = [], skipped: [(path: String, reason: String)] = []
        var total = 0
        for p in paths {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir) else { skipped.append((p, "missing")); continue }
            if isDir.boolValue { skipped.append((p, "folder")); continue }
            if SecretGuard.isSecretPath(p) { skipped.append((p, "likely secret")); continue }
            guard let h = FileHandle(forReadingAtPath: p) else { skipped.append((p, "unreadable")); continue }
            let data = (try? h.read(upToCount: perFileLimit + 1)) ?? Data()
            try? h.close()
            if SecretGuard.isBinary(data) { skipped.append((p, "binary")); continue }
            var body = String(decoding: data.prefix(perFileLimit), as: UTF8.self)
            if SecretGuard.looksSecret(content: body) { skipped.append((p, "likely secret")); continue }
            if data.count > perFileLimit { body += "\n[truncated at 200 KB]" }
            if total + body.utf8.count > totalLimit { skipped.append((p, "over 1 MB total")); continue }
            total += body.utf8.count
            included.append((p, body))
        }
        let text = included.count == 1
            ? included[0].1
            : included.map { "===== \($0.0) =====\n\($0.1)" }.joined(separator: "\n\n")
        return Output(text: text, included: included.map(\.0), skipped: skipped)
    }
}
