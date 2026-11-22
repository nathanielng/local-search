import Foundation
import Darwin

/// Unix permission bits: display, presets and applying them.
public enum Permissions {
    /// "drwxr-xr-x" for a mode, with setuid/setgid/sticky shown as s/S/t/T like `ls -l`.
    public static func string(mode: UInt16, isDirectory: Bool, isSymlink: Bool = false) -> String {
        var s = isSymlink ? "l" : (isDirectory ? "d" : "-")
        func triple(_ r: UInt16, _ w: UInt16, _ x: UInt16, special: UInt16, on: Character, off: Character) -> String {
            let exec = mode & x != 0
            let xs: Character = mode & special != 0 ? (exec ? on : off) : (exec ? "x" : "-")
            return (mode & r != 0 ? "r" : "-") + (mode & w != 0 ? "w" : "-") + String(xs)
        }
        s += triple(0o400, 0o200, 0o100, special: 0o4000, on: "s", off: "S")
        s += triple(0o040, 0o020, 0o010, special: 0o2000, on: "s", off: "S")
        s += triple(0o004, 0o002, 0o001, special: 0o1000, on: "t", off: "T")
        return s
    }

    /// "755" (or "4755" with a special bit).
    public static func octal(_ mode: UInt16) -> String {
        let m = mode & 0o7777
        return m > 0o777 ? String(m, radix: 8) : String(format: "%03o", m)
    }

    public enum Preset: String, CaseIterable, Sendable {
        case makeExecutable, removeExecute, privateToOwner, readOnly

        public var title: String {
            switch self {
            case .makeExecutable: "Make Executable (+x)"
            case .removeExecute: "Remove Execute (-x)"
            case .privateToOwner: "Private: owner only (600 / 700)"
            case .readOnly: "Read-only for owner (400 / 500)"
            }
        }
        public var help: String {
            switch self {
            case .makeExecutable: "Lets the file run as a program or script, like chmod +x"
            case .removeExecute: "Stops the file running as a program. Folders are left alone, since they need it to be opened"
            case .privateToOwner: "Only you can read or change it, the setting SSH wants for key files like ~/.ssh/id_rsa"
            case .readOnly: "Only you can read it and nobody can change it, like chmod 400"
            }
        }
    }

    /// The mode a preset gives. Permission bits only; setuid/setgid/sticky are cleared by the private and read-only presets.
    public static func newMode(_ old: UInt16, _ preset: Preset, isDirectory: Bool) -> UInt16 {
        let perm = old & 0o7777
        switch preset {
        case .makeExecutable: return perm | 0o111
        case .removeExecute: return isDirectory ? perm : perm & ~0o111
        case .privateToOwner: return isDirectory ? 0o700 : 0o600
        case .readOnly: return isDirectory ? 0o500 : 0o400
        }
    }

    public struct Change: Sendable, Equatable { public let path: String; public let old: UInt16; public let new: UInt16 }

    /// Read a path's mode without following a link.
    public static func mode(of path: String) -> UInt16? {
        var st = stat()
        return lstat(path, &st) == 0 ? UInt16(st.st_mode & 0o7777) : nil
    }

    /// Apply a preset; symlinks are skipped (chmod would change the target). Returns what changed.
    public static func apply(_ preset: Preset, to path: String, isDirectory: Bool) throws -> Change? {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return nil }
        let old = UInt16(st.st_mode & 0o7777), new = newMode(old, preset, isDirectory: isDirectory)
        guard new != old else { return nil }
        guard chmod(path, mode_t(new)) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return Change(path: path, old: old, new: new)
    }

    public static func restore(_ c: Change) { _ = chmod(c.path, mode_t(c.old)) }
}

/// Decide whether pasted text is a file path worth putting in the path bar.
public enum PathText {
    /// Returns the cleaned path (quotes, `file://` and trailing newline removed), or nil if the text doesn't look like one.
    public static func looksLikePath(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.count <= 4096 else { return nil }
        if s.hasPrefix("file://"), let u = URL(string: s), u.isFileURL { s = u.path }
        if s.count >= 2, let f = s.first, let l = s.last, (f == "'" && l == "'") || (f == "\"" && l == "\"") { s = String(s.dropFirst().dropLast()) }
        s = s.replacingOccurrences(of: "\\ ", with: " ")
        guard s.range(of: #"^(~|/)[^\x00-\x1f]*$"#, options: .regularExpression) != nil else { return nil }
        if s.hasPrefix("~") && s != "~" && !s.hasPrefix("~/") { return nil }
        return s
    }
}
