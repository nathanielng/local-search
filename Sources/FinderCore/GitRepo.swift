import Foundation

/// Finds the git repository a folder belongs to by looking for `.git` here and above (a folder, or a file in worktrees and submodules).
public enum GitRepo {
    public static func root(of path: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        var p = (path as NSString).standardizingPath
        while true {
            if exists((p as NSString).appendingPathComponent(".git")) { return p }
            let parent = (p as NSString).deletingLastPathComponent
            if parent == p || parent.isEmpty { return nil }
            p = parent
        }
    }
}
