import SwiftUI
import AppKit
import FinderCore

/// The shortcuts in effect: the built-in list with your changes from shortcuts.json.
/// Menus, tooltips and the shortcuts window all read this, so they always agree.
@MainActor @Observable
final class ShortcutStore {
    static let shared = ShortcutStore()

    private(set) var overrides = ShortcutOverrides.load()
    private(set) var malformed = ShortcutOverrides.isMalformed()
    @ObservationIgnored private let watcher = FolderWatcher()
    @ObservationIgnored private let fileWatcher = FolderWatcher()

    var list: [ShortcutDef] { Shortcuts.effective(overrides) }
    func def(_ id: String) -> ShortcutDef { list.first { $0.id == id } ?? Shortcuts.def(id) }
    var changedCount: Int { overrides.keys.count }
    func isChanged(_ id: String) -> Bool { overrides.keys[id] != nil }

    /// "⌘F" for a tooltip, or nothing when you turned that shortcut off.
    func hint(_ id: String) -> String {
        let d = def(id)
        return d.isOff ? "" : " (\(d.display))"
    }

    func set(_ id: String, to chord: Chord) { overrides.set(id, to: chord); persist() }
    func turnOff(_ id: String) { overrides.turnOff(id); persist() }
    func reset(_ id: String) { overrides.reset(id); persist() }
    func resetAll() { overrides = ShortcutOverrides(); persist() }
    /// Give `chord` to `id` and turn off whoever had it.
    func replace(_ other: String, with id: String, chord: Chord) { overrides.turnOff(other); overrides.set(id, to: chord); persist() }

    func problem(setting chord: Chord, for id: String) -> ShortcutOverrides.Problem? { overrides.problem(setting: chord, for: id) }

    private func persist() {
        overrides.save()
        arm()
    }

    /// Pick up edits made in an editor.
    func reload() {
        malformed = ShortcutOverrides.isMalformed()
        guard !malformed else { return }
        let fresh = ShortcutOverrides.load()
        if fresh != overrides { overrides = fresh }
    }

    func watch() {
        watcher.watch(AppPaths.supportDir.path) { [weak self] in self?.reload(); self?.arm() }
        arm()
    }
    private func arm() {
        let path = AppPaths.shortcutsURL.path
        fileWatcher.stop()
        guard FileManager.default.fileExists(atPath: path) else { return }
        fileWatcher.watch(path) { [weak self] in self?.reload(); self?.arm() }
    }

    func revealFile() {
        let url = AppPaths.shortcutsURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("{\n  \"version\": 1,\n  \"overrides\": {}\n}\n".utf8).write(to: url)
            arm()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Records one key press for the settings tab.
@MainActor
final class ChordRecorder {
    private var monitor: Any?
    func start(_ onChord: @escaping (Chord) -> Void, onCancel: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.stop(); onCancel(); return nil }            // Esc
            guard let chord = Self.chord(from: e) else { NSSound.beep(); return nil }
            self?.stop(); onChord(chord); return nil
        }
    }
    func stop() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }

    /// What menus expect: the key without shift's effect ("]" with shift, not "}").
    static func chord(from e: NSEvent) -> Chord? {
        var mods: [ShortcutDef.Mod] = []
        let f = e.modifierFlags
        if f.contains(.control) { mods.append(.control) }
        if f.contains(.option) { mods.append(.option) }
        if f.contains(.shift) { mods.append(.shift) }
        if f.contains(.command) { mods.append(.command) }
        let codes: [UInt16: String] = [126: "up", 125: "down", 123: "left", 124: "right", 36: "return", 76: "return", 51: "delete", 49: "space", 48: "tab"]
        if let named = codes[e.keyCode] { return Chord(key: named, mods: mods) }
        guard var ch = e.charactersIgnoringModifiers?.lowercased(), ch.count == 1 else { return nil }
        let unshift: [Character: String] = ["{": "[", "}": "]", "<": ",", ">": ".", "?": "/", ":": ";", "\"": "'", "|": "\\", "~": "`", "_": "-", "+": "="]
        if let u = unshift[ch.first!] { ch = u }
        guard ch.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { return nil }
        return Chord(key: ch, mods: mods)
    }
}
