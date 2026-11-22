import SwiftUI
import FinderCore

extension AppModel {
    /// Apply a permission preset to items (not recursive). Each change is recorded in file history.
    func changePermissions(_ preset: Permissions.Preset, paths: [String]) {
        var changed = 0, firstError: String?
        for e in sortedEntries where paths.contains(e.path) {
            do {
                if let c = try Permissions.apply(preset, to: e.path, isDirectory: e.isDirectory) {
                    changed += 1
                    logOp("chmod", src: c.path, dst: "\(Permissions.octal(c.old)) → \(Permissions.octal(c.new))", ok: true)
                }
            } catch {
                logOp("chmod", src: e.path, dst: nil, ok: false)
                firstError = firstError ?? "Couldn't change permissions on “\(e.name)”: \(error.localizedDescription)"
            }
        }
        warning = firstError
        if changed > 0 { refresh(); historyVersion += 1 }
    }
}
