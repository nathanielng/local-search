import Foundation

/// Watches one folder and calls back (debounced) when entries are added, removed or renamed,
/// for example by `mv` in a terminal.
@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?
    private(set) var path: String?

    func watch(_ path: String, onChange: @escaping @MainActor () -> Void) {
        guard path != self.path else { return }
        stop()
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                            eventMask: [.write, .delete, .rename, .extend, .link], queue: .main)
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.schedule(onChange) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        self.path = path
    }

    private func schedule(_ f: @escaping @MainActor () -> Void) {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { f() }
        }
    }

    func stop() {
        debounce?.cancel()
        source?.cancel()
        source = nil
        path = nil
    }
}
