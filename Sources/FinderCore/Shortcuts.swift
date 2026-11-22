import Foundation

/// Every keyboard shortcut in one place. The menus and the shortcuts window both read this list,
/// and a test makes sure no two shortcuts in the same place use the same keys.
public struct ShortcutDef: Sendable, Equatable, Identifiable {
    public enum Mod: Int, Sendable, Comparable {
        case control = 0, option, shift, command          // the order macOS writes them: ⌃⌥⇧⌘
        public static func < (a: Mod, b: Mod) -> Bool { a.rawValue < b.rawValue }
        public var symbol: String { ["⌃", "⌥", "⇧", "⌘"][rawValue] }
    }
    public let id: String
    public let section: String
    public let title: String
    /// One character ("t", "[", "`"), or a name: up, down, return, delete, space, escape, tab.
    public let key: String
    public let mods: [Mod]
    /// Where it works: "App" (menus, anywhere) or a place such as "File list".
    public let scope: String
    public let note: String?

    public var display: String {
        let names = ["up": "↑", "down": "↓", "return": "↩", "delete": "⌫", "space": "Space", "escape": "Esc", "tab": "⇥"]
        return mods.sorted().map(\.symbol).joined() + (names[key] ?? key.uppercased())
    }
    /// For finding clashes.
    public var signature: String { scope + "|" + mods.sorted().map { String($0.rawValue) }.joined() + "|" + key.lowercased() }
}

public enum Shortcuts {
    private static func d(_ id: String, _ section: String, _ title: String, _ key: String, _ mods: [ShortcutDef.Mod],
                          scope: String = "App", note: String? = nil) -> ShortcutDef {
        ShortcutDef(id: id, section: section, title: title, key: key, mods: mods, scope: scope, note: note)
    }
    private static let c = ShortcutDef.Mod.command, s = ShortcutDef.Mod.shift, o = ShortcutDef.Mod.option, k = ShortcutDef.Mod.control

    public static let all: [ShortcutDef] = [
        // Tabs
        d("newTab", "Tabs", "New Tab", "t", [c]),
        d("closeTab", "Tabs", "Close Tab", "w", [c]),
        d("reopenTab", "Tabs", "Reopen Closed Tab", "t", [c, s]),
        d("nextTab", "Tabs", "Next Tab", "]", [c, s]),
        d("prevTab", "Tabs", "Previous Tab", "[", [c, s]),
        // Go
        d("back", "Go", "Back", "[", [c]),
        d("forward", "Go", "Forward", "]", [c]),
        d("up", "Go", "Enclosing Folder", "up", [c]),
        d("goToFolder", "Go", "Go to Folder… (type a path)", "g", [c, s]),
        d("quickFind", "Go", "Quick Find…", "f", [c]),
        d("webLocations", "Go", "Web Locations…", "l", [c, s]),
        d("history", "Go", "Show History", "y", [c]),
        // Files
        d("newFolder", "Files", "New Folder", "n", [c, s]),
        d("newTextFile", "Files", "New Text File", "n", [c, o]),
        d("trash", "Files", "Move to Trash", "delete", [c]),
        d("showInFinder", "Files", "Show in Finder", "r", [c, o]),
        d("copy", "Files", "Copy", "c", [c]),
        d("paste", "Files", "Paste (copy here)", "v", [c]),
        d("moveHere", "Files", "Move Item Here", "v", [c, o]),
        d("selectAll", "Files", "Select All", "a", [c]),
        d("undo", "Files", "Undo the last file operation", "z", [c]),
        d("redo", "Files", "Redo", "z", [c, s]),
        d("copyPaths", "Files", "Copy Paths", "c", [c, o]),
        d("copyText", "Files", "Copy File Text for AI", "c", [c, o, s]),
        d("favorite", "Files", "Toggle Favorite (sidebar)", "t", [c, k]),
        // Panels and view
        d("sidebar", "View", "Show or hide the sidebar", "s", [c, k]),
        d("rightPanel", "View", "Show or hide the right panel", "p", [c, k]),
        d("verticalTabs", "View", "Vertical Tabs pane", "v", [c, k]),
        d("recent", "View", "Recent Locations pane", "r", [c, k]),
        d("info", "View", "Info & Preview pane", "i", [c]),
        d("commands", "View", "Command panel", "`", [k]),
        d("colours", "View", "File colours", "k", [c, k]),
        d("badges", "View", "Kind badges", "b", [c, k]),
        d("group", "View", "Group by Date", "g", [c, k]),
        d("permissions", "View", "Permissions column", "m", [c, k]),
        d("hidden", "View", "Show or hide hidden files", ".", [c, s]),
        d("bigger", "View", "Bigger Text", "+", [c]),
        d("smaller", "View", "Smaller Text", "-", [c]),
        d("actualSize", "View", "Actual Text Size", "0", [c]),
        // Help
        d("shortcuts", "Help", "Keyboard Shortcuts (this window)", "/", [c]),
        d("shortcutsKey", "Help", "Keyboard Shortcuts, from the file list", "?", [], scope: "File list"),
        // In the file list
        d("quickLook", "File list", "Quick Look", "space", [], scope: "File list"),
        d("rename", "File list", "Rename the selected item", "return", [], scope: "File list"),
        d("openNewTab", "File list", "Open in a new tab (with a double-click)", "return", [c], scope: "File list", note: "⌘-double-click"),
        // Quick Find
        d("qfMove", "Quick Find", "Move through results", "down", [], scope: "Quick Find", note: "↑ and ↓"),
        d("qfOpen", "Quick Find", "Go to the result", "return", [], scope: "Quick Find"),
        d("qfNewTab", "Quick Find", "Open the result in a new tab", "return", [c], scope: "Quick Find"),
        d("qfClose", "Quick Find", "Close", "escape", [], scope: "Quick Find"),
        // Command panel
        d("run", "Command panel", "Run the command", "return", [c], scope: "Command panel"),
        d("stop", "Command panel", "Stop the running command", ".", [c], scope: "Command panel"),
        // System
        d("settings", "App", "Settings", ",", [c]),
    ]

    public static func def(_ id: String) -> ShortcutDef {
        guard let s = all.first(where: { $0.id == id }) else { preconditionFailure("unknown shortcut \(id)") }
        return s
    }

    /// Pairs of shortcuts that use the same keys in the same place.
    public static func clashes(_ list: [ShortcutDef] = all) -> [(String, String)] {
        var seen: [String: String] = [:], out: [(String, String)] = []
        for s in list {
            if let other = seen[s.signature] { out.append((other, s.id)) } else { seen[s.signature] = s.id }
        }
        return out
    }
}
