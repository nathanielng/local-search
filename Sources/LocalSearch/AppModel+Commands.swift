import SwiftUI
import AppKit
import FinderCore

/// One run in the command panel.
@MainActor @Observable
final class CommandRun {
    var output = ""
    var running = true
    var exitCode: Int32?
    var truncated = false
    static let maxOutput = 400_000
    @ObservationIgnored var process: CommandProcess?

    func append(_ s: String) {
        guard output.utf8.count < Self.maxOutput else { truncated = true; return }
        output += s
    }
}

extension AppModel {
    static let actionsURL = AppPaths.supportDir.appendingPathComponent("actions.json")

    func loadActions() {
        if let bundled = Bundle.main.url(forResource: "actions", withExtension: "json") {
            Actions.installDefaults(bundled: bundled, to: Self.actionsURL)
        }
        guard let data = try? Data(contentsOf: Self.actionsURL) else { actions = []; actionsError = "actions.json is missing"; return }
        let r = Actions.parse(data)
        if let f = r.file { actions = f.actions; actionsError = nil } else { actionsError = r.error }   // keep last good on error
    }

    var actionContext: ActionContext {
        ActionContext(folder: current.path, selection: selectedEntries.map(\.path),
                      hasTool: { Self.toolExists($0) })
    }

    nonisolated static func toolExists(_ name: String) -> Bool {
        let key = "tool:" + name
        if let c = toolCache.value(key) { return c }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l", "-c", "command -v \(Actions.shellQuote(name))"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        let ok = ((try? p.run()) != nil) ? { p.waitUntilExit(); return p.terminationStatus == 0 }() : false
        toolCache.set(key, ok)
        return ok
    }

    func runCommand(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, commandRun?.running != true else { return }
        let folder = current.path
        let before = Set(entries.map(\.path))
        let run = CommandRun()
        commandRun = run
        let logID = store?.logCommandStart(tabID: selectedTabID, folder: folder, command: command)
        let proc = CommandProcess()
        run.process = proc
        let store = self.store
        do {
            try proc.start(command: command, folder: folder,
                onOutput: { s in Task { @MainActor in run.append(s) } },
                onExit: { code in
                    if let logID { store?.logCommandEnd(id: logID, exitCode: code) }
                    Task { @MainActor [weak self] in
                        run.running = false; run.exitCode = code
                        self?.finishCommand(folder: folder, before: before)
                    }
                })
        } catch {
            run.running = false; run.exitCode = 127
            run.append("Couldn't start: \(error.localizedDescription)\n")
            if let logID { store?.logCommandEnd(id: logID, exitCode: 127) }
        }
        historyVersion += 1
    }

    func stopCommand() { commandRun?.process?.stop() }

    /// When the command ends, refresh the folder and select what's new.
    private func finishCommand(folder: String, before: Set<String>) {
        historyVersion += 1
        guard current.path == folder else { return }
        Task { @MainActor in
            guard let list = await Self.listAsync(folder, hidden: showHidden), current.path == folder else { return }
            entries = list
            let added = Set(list.map(\.path)).subtracting(before)
            if !added.isEmpty { selection = added }
        }
    }

    /// Paths mentioned in output lines that exist, for find/grep results: "./a/b.txt" or "./a/b.txt:12:text".
    func pathsInOutput(_ line: String) -> String? {
        var s = line.trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: #":\d+:"#, options: .regularExpression) { s = String(s[..<r.lowerBound]) }
        let full = s.hasPrefix("/") ? s : (current.path as NSString).appendingPathComponent(s)
        let std = (full as NSString).standardizingPath
        return FileManager.default.fileExists(atPath: std) ? std : nil
    }
}

final class ToolCache: @unchecked Sendable {
    private var d: [String: Bool] = [:]; private let l = NSLock()
    func value(_ k: String) -> Bool? { l.lock(); defer { l.unlock() }; return d[k] }
    func set(_ k: String, _ v: Bool) { l.lock(); d[k] = v; l.unlock() }
}
let toolCache = ToolCache()
