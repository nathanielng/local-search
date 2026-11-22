import SwiftUI
import AppKit
import FinderCore

extension AppModel {
    func reloadCloudAndWeb() {
        cloudFolders = Cloud.load()
        webLocations = WebLocations.load()
        sidebarVersion += 1
    }

    /// The OneDrive app is running (by bundle id). This says nothing about whether files are synced.
    var oneDriveRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { Cloud.oneDriveBundleIDs.contains($0.bundleIdentifier ?? "") }
    }

    func openWebLocation(_ w: WebLocation) {
        guard let u = WebLocations.validURL(w.url) else { warning = "Only https:// addresses can be opened"; return }
        NSWorkspace.shared.open(u)
    }

    func removeWebLocation(_ w: WebLocation) {
        if WebLocations.remove(url: w.url) { reloadCloudAndWeb() }
    }

    func removeCloudFolder(_ path: String) {
        if Cloud.remove(path: path) { reloadCloudAndWeb() }
    }

    /// Choose a OneDrive folder by hand (for a location outside ~/Library/CloudStorage).
    func promptAddOneDriveFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Add"; p.message = "Choose a OneDrive folder to add to Cloud"
        guard p.runModal() == .OK, let u = p.url else { return }
        if !Cloud.add(path: u.path) { warning = "That folder is already in Cloud" }
        reloadCloudAndWeb()
    }

    /// A small dialog: title, https address and notes. The address is prefilled from the clipboard when it is a link.
    func promptAddWebLocation() {
        let title = NSTextField(frame: NSRect(x: 0, y: 56, width: 320, height: 22)); title.placeholderString = "Title"
        let url = NSTextField(frame: NSRect(x: 0, y: 28, width: 320, height: 22)); url.placeholderString = "https://…"
        let notes = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22)); notes.placeholderString = "Notes (optional)"
        if let clip = NSPasteboard.general.string(forType: .string), WebLocations.validURL(clip) != nil { url.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines) }
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        [title, url, notes].forEach(box.addSubview)
        let a = NSAlert()
        a.messageText = "Add Web Location"
        a.informativeText = "Opens in your default browser. Only https:// addresses are accepted."
        a.accessoryView = box
        a.addButton(withTitle: "Add"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = title
        guard a.runModal() == .alertFirstButtonReturn else { return }
        switch WebLocations.add(title: title.stringValue, url: url.stringValue, notes: notes.stringValue) {
        case .invalid: warning = "That isn't an https:// address"
        case .alreadyThere: warning = "That address is already in Web Locations"
        case .full: warning = "Web Locations is full (\(WebLocations.limit) items)"
        case .failed: warning = "Couldn't save to settings.json"
        case .added: break
        }
        reloadCloudAndWeb()
    }
}
