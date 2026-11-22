import SwiftUI
import FinderCore

extension AppModel {
    /// Apply a permission preset to items (not recursive). Each change is recorded in file history.
    func changePermissions(_ preset: Permissions.Preset, paths: [String]) {
        let items = sortedEntries.filter { paths.contains($0.path) }.map { ($0.path, $0.name, $0.isDirectory) }
        Task {
            let out = await inBackground("Changing permissions…") { () -> ([Permissions.Change], String?) in
                var changes: [Permissions.Change] = [], err: String?
                for (path, name, isDir) in items {
                    do { if let c = try Permissions.apply(preset, to: path, isDirectory: isDir) { changes.append(c) } }
                    catch { err = err ?? "Couldn't change permissions on “\(name)”: \(error.localizedDescription)" }
                }
                return (changes, err)
            }
            for c in out.0 { logOp("chmod", src: c.path, dst: "\(Permissions.octal(c.old)) → \(Permissions.octal(c.new))", ok: true) }
            warning = out.1
            if !out.0.isEmpty { refresh(); historyVersion += 1 }
        }
    }
}
