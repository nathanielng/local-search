import SwiftUI
import AppKit
import FinderCore

extension AppModel {
    /// Reload the lists when settings.json changes on disk (an editor, a script, or this app itself).
    func watchSettings() {
        settingsStamp = Self.settingsModified()
        // An editor that saves by replacing the file changes the folder; one that writes in place only
        // changes the file. After a replace the old file handle is dead, so watch the new file again.
        let onChange: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.armSettingsFileWatcher()
            let stamp = Self.settingsModified()
            guard stamp != self.settingsStamp else { return }   // the database next to it changes all the time
            self.settingsStamp = stamp
            self.reloadNetworkLocations()
        }
        settingsWatcher.watch(AppPaths.supportDir.path, onChange: onChange)
        armSettingsFileWatcher()
    }

    private func armSettingsFileWatcher() {
        let path = AppPaths.settingsURL.path
        guard FileManager.default.fileExists(atPath: path) else { settingsFileWatcher.stop(); return }
        settingsFileWatcher.stop()
        settingsFileWatcher.watch(path) { [weak self] in
            guard let self else { return }
            let stamp = Self.settingsModified()
            self.armSettingsFileWatcher()
            guard stamp != self.settingsStamp else { return }
            self.settingsStamp = stamp
            self.reloadNetworkLocations()
        }
    }

    private static func settingsModified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: AppPaths.settingsURL.path))?[.modificationDate] as? Date
    }

    func revealSettingsFile() {
        let url = AppPaths.settingsURL
        if !FileManager.default.fileExists(atPath: url.path) { try? "{}\n".write(to: url, atomically: true, encoding: .utf8) }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func promptAddProject() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        p.prompt = "Add"; p.message = "Choose project folders"
        guard p.runModal() == .OK else { return }
        p.urls.forEach { addProject($0.path) }
    }

    func moveProject(_ path: String, up: Bool) {
        guard let i = projects.firstIndex(where: { $0.path == path }) else { return }
        let j = up ? i - 1 : i + 1
        guard projects.indices.contains(j) else { return }
        if Projects.move(path, relativeTo: projects[j].path, after: !up) { reloadProjects() }
    }
}
