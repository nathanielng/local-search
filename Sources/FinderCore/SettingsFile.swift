import Foundation

/// Read-modify-write access to the local settings.json. Every edit writes the whole object back,
/// so keys this code doesn't know about are kept.
public enum SettingsFile {
    public static func read(_ url: URL) -> [String: Any] {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    /// The file exists and isn't a JSON object (half-saved or hand-edited with a typo).
    public static func isMalformed(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }       // missing is fine
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0a || $0 == 0x0d || $0 == 0x09 }) { return false }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) == nil
    }

    static func write(_ obj: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
