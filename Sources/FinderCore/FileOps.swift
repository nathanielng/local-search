import Foundation

public enum FileOpKind: String, Sendable { case copy, move }

public struct FileOpResult: Sendable, Equatable {
    public var src: String
    public var dst: String?
    public var result: String   // done | skipped | failed
    public var message: String?
}

/// Copy/move with "Keep Both" naming, protected-location checks and `file_ops` logging.
/// Nothing is ever overwritten.
public enum FileOps {
    static let systemRoots: Set<String> = ["/", "/System", "/Library", "/Users", "/Applications", "/usr", "/bin",
                                           "/sbin", "/etc", "/var", "/private", "/opt", "/Volumes", "/cores", "/dev"]
    static let systemPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/"]

    /// System folders, the home folder and its top-level folders can't be moved.
    public static func isProtected(_ path: String, home: String = AppPaths.home) -> Bool {
        let p = URL(fileURLWithPath: path).standardized.path
        if systemRoots.contains(p) || p == home { return true }
        if (p as NSString).deletingLastPathComponent == home {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
        }
        return false
    }

    public static func isSystemPath(_ path: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardized.path
        return systemRoots.contains(p) || systemPrefixes.contains { p.hasPrefix($0) }
    }

    /// "name.ext" → "name 2.ext", "name 3.ext"… in `folder`.
    public static func uniqueDestination(name: String, in folder: String) -> String {
        let fm = FileManager.default
        var candidate = (folder as NSString).appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate) || (try? fm.destinationOfSymbolicLink(atPath: candidate)) != nil else { return candidate }
        let ns = name as NSString
        let ext = ns.pathExtension, stem = ns.deletingPathExtension
        var n = 2
        repeat {
            let leaf = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            candidate = (folder as NSString).appendingPathComponent(leaf)
            n += 1
        } while fm.fileExists(atPath: candidate)
        return candidate
    }

    @discardableResult
    public static func perform(_ kind: FileOpKind, sources: [String], into folder: String,
                               store: FinderStore?, actor: String = "app") -> [FileOpResult] {
        let batch = UUID().uuidString
        let fm = FileManager.default
        let dstFolder = URL(fileURLWithPath: folder).standardized.path
        var results: [FileOpResult] = []

        for raw in sources {
            let src = URL(fileURLWithPath: raw).standardized.path
            var r = FileOpResult(src: src, dst: nil, result: "skipped", message: nil)
            if kind == .move && isProtected(src) {
                r.message = "protected location"
            } else if kind == .move && isSystemPath(dstFolder) {
                r.message = "destination is a system folder"
            } else if dstFolder == src || dstFolder.hasPrefix(src + "/") {
                r.message = "can't put a folder inside itself"
            } else if kind == .move && (src as NSString).deletingLastPathComponent == dstFolder {
                r.message = "already in this folder"
            } else if !fm.fileExists(atPath: src) {
                r.result = "failed"; r.message = "source no longer exists"
            } else {
                let dst = uniqueDestination(name: (src as NSString).lastPathComponent, in: dstFolder)
                do {
                    if kind == .move { try fm.moveItem(atPath: src, toPath: dst) }
                    else { try fm.copyItem(atPath: src, toPath: dst) }
                    r.dst = dst; r.result = "done"
                } catch {
                    r.result = "failed"; r.message = error.localizedDescription
                }
            }
            results.append(r)
            try? store?.logFileOp(batch: batch, op: kind.rawValue, src: src, dst: r.dst ?? dstFolder,
                                  result: r.result, actor: actor)
        }
        return results
    }
}
