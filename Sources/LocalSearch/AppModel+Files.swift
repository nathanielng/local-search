import SwiftUI
import AppKit
import FinderCore

/// Progress for a background copy or move.
@MainActor @Observable
final class CopyJob {
    let title: String
    let total: Int
    var done = 0
    let token = CancelToken()
    init(title: String, total: Int) { self.title = title; self.total = total }
}

extension AppModel {
    var selectedEntries: [FileEntry] { sortedEntries.filter { selection.contains($0.path) } }

    // MARK: Create and rename

    func newFolder() { create { FileOps.createFolder(in: $0, store: self.store) } }
    func newTextFile() { create { FileOps.createTextFile(in: $0, store: self.store) } }

    /// Created in the current folder, selected, and opened for renaming.
    private func create(_ make: (String) -> FileOpResult) {
        let r = make(current.path)
        guard let dst = r.dst else { warning = r.message; return }
        let id = selectedTabID
        Task {
            if let list = await Self.listAsync(current.path, hidden: showHidden), id == selectedTabID { entries = list }
            setSelection([dst])
            renamingPath = dst
            historyVersion += 1
        }
    }

    func beginRename() {
        guard selection.count == 1, let p = selection.first else { return }
        renamingPath = p
    }

    func commitRename(_ path: String, to name: String) {
        renamingPath = nil
        let r = FileOps.rename(path, to: name, store: store)
        if r.result == "failed" || r.message == "invalid name" || r.message == "protected location" { warning = r.message } else { warning = nil }
        if let dst = r.dst { setSelection([dst]) }
        refresh(); historyVersion += 1
    }

    // MARK: Clipboard

    /// ⌘C: file URLs plus a text list of paths.
    func copyFiles() {
        let urls = selectedEntries.map(\.url)
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// ⌥⌘C: paths only.
    func copyPaths() {
        let paths = selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    /// ⌥⇧⌘C: file text for AI chats. Skips binaries and likely secrets.
    func copyFileText() {
        let paths = selectedEntries.map(\.path)
        let out = CopyText.build(paths: paths)
        guard !out.included.isEmpty else {
            warning = paths.isEmpty ? nil : "Nothing copied: " + (out.skipped.first.map { "\(($0.path as NSString).lastPathComponent) is \($0.reason)" } ?? "no text files")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out.text, forType: .string)
        warning = out.skipped.isEmpty ? nil : "Copied \(out.included.count) file(s); skipped \(out.skipped.count) (\(Set(out.skipped.map(\.reason)).sorted().joined(separator: ", ")))"
    }

    /// ⌘V: copy the pasteboard's files into the current folder.
    func pasteFiles() {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        runJob(.copy, paths: urls.map { $0.standardized.path }, into: current.path)
    }

    // MARK: Background jobs

    /// Copies ask what to do about name clashes (Keep Both / Replace / Skip / Stop); moves always keep both.
    func runJob(_ kind: FileOpKind, paths: [String], into folder: String) {
        guard let store, copyJob == nil else { if copyJob != nil { warning = "Another copy is still running" }; return }
        var choice = ConflictChoice.keepBoth
        if kind == .copy, !FileOps.conflicts(sources: paths, into: folder).isEmpty {
            guard let c = askConflict(FileOps.conflicts(sources: paths, into: folder)) else { return }
            choice = c
        }
        let job = CopyJob(title: kind == .copy ? "Copying" : "Moving", total: paths.count)
        copyJob = job
        let onFinish = choice
        Task {
            let results = await Task.detached {
                FileOps.perform(kind, sources: paths, into: folder, store: store, conflict: onFinish, cancel: job.token) { d, _ in
                    Task { @MainActor in job.done = d }
                }
            }.value
            copyJob = nil
            let refused = results.filter { $0.result != "done" }
            if job.token.isCancelled { warning = "Stopped after \(results.count) of \(paths.count)" }
            else { warning = refused.isEmpty ? nil : "\(refused.count) item(s) not \(kind == .move ? "moved" : "copied"): \(refused[0].message ?? refused[0].result)" }
            refresh(); historyVersion += 1
        }
    }

    private func askConflict(_ names: [String]) -> ConflictChoice? {
        let a = NSAlert()
        a.messageText = names.count == 1 ? "“\(names[0])” already exists in this folder" : "\(names.count) items already exist in this folder"
        a.informativeText = "Nothing is overwritten unless you choose Replace. Replaced items go to the Trash."
        for t in ["Keep Both", "Replace", "Skip", "Stop"] { a.addButton(withTitle: t) }
        switch a.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        case .alertThirdButtonReturn: return .skip
        default: return nil
        }
    }

    // MARK: Misc

    func quickLook() {
        QuickLookController.shared.toggle(selectedEntries.filter { !$0.isOnlineOnly }.map(\.url))
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedEntries.map(\.url))
    }

    func trashSelection() { trash(Array(selection)) }
}
