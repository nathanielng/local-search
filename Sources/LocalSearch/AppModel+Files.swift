import SwiftUI
import AppKit
import FinderCore

/// Progress for a background copy or move.
@MainActor @Observable
final class CopyJob {
    let title: String
    let total: Int
    var done = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var current = ""
    var preparing = true
    var stopping = false
    let started = Date()
    let token = CancelToken()
    init(title: String, total: Int) { self.title = title; self.total = total }

    func apply(_ p: TransferProgress) {
        done = p.itemsDone; bytesDone = p.bytesDone; bytesTotal = p.bytesTotal; current = p.current
        preparing = false
    }
    var fraction: Double {
        bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : Double(done) / Double(max(total, 1))
    }
    /// "Copying report.mov · 1.2 of 4.8 GB · 85 MB/s · item 2 of 5"
    var summary: String {
        if preparing { return "\(title): preparing…" }
        if stopping { return "Stopping…" }
        var parts = ["\(title) \(current)"]
        if bytesTotal > 0 {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append("\(f.string(fromByteCount: bytesDone)) of \(f.string(fromByteCount: bytesTotal))")
            let secs = Date().timeIntervalSince(started)
            if secs > 1.5, bytesDone > 0 {
                let rate = Double(bytesDone) / secs
                parts.append("\(f.string(fromByteCount: Int64(rate)))/s")
                let left = Double(bytesTotal - bytesDone) / rate
                if left > 3, left < 86400 { parts.append(left < 90 ? "about \(Int(left)) s left" : "about \(Int(left / 60) + 1) min left") }
            }
        }
        if total > 1 { parts.append("item \(min(done + 1, total)) of \(total)") }
        return parts.joined(separator: " · ")
    }
}

struct QueuedJob {
    let kind: FileOpKind
    let paths: [String]
    let folder: String
    let choice: ConflictChoice
}

extension AppModel {
    var selectedEntries: [FileEntry] { sortedEntries.filter { selection.contains($0.path) } }

    // MARK: Create and rename

    func newFolder() { let st = store; create { FileOps.createFolder(in: $0, store: st) } }
    func newTextFile() { let st = store; create { FileOps.createTextFile(in: $0, store: st) } }

    /// Created in the current folder, selected, and opened for renaming.
    private func create(_ make: @escaping @Sendable (String) -> FileOpResult) {
        let folder = current.path, id = selectedTabID
        Task {
            let r = await inBackground("Creating…") { make(folder) }
            guard let dst = r.dst else { warning = r.message; return }
            pushUndo(UndoRecord(label: dst.hasSuffix(".txt") ? "New Text File" : "New Folder", steps: [.trash(dst)]))
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
        let store = self.store
        Task {
            let r = await inBackground("Renaming…") { FileOps.rename(path, to: name, store: store) }
            finishRename(path, r)
        }
    }

    private func finishRename(_ path: String, _ r: FileOpResult) {
        warning = nil
        if r.result == "failed" || r.message == "invalid name" || r.message == "protected location" {
            let old = (path as NSString).lastPathComponent
            let reason: String
            switch r.message {
            case "invalid name": reason = "Names can't be empty or contain “/” or “:”."
            case "protected location": reason = "“\(old)” is a system or home folder and can't be renamed."
            default: reason = r.message ?? "Unknown error."
            }
            warning = "Couldn't rename “\(old)”: \(reason)"
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "Couldn't rename “\(old)”"
            a.informativeText = reason + (r.message?.hasSuffix("already exists") == true ? " Choose a different name." : "")
            a.addButton(withTitle: "OK")
            a.runModal()
        }
        if let dst = r.dst {
            setSelection([dst])
            pushUndo(UndoRecord(label: "Rename", steps: [.moveBack(from: dst, to: r.src)]))
        }
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

    /// ⌥⌘V (Move Item Here): move the pasteboard's files into the current folder.
    func moveFilesHere() {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        runJob(.move, paths: urls.map { $0.standardized.path }, into: current.path)
    }

    // MARK: Background jobs

    /// Copies ask what to do about name clashes (Keep Both / Replace / Skip / Stop); moves always keep both.
    /// A job started while another runs waits its turn.
    func runJob(_ kind: FileOpKind, paths: [String], into folder: String) {
        guard store != nil else { return }
        var choice = ConflictChoice.keepBoth
        if kind == .copy, !FileOps.conflicts(sources: paths, into: folder).isEmpty {
            guard let c = askConflict(FileOps.conflicts(sources: paths, into: folder)) else { return }
            choice = c
        }
        let q = QueuedJob(kind: kind, paths: paths, folder: folder, choice: choice)
        if copyJob == nil { start(q) } else { jobQueue.append(q) }
    }

    private func start(_ q: QueuedJob) {
        guard let store else { return }
        let job = CopyJob(title: q.kind == .copy ? "Copying" : "Moving", total: q.paths.count)
        copyJob = job
        Task {
            let results = await Task.detached {
                FileOps.perform(q.kind, sources: q.paths, into: q.folder, store: store, conflict: q.choice, cancel: job.token,
                                detail: { p in Task { @MainActor in job.apply(p) } })
            }.value
            copyJob = nil
            if let rec = UndoRecord.forJob(q.kind, results: results, conflict: q.choice) { pushUndo(rec) }
            let refused = results.filter { $0.result != "done" && $0.message != "stopped" }
            if job.token.isCancelled {
                jobQueue.removeAll()    // Stop ends everything that was waiting too
                warning = "Stopped after \(results.filter { $0.result == "done" }.count) of \(q.paths.count)"
            } else {
                warning = refused.isEmpty ? nil : "\(refused.count) item(s) not \(q.kind == .move ? "moved" : "copied"): \(refused[0].message ?? refused[0].result)"
            }
            refresh(); historyVersion += 1
            if !jobQueue.isEmpty { start(jobQueue.removeFirst()) }
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

extension AppModel {
    /// Run slow file work off the main thread. A small "working" note appears only if it takes more than a moment.
    func inBackground<T: Sendable>(_ label: String, _ work: @escaping @Sendable () -> T) async -> T {
        backgroundCount += 1
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if backgroundCount > 0 { backgroundLabel = label }
        }
        let r = await Task.detached { work() }.value
        backgroundCount -= 1
        if backgroundCount == 0 { backgroundLabel = nil }
        return r
    }
}
