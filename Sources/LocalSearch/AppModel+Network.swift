import SwiftUI
import AppKit
import FinderCore

/// One row in the sidebar's Locations section.
struct SidebarRow: Identifiable {
    var title: String
    var path: String
    var symbol: String
    var network: NetworkLocation?
    var connected = true
    var ejectable = false
    var running = false      // Cloud: the OneDrive app is running
    var manual = false       // Cloud: added by hand, so it can be removed
    var id: String { path }
    /// A configured network location that isn't mounted: clicking connects it.
    var needsConnect: Bool { network != nil && !connected }
}

extension AppModel {
    /// Locations: Home, startup disk, external and network volumes (auto-detected, ejectable), configured
    /// network folders (dim until connected), Trash.
    func locationRows() -> [SidebarRow] {
        let home = AppPaths.home
        let vols = Mounts.all()
        var rows = [SidebarRow(title: "Home", path: home, symbol: "house"),
                    SidebarRow(title: "Macintosh HD", path: "/", symbol: "internaldrive")]
        var used = Set<String>()
        for loc in networkLocations {
            let mp = Mounts.mountPoint(for: loc, in: vols)
            if let mp { used.insert(mp) }
            rows.append(SidebarRow(title: loc.title, path: mp ?? "net:\(loc.id)", symbol: loc.kind == .smb ? "server.rack" : "terminal",
                                   network: loc, connected: mp != nil, ejectable: mp != nil))
        }
        for v in vols where v.mountPoint.hasPrefix("/Volumes/") && !used.contains(v.mountPoint) {
            rows.append(SidebarRow(title: (v.mountPoint as NSString).lastPathComponent, path: v.mountPoint,
                                   symbol: v.isNetwork ? "externaldrive.connected.to.line.below" : "externaldrive", ejectable: true))
        }
        rows.append(SidebarRow(title: "Trash", path: "\(home)/.Trash", symbol: "trash"))
        return rows
    }

    func addSSHLocation(_ alias: String) {
        if NetworkLocation.addSSH(alias: alias) { reloadNetworkLocations() }
    }

    func removeNetworkLocation(_ title: String) {
        if NetworkLocation.remove(title: title) { reloadNetworkLocations() }
    }

    static let badSettingsMessage = "settings.json isn't valid JSON, so the last good values are being kept"

    /// Re-read every list in settings.json. A malformed file keeps the last good values and shows a warning.
    func reloadNetworkLocations() {
        if SettingsFile.isMalformed(AppPaths.settingsURL) {
            warning = Self.badSettingsMessage
            return
        }
        if warning == Self.badSettingsMessage { warning = nil }
        networkLocations = NetworkLocation.load()
        projects = Projects.load()
        cloudFolders = Cloud.load()
        webLocations = WebLocations.load()
        sidebarVersion += 1
    }

    /// Re-read settings and redraw when volumes come and go or the app is brought forward.
    func watchVolumes() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sidebarVersion += 1 }
            }
        }
        // The OneDrive "running" dot follows the app starting and quitting.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sidebarVersion += 1 }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadNetworkLocations() }
        }
    }

    /// Mount (asking for a password if macOS needs one), then open it in the current tab.
    func connect(_ loc: NetworkLocation) {
        guard connecting == nil else { return }
        connecting = loc.title
        warning = nil
        Task {
            do {
                let mp = try await Task.detached { try NetworkMounter.mount(loc) }.value
                connecting = nil
                sidebarVersion += 1
                navigate(mp, .sidebar)
            } catch {
                connecting = nil
                warning = "\(error)"
                sidebarVersion += 1
            }
        }
    }

    func openRow(_ row: SidebarRow, source: NavSource) {
        if let loc = row.network, !row.connected { connect(loc) } else { navigate(row.path, source) }
    }

    /// Unmount without blocking the UI. Tabs inside the volume are closed first (a tab on a vanished
    /// mount can only hang or error); the last remaining tab moves to Home instead.
    func eject(_ mountPoint: String, title: String) {
        guard connecting == nil else { return }
        connecting = title
        warning = nil
        let prefix = mountPoint.hasSuffix("/") ? mountPoint : mountPoint + "/"
        func inside(_ p: String) -> Bool { p == mountPoint || p.hasPrefix(prefix) }
        for t in tabs where inside(t.path) {
            if tabs.count > 1 { closeTab(t.id) } else { navigate(AppPaths.home, .sidebar) }
        }
        Task {
            let failure: String? = await Task.detached {
                do { try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: mountPoint)); return nil }
                catch { return error.localizedDescription }
            }.value
            connecting = nil
            if let failure { warning = "Couldn't disconnect \(title): \(failure)" }
            sidebarVersion += 1
        }
    }
}
