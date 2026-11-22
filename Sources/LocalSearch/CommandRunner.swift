import Foundation
import Darwin

/// Runs one shell command with `zsh -l -c` in a folder and streams its output.
/// Stop ends the whole process tree, not just the shell.
final class CommandProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private(set) var stopped = false

    /// `onOutput` gets chunks of text on a background queue; `onExit` the exit code (or 143 after Stop).
    func start(command: String, folder: String, onOutput: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"; env["NO_COLOR"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { onOutput(String(decoding: d, as: UTF8.self)) }
        }
        process.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            if let rest = try? pipe.fileHandleForReading.readToEnd(), !rest.isEmpty { onOutput(String(decoding: rest, as: UTF8.self)) }
            let wasStopped = self?.isStopped ?? false
            onExit(wasStopped ? 143 : p.terminationStatus)
        }
        try process.run()
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        guard process.isRunning else { return }
        Self.kill(tree: process.processIdentifier, signal: SIGTERM)
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { Self.kill(tree: pid, signal: SIGKILL) }
    }

    /// Children first, then the parent, so nothing is orphaned.
    static func kill(tree pid: pid_t, signal sig: Int32) {
        guard pid > 0 else { return }
        let p = Process(); let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-P", String(pid)]
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if let child = pid_t(line) { kill(tree: child, signal: sig) }
            }
        }
        Darwin.kill(pid, sig)
    }
}
