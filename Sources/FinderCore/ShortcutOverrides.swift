import Foundation

/// Your own key choices, kept apart from the built-in list. Only the shortcuts you changed are stored,
/// so a new version of the app can add shortcuts without touching yours.
/// `shortcuts.json`: { "version": 1, "overrides": { "newTab": "cmd+shift+n", "stop": "none" } }
public struct ShortcutOverrides: Equatable, Sendable {
    /// id -> keys like "cmd+shift+t", or "none" for a shortcut you turned off.
    public var keys: [String: String] = [:]
    public init(_ keys: [String: String] = [:]) { self.keys = keys }

    public static let none = "none"

    // MARK: Reading and writing

    public static func parse(_ data: Data) -> ShortcutOverrides? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        for (id, v) in (obj["overrides"] as? [String: Any]) ?? [:] {
            guard let s = v as? String, Shortcuts.base(id) != nil, s == none || Chord.parse(s) != nil else { continue }
            out[id] = s
        }
        return ShortcutOverrides(out)
    }
    public static func load(_ url: URL = AppPaths.shortcutsURL) -> ShortcutOverrides {
        (try? Data(contentsOf: url)).flatMap(parse) ?? ShortcutOverrides()
    }
    /// True when the file exists but isn't a JSON object.
    public static func isMalformed(_ url: URL = AppPaths.shortcutsURL) -> Bool {
        guard let d = try? Data(contentsOf: url), !d.allSatisfy({ [0x20, 0x0a, 0x0d, 0x09].contains($0) }) else { return false }
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) == nil
    }
    @discardableResult public func save(_ url: URL = AppPaths.shortcutsURL) -> Bool {
        if keys.isEmpty { try? FileManager.default.removeItem(at: url); return true }
        let obj: [String: Any] = ["version": 1, "overrides": keys]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    // MARK: Changing

    public enum Problem: Equatable, Sendable {
        case fixed                          // that shortcut can't be changed
        case needsModifier                  // a bare key would stop you typing
        case reserved(String)               // macOS keeps it
        case taken(by: String)              // another shortcut here already uses it
    }

    /// Why `chord` can't be given to `id`, or nil when it can.
    public func problem(setting chord: Chord, for id: String) -> Problem? {
        guard let def = Shortcuts.base(id), def.rebindable else { return .fixed }
        if !chord.mods.contains(where: { $0 == .command || $0 == .control || $0 == .option }) { return .needsModifier }
        if let why = Chord.reserved[chord.text] { return .reserved(why) }
        let mine = ShortcutDef(id: id, section: "", title: "", key: chord.key, mods: chord.mods, scope: def.scope, note: nil)
        for other in Shortcuts.effective(self) where other.id != id && other.signature == mine.signature { return .taken(by: other.id) }
        return nil
    }
    public mutating func set(_ id: String, to chord: Chord) {
        if Shortcuts.base(id).map({ ShortcutDef.chordText($0) }) == chord.text { keys[id] = nil } else { keys[id] = chord.text }
    }
    public mutating func turnOff(_ id: String) { keys[id] = Self.none }
    public mutating func reset(_ id: String) { keys[id] = nil }
}

/// One key with its modifiers, as written in shortcuts.json: "cmd+shift+t", "ctrl+`", "cmd+up".
public struct Chord: Equatable, Sendable {
    public var key: String
    public var mods: [ShortcutDef.Mod]
    public init(key: String, mods: [ShortcutDef.Mod]) { self.key = key.lowercased(); self.mods = mods.sorted() }

    static let names: [(ShortcutDef.Mod, String)] = [(.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
    static let special: Set<String> = ["up", "down", "left", "right", "return", "delete", "space", "tab"]

    public var text: String { (mods.sorted().compactMap { m in Self.names.first { $0.0 == m }?.1 } + [key]).joined(separator: "+") }

    public static func parse(_ s: String) -> Chord? {
        let parts = s.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard var key = parts.last, !key.isEmpty || s.hasSuffix("++") else { return nil }
        var body = Array(parts.dropLast())
        if s.hasSuffix("++") { key = "+"; body = Array(s.dropLast(2).lowercased().split(separator: "+").map(String.init)) }
        var mods: [ShortcutDef.Mod] = []
        for p in body {
            let aliases: [String: ShortcutDef.Mod] = ["cmd": .command, "command": .command, "ctrl": .control, "control": .control,
                                                     "opt": .option, "option": .option, "alt": .option, "shift": .shift]
            guard let m = aliases[p], !mods.contains(m) else { return nil }
            mods.append(m)
        }
        guard key.count == 1 || special.contains(key) else { return nil }
        return Chord(key: key, mods: mods)
    }

    /// Combinations macOS or the menu bar keep for themselves.
    static let reserved: [String: String] = [
        "cmd+q": "Quit", "cmd+h": "Hide", "cmd+opt+h": "Hide Others", "cmd+m": "Minimise", "cmd+tab": "the app switcher",
        "cmd+space": "Spotlight", "ctrl+cmd+q": "Lock Screen", "cmd+opt+esc": "Force Quit",
    ]
}

extension ShortcutDef {
    var chord: Chord { Chord(key: key, mods: mods) }
    static func chordText(_ d: ShortcutDef) -> String { d.chord.text }
}
