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

    /// Names in `sources` that already exist in `folder` (a source already at its own destination doesn't count).
    public static func conflicts(sources: [String], into folder: String) -> [String] {
        let dst = URL(fileURLWithPath: folder).standardized.path
        return sources.compactMap { raw in
            let src = URL(fileURLWithPath: raw).standardized.path
            let target = (dst as NSString).appendingPathComponent((src as NSString).lastPathComponent)
            return target != src && FileManager.default.fileExists(atPath: target) ? (src as NSString).lastPathComponent : nil
        }
    }

    /// Copy or move `sources` into `folder`. Nothing is overwritten silently: `conflict` decides what
    /// happens when the name exists (Keep Both by default). Replace sends the old item to the Trash
    /// only after the new copy succeeded.
    @discardableResult
    public static func perform(_ kind: FileOpKind, sources: [String], into folder: String,
                               store: FinderStore?, actor: String = "app",
                               conflict: ConflictChoice = .keepBoth, cancel: CancelToken? = nil,
                               progress: (@Sendable (Int, Int) -> Void)? = nil) -> [FileOpResult] {
        let batch = UUID().uuidString
        let fm = FileManager.default
        let dstFolder = URL(fileURLWithPath: folder).standardized.path
        var results: [FileOpResult] = []

        for (index, raw) in sources.enumerated() {
            if cancel?.isCancelled == true { break }
            progress?(index, sources.count)
            let src = URL(fileURLWithPath: raw).standardized.path
            let target = (dstFolder as NSString).appendingPathComponent((src as NSString).lastPathComponent)
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
            } else if conflict == .skip && target != src && fm.fileExists(atPath: target) {
                r.message = "already exists"
            } else {
                let dst = uniqueDestination(name: (src as NSString).lastPathComponent, in: dstFolder)
                do {
                    if kind == .move { try fm.moveItem(atPath: src, toPath: dst) }
                    else { try fm.copyItem(atPath: src, toPath: dst) }
                    r.dst = dst; r.result = "done"
                    if conflict == .replace && dst != target && target != src {
                        do {
                            try fm.trashItem(at: URL(fileURLWithPath: target), resultingItemURL: nil)
                            try fm.moveItem(atPath: dst, toPath: target)
                            r.dst = target
                        } catch { r.message = "kept both: couldn't replace (\(error.localizedDescription))" }
                    }
                } catch {
                    r.result = "failed"; r.message = error.localizedDescription
                }
            }
            results.append(r)
            try? store?.logFileOp(batch: batch, op: kind.rawValue, src: src, dst: r.dst ?? dstFolder,
                                  result: r.result, actor: actor)
        }
        progress?(results.count, sources.count)
        return results
    }

    // MARK: Create and rename

    @discardableResult
    public static func createFolder(in folder: String, store: FinderStore?, actor: String = "app") -> FileOpResult {
        create(in: folder, name: "untitled folder", store: store, actor: actor) {
            try FileManager.default.createDirectory(atPath: $0, withIntermediateDirectories: false)
        }
    }

    /// `untitled.txt`, then `untitled 2.txt`, …
    @discardableResult
    public static func createTextFile(in folder: String, store: FinderStore?, actor: String = "app") -> FileOpResult {
        create(in: folder, name: "untitled.txt", store: store, actor: actor) {
            guard FileManager.default.createFile(atPath: $0, contents: Data()) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    private static func create(in folder: String, name: String, store: FinderStore?, actor: String,
                               make: (String) throws -> Void) -> FileOpResult {
        let dst = uniqueDestination(name: name, in: folder)
        var r = FileOpResult(src: dst, dst: dst, result: "done", message: nil)
        do { try make(dst) } catch { r.result = "failed"; r.dst = nil; r.message = error.localizedDescription }
        try? store?.logFileOp(batch: UUID().uuidString, op: "create", src: nil, dst: dst, result: r.result, actor: actor)
        return r
    }

    /// Rename in place. Never overwrites; case-only changes are allowed; protected locations are refused.
    @discardableResult
    public static func rename(_ path: String, to newName: String, store: FinderStore?, actor: String = "app") -> FileOpResult {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: path).standardized.path
        let old = (src as NSString).lastPathComponent
        var r = FileOpResult(src: src, dst: nil, result: "skipped", message: nil)
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains(":") {
            r.message = "invalid name"
        } else if name == old {
            r.message = "unchanged"
        } else if isProtected(src) {
            r.message = "protected location"
        } else {
            let dst = ((src as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
            let caseOnly = name.lowercased() == old.lowercased()
            if fm.fileExists(atPath: dst) && !caseOnly {
                r.result = "failed"; r.message = "“\(name)” already exists"
            } else {
                do {
                    if caseOnly { // two steps so case-insensitive volumes accept it
                        let tmp = src + ".rename-\(UUID().uuidString.prefix(8))"
                        try fm.moveItem(atPath: src, toPath: tmp)
                        try fm.moveItem(atPath: tmp, toPath: dst)
                    } else { try fm.moveItem(atPath: src, toPath: dst) }
                    r.result = "done"; r.dst = dst
                } catch { r.result = "failed"; r.message = error.localizedDescription }
            }
            try? store?.logFileOp(batch: UUID().uuidString, op: "rename", src: src, dst: r.dst ?? dst,
                                  result: r.result, actor: actor)
        }
        return r
    }
}

public enum ConflictChoice: String, Sendable { case keepBoth, replace, skip }

public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
