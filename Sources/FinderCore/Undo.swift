import Foundation

/// What it takes to reverse one user action (a move, copy, rename, create or trash).
public struct UndoRecord: Sendable, Equatable {
    public enum Step: Sendable, Equatable {
        case moveBack(from: String, to: String)
        case trash(String)
    }
    public var label: String   // "Move", "Copy", "Rename", "New Folder", "Move to Trash"
    public var steps: [Step]

    public init(label: String, steps: [Step]) { self.label = label; self.steps = steps }

    /// Moves go back where they came from; copies are trashed. Replaced items can't be undone.
    public static func forJob(_ kind: FileOpKind, results: [FileOpResult], conflict: ConflictChoice) -> UndoRecord? {
        guard conflict != .replace else { return nil }
        let steps: [Step] = results.compactMap { r in
            guard r.result == "done", let dst = r.dst else { return nil }
            return kind == .move ? .moveBack(from: dst, to: r.src) : .trash(dst)
        }
        return steps.isEmpty ? nil : UndoRecord(label: kind == .move ? "Move" : "Copy", steps: steps)
    }
}

extension FileOps {
    /// Reverse an action. Never overwrites: if the original name is taken again, that step fails.
    @discardableResult
    public static func undo(_ record: UndoRecord, store: FinderStore?, actor: String = "app") -> [FileOpResult] {
        let fm = FileManager.default
        let batch = UUID().uuidString
        var results: [FileOpResult] = []
        for step in record.steps.reversed() {
            switch step {
            case .moveBack(let from, let to):
                var r = FileOpResult(src: from, dst: nil, result: "failed", message: nil)
                let caseOnly = from.lowercased() == to.lowercased()
                if !fm.fileExists(atPath: from) { r.message = "“\((from as NSString).lastPathComponent)” is no longer there" }
                else if fm.fileExists(atPath: to) && !caseOnly { r.message = "“\((to as NSString).lastPathComponent)” already exists" }
                else {
                    do {
                        try fm.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                        if caseOnly && from != to {
                            let tmp = from + ".undo-\(UUID().uuidString.prefix(8))"
                            try fm.moveItem(atPath: from, toPath: tmp)
                            try fm.moveItem(atPath: tmp, toPath: to)
                        } else { try fm.moveItem(atPath: from, toPath: to) }
                        r.result = "done"; r.dst = to
                    } catch { r.message = error.localizedDescription }
                }
                results.append(r)
                try? store?.logFileOp(batch: batch, op: "move", src: from, dst: to, result: r.result, actor: actor)
            case .trash(let p):
                var r = FileOpResult(src: p, dst: nil, result: "failed", message: nil)
                if !fm.fileExists(atPath: p) { r.message = "“\((p as NSString).lastPathComponent)” is no longer there" }
                else {
                    do { try fm.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil); r.result = "done" }
                    catch { r.message = error.localizedDescription }
                }
                results.append(r)
                try? store?.logFileOp(batch: batch, op: "trash", src: p, dst: nil, result: r.result, actor: actor)
            }
        }
        return results
    }

    /// Trash items and return what's needed to put them back.
    public static func trash(_ paths: [String], store: FinderStore?, actor: String = "app") -> (UndoRecord?, [FileOpResult]) {
        let fm = FileManager.default, batch = UUID().uuidString
        var steps: [UndoRecord.Step] = [], results: [FileOpResult] = []
        for p in paths {
            var r = FileOpResult(src: p, dst: nil, result: "failed", message: nil)
            var out: NSURL?
            do {
                try fm.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: &out)
                r.result = "done"
                if let t = out?.path { steps.append(.moveBack(from: t, to: p)); r.dst = t }
            } catch { r.message = error.localizedDescription }
            results.append(r)
            try? store?.logFileOp(batch: batch, op: "trash", src: p, dst: r.dst, result: r.result, actor: actor)
        }
        return (steps.isEmpty ? nil : UndoRecord(label: "Move to Trash", steps: steps), results)
    }
}
