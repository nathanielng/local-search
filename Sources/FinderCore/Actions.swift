import Foundation

/// One entry of actions.json: a shell command template the command panel can fill in for the selection.
///
/// Template tokens (every substituted value is shell-quoted):
/// `{{selection}}` all selected items, `{{file}}` the item (each item when `each` is set), `{{stem}}`, `{{ext}}`,
/// `{{folder}}`, `{{out:Name}}` a file name that never overwrites (inside it `<stem>` and `<ext>` are the
/// selected file's), and `{{ask:Label=default}}` a value the user types in the panel.
/// A preconfigured alternative to an action: only what differs is listed, everything else comes from the action.
public struct ActionVariant: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var description: String?
    public var command: String?
    public var explain: [String]?
    public var confirm: Bool?
}

public struct Action: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var group: String
    public var description: String
    public var command: String
    /// Plain-language lines: "part of the command — what it does".
    public var explain: [String]?
    /// "none", "one" (exactly one item) or "some" (one or more). Default: worked out from the command.
    public var needs: String?
    public var extensions: [String]?
    public var each: Bool?
    public var tool: String?
    public var requires: [String]?
    public var match: String?
    public var confirm: Bool?
    public var notInHome: Bool?
    public var results: Bool?
    /// Small variations (other flags, other modes). The action itself is the first choice, labelled `baseLabel`.
    public var variants: [ActionVariant]?
    public var baseLabel: String?
}

public struct ActionFile: Codable, Sendable {
    public var version: Int
    public var actions: [Action]
}

public struct ActionContext: Sendable {
    public var folder: String
    public var selection: [String]          // full paths
    public var home: String
    public var hasTool: @Sendable (String) -> Bool
    /// Features that are available here, for `requires`: "git" when the folder is in a repository (cloud, s3 and llm come later).
    public var supported: Set<String>
    public var isDirectory: @Sendable (String) -> Bool
    public var exists: @Sendable (String) -> Bool

    public init(folder: String, selection: [String], home: String = AppPaths.home, supported: Set<String> = [],
                hasTool: @escaping @Sendable (String) -> Bool = { _ in true },
                isDirectory: @escaping @Sendable (String) -> Bool = { p in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue },
                exists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.folder = folder; self.selection = selection; self.home = home; self.supported = supported
        self.hasTool = hasTool; self.isDirectory = isDirectory; self.exists = exists
    }
}

public enum Availability: Equatable, Sendable {
    case available
    case unavailable(String)
    public var isAvailable: Bool { self == .available }
}

public enum Actions {
    // MARK: Loading

    public static func parse(_ data: Data) -> (file: ActionFile?, error: String?) {
        do { return (try JSONDecoder().decode(ActionFile.self, from: data), nil) }
        catch { return (nil, "actions.json couldn't be read: \(error.localizedDescription)") }
    }

    /// Put the bundled actions in place. A missing file is created. A file with an older `version` is moved
    /// to actions.json.bak and replaced; an unreadable file is kept as .bak too. Returns true when it wrote.
    @discardableResult
    public static func installDefaults(bundled: URL, to target: URL) -> Bool {
        guard let bundledData = try? Data(contentsOf: bundled), let b = parse(bundledData).file else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: target) {
            if let e = parse(existing).file, e.version >= b.version { return false }
            let bak = target.appendingPathExtension("bak")
            try? fm.removeItem(at: bak)
            try? fm.moveItem(at: target, to: bak)
        }
        return (try? bundledData.write(to: target, options: .atomic)) != nil
    }

    // MARK: Variants

    /// The action with a variant's differences applied. An unknown or nil id gives the action itself.
    public static func resolved(_ a: Action, variant id: String?) -> Action {
        guard let id, let v = a.variants?.first(where: { $0.id == id }) else { return a }
        var r = a
        if let c = v.command { r.command = c }
        if let d = v.description { r.description = d }
        if let e = v.explain { r.explain = e }
        if let c = v.confirm { r.confirm = c }
        r.variants = nil
        return r
    }

    // MARK: Shell quoting

    /// Quote one value for zsh: plain words stay as they are, anything else goes in single quotes.
    public static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Tokens

    private static let token = try! NSRegularExpression(pattern: #"\{\{([a-z_]+)(?::([^}]*))?\}\}"#)

    /// The `{{ask:Label=default}}` fields in a command, in order, without repeats.
    public static func asks(in command: String) -> [(label: String, def: String)] {
        var out: [(String, String)] = []
        let ns = command as NSString
        for m in token.matches(in: command, range: NSRange(location: 0, length: ns.length)) where ns.substring(with: m.range(at: 1)) == "ask" {
            let arg = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            let (l, d) = splitAsk(arg)
            if !out.contains(where: { $0.0 == l }) { out.append((l, d)) }
        }
        return out.map { (label: $0.0, def: $0.1) }
    }

    private static func splitAsk(_ arg: String) -> (String, String) {
        guard let eq = arg.firstIndex(of: "=") else { return (arg, "") }
        return (String(arg[..<eq]), String(arg[arg.index(after: eq)...]))
    }

    /// The command's own needs when `needs` isn't set.
    static func effectiveNeeds(_ a: Action) -> String {
        if let n = a.needs { return n }
        let c = a.command
        if c.contains("{{selection}}") { return "some" }
        if c.contains("{{file}}") || c.contains("{{stem}}") || c.contains("{{ext}}") || c.contains("<stem>") || c.contains("<ext>") {
            return a.each == true ? "some" : "one"
        }
        return "none"
    }

    // MARK: Availability

    public static func availability(of a: Action, in ctx: ActionContext) -> Availability {
        for r in a.requires ?? [] where !ctx.supported.contains(r) {
            switch r {
            case "git": return .unavailable("This folder isn't in a git repository (no .git folder here or above)")
            default: return .unavailable("Needs \(r), which isn't set up in this version yet")
            }
        }
        if a.notInHome == true, (ctx.folder as NSString).standardizingPath == (ctx.home as NSString).standardizingPath {
            return .unavailable("Not offered in your home folder (it would take too long)")
        }
        switch effectiveNeeds(a) {
        case "one": if ctx.selection.count != 1 { return .unavailable("Select exactly one item") }
        case "some": if ctx.selection.isEmpty { return .unavailable("Select one or more items") }
        default: break
        }
        if let exts = a.extensions, !exts.isEmpty, !ctx.selection.isEmpty {
            let want = Set(exts.map { $0.lowercased() })
            if !ctx.selection.allSatisfy({ !ctx.isDirectory($0) && want.contains(($0 as NSString).pathExtension.lowercased()) }) {
                return .unavailable("Works on " + exts.map { "." + $0 }.joined(separator: ", ") + " files")
            }
        }
        if let m = a.match, !ctx.selection.isEmpty, let re = try? NSRegularExpression(pattern: m) {
            let ok = ctx.selection.allSatisfy { p in
                let n = (p as NSString).lastPathComponent
                return re.firstMatch(in: n, range: NSRange(location: 0, length: (n as NSString).length)) != nil
            }
            if !ok { return .unavailable("The selected names don't fit this action") }
        }
        if let t = a.tool, !ctx.hasTool(t) { return .unavailable("\(t) isn't installed") }
        return .available
    }

    // MARK: Rendering

    /// "Name.zip" -> "Name.zip", or "Name 2.zip", "Name 3.zip"... when taken (on disk or in `reserved`).
    public static func uniqueName(_ name: String, in folder: String, reserved: Set<String> = [],
                                  exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        let ns = name as NSString
        let stem = ns.deletingPathExtension, ext = ns.pathExtension
        var candidate = name, n = 1
        while exists((folder as NSString).appendingPathComponent(candidate)) || reserved.contains(candidate) {
            n += 1
            candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
        }
        return candidate
    }

    /// Selected items as the command sees them: names inside the folder, full paths otherwise.
    static func display(_ path: String, folder: String) -> String {
        let f = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(f) && !path.dropFirst(f.count).contains("/") ? String(path.dropFirst(f.count)) : path
    }

    public static func render(_ a: Action, in ctx: ActionContext, asks values: [String: String] = [:]) -> String {
        if a.each == true, !ctx.selection.isEmpty {
            var reserved = Set<String>()
            return ctx.selection.map { renderOnce(a.command, ctx: ctx, item: $0, asks: values, reserved: &reserved) }.joined(separator: "\n")
        }
        var reserved = Set<String>()
        return renderOnce(a.command, ctx: ctx, item: ctx.selection.first, asks: values, reserved: &reserved)
    }

    private static func renderOnce(_ command: String, ctx: ActionContext, item: String?, asks values: [String: String], reserved: inout Set<String>) -> String {
        let itemName = item.map { display($0, folder: ctx.folder) } ?? ""
        let base = (itemName as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension, ext = (base as NSString).pathExtension
        let ns = command as NSString
        var out = "", last = 0
        for m in token.matches(in: command, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            last = m.range.location + m.range.length
            let key = ns.substring(with: m.range(at: 1))
            let arg = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            switch key {
            case "selection": out += ctx.selection.map { shellQuote(display($0, folder: ctx.folder)) }.joined(separator: " ")
            case "file": out += shellQuote(itemName)
            case "stem": out += shellQuote(stem)
            case "ext": out += shellQuote(ext)
            case "folder": out += shellQuote(ctx.folder)
            case "out":
                let wanted = arg.replacingOccurrences(of: "<stem>", with: stem).replacingOccurrences(of: "<ext>", with: ext)
                let name = uniqueName(wanted, in: ctx.folder, reserved: reserved, exists: ctx.exists)
                reserved.insert(name)
                out += shellQuote(name)
            case "ask":
                let (label, def) = splitAsk(arg)
                out += shellQuote(values[label] ?? def)
            default: out += ns.substring(with: m.range)    // unknown token: left visible
            }
        }
        out += ns.substring(from: last)
        return out
    }
}
