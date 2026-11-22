import Foundation
import NetFS

/// A remote folder from the local settings.json (`network_locations`). Never committed: the file lives
/// in Application Support, outside the repository.
///
/// ```json
/// { "network_locations": [
///   { "title": "NAS",  "kind": "smb", "url": "smb://nas.example/share" },
///   { "title": "Pi",   "kind": "ssh", "host": "pi.example", "user": "me", "path": "/home/me" } ] }
/// ```
public struct NetworkLocation: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case smb, ssh }
    public var title: String
    public var kind: Kind
    public var url: String?      // smb://host/share
    public var host: String?     // ssh
    public var user: String?
    public var path: String?

    public var id: String { title }
    public init(title: String, kind: Kind, url: String? = nil, host: String? = nil, user: String? = nil, path: String? = nil) {
        self.title = title; self.kind = kind; self.url = url; self.host = host; self.user = user; self.path = path
    }

    public static func load(from url: URL = AppPaths.settingsURL) -> [NetworkLocation] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["network_locations"] as? [[String: Any]] else { return [] }
        return list.prefix(FinderStore.sidebarLimit).compactMap { d in
            guard let title = d["title"] as? String, let k = (d["kind"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
            return NetworkLocation(title: title, kind: k, url: d["url"] as? String, host: d["host"] as? String,
                                   user: d["user"] as? String, path: d["path"] as? String)
        }
    }

    /// Add an ssh location for a Host alias from ~/.ssh/config, keeping every other key in the file.
    @discardableResult
    public static func addSSH(alias: String, at url: URL = AppPaths.settingsURL) -> Bool {
        var obj = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var list = obj["network_locations"] as? [[String: Any]] ?? []
        guard !list.contains(where: { $0["kind"] as? String == "ssh" && $0["host"] as? String == alias }) else { return false }
        list.append(["title": alias, "kind": "ssh", "host": alias, "path": ""])
        obj["network_locations"] = list
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Where an ssh location is mounted: inside our own support folder, one folder per title.
    public var sshMountPoint: String {
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return AppPaths.supportDir.appendingPathComponent("mnt/\(slug)").path
    }
}

public struct MountedVolume: Sendable, Equatable {
    public var mountPoint: String
    public var from: String
    public var fsType: String
    public var isNetwork: Bool { ["smbfs", "afpfs", "nfs", "webdav", "macfuse", "osxfuse", "fusefs", "fuse-t"].contains(fsType) }
}

public enum Mounts {
    /// Every mounted file system, from getmntinfo.
    public static func all() -> [MountedVolume] {
        var buf: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&buf, MNT_NOWAIT)
        guard n > 0, let buf else { return [] }
        func str<T>(_ v: inout T) -> String {
            withUnsafePointer(to: &v) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
        }
        return (0..<Int(n)).map { i in
            var s = buf[i]
            return MountedVolume(mountPoint: str(&s.f_mntonname), from: str(&s.f_mntfromname), fsType: str(&s.f_fstypename))
        }
    }

    /// `//USER@HOST._smb._tcp.local/share` and `smb://user@host/share` both reduce to ("host", "share").
    static func hostAndShare(_ s: String) -> (String, String)? {
        var t = s
        if let r = t.range(of: "://") { t = String(t[r.upperBound...]) } else if t.hasPrefix("//") { t.removeFirst(2) }
        if let at = t.lastIndex(of: "@"), at < (t.firstIndex(of: "/") ?? t.endIndex) { t = String(t[t.index(after: at)...]) }
        let parts = t.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let hostRaw = parts.first else { return nil }
        var host = hostRaw.lowercased()
        for suffix in ["._smb._tcp.local", ".local"] where host.hasSuffix(suffix) { host.removeLast(suffix.count) }
        let share = (parts.count > 1 ? parts[1] : "").removingPercentEncoding?.lowercased() ?? ""
        return (host, share)
    }

    /// The mount point of an SMB location if it is already mounted.
    public static func smbMountPoint(for url: String, in volumes: [MountedVolume] = all()) -> String? {
        guard let want = hostAndShare(url) else { return nil }
        return volumes.first { v in
            guard v.fsType == "smbfs", let have = hostAndShare(v.from) else { return false }
            return have.0 == want.0 && (want.1.isEmpty || have.1 == want.1)
        }?.mountPoint
    }

    public static func mountPoint(for loc: NetworkLocation, in volumes: [MountedVolume] = all()) -> String? {
        switch loc.kind {
        case .smb: return loc.url.flatMap { smbMountPoint(for: $0, in: volumes) }
        case .ssh: return volumes.first { $0.mountPoint == loc.sshMountPoint }?.mountPoint
        }
    }
}

public enum NetworkError: Error, CustomStringConvertible {
    case message(String)
    public var description: String { if case .message(let m) = self { return m }; return "" }
}

public enum NetworkMounter {
    public static let sshfsCandidates = ["/opt/homebrew/bin/sshfs", "/usr/local/bin/sshfs"]
    public static var sshfsPath: String? { sshfsCandidates.first { FileManager.default.isExecutableFile(atPath: $0) } }

    /// Mount and return the mount point. SMB goes through the system's NetFS (it asks for a password and
    /// offers the keychain). SSH needs `sshfs` (FUSE-T) and key-based login.
    public static func mount(_ loc: NetworkLocation, timeout: TimeInterval = 25) throws -> String {
        if let existing = Mounts.mountPoint(for: loc) { return existing }
        switch loc.kind {
        case .smb:
            guard let s = loc.url, let url = URL(string: s) else { throw NetworkError.message("“\(loc.title)” has no valid smb:// url in settings.json") }
            let open = NSMutableDictionary()
            open[kNAUIOptionKey as String] = kNAUIOptionAllowUI as String // let macOS show the sign-in dialog
            var points: Unmanaged<CFArray>?
            let rc = NetFSMountURLSync(url as CFURL, nil, nil, nil, open, nil, &points)
            let list = points?.takeRetainedValue() as? [String] ?? []
            if rc == 0 || rc == EEXIST, let p = list.first ?? Mounts.smbMountPoint(for: s) { return p }
            throw NetworkError.message(rc == Int32(ECANCELED) || rc == -128 ? "Connection cancelled" : "Couldn't connect to “\(loc.title)” (error \(rc))")
        case .ssh:
            guard let sshfs = sshfsPath else {
                throw NetworkError.message("SSH folders need sshfs. Install FUSE-T and fuse-t-sshfs (see docs/NETWORK.md), then try again.")
            }
            guard let alias = loc.host, !alias.isEmpty else { throw NetworkError.message("“\(loc.title)” has no host in settings.json") }
            guard SSHConfig.hosts().contains(alias) else {
                throw NetworkError.message("“\(alias)” isn't a Host in ~/.ssh/config. SSH locations use your ssh config for the user, key and port.")
            }
            let mp = loc.sshMountPoint
            try FileManager.default.createDirectory(atPath: mp, withIntermediateDirectories: true)
            // FUSE-T's sshfs keeps running as the mount server, so don't wait for it to exit: start it and
            // watch for the mount to appear.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: sshfs)
            p.arguments = ["\(alias):\(loc.path ?? "")", mp, "-o",
                           "volname=\(loc.title),reconnect,ServerAliveInterval=15,ConnectTimeout=10,BatchMode=yes,StrictHostKeyChecking=accept-new"]
            let err = Pipe()
            p.standardError = err; p.standardOutput = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            try p.run()
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if Mounts.all().contains(where: { $0.mountPoint == mp }) { return mp }
                if !p.isRunning { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
            if Mounts.all().contains(where: { $0.mountPoint == mp }) { return mp }
            if p.isRunning { p.terminate() }
            var detail = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty { detail = diagnose(alias) }
            throw NetworkError.message("Couldn't connect to “\(loc.title)”: \(detail)")
        }
    }

    /// Why can't we reach it? Try a plain ssh with the same options and report what it says.
    static func diagnose(_ alias: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", alias, "true"]
        let err = Pipe()
        p.standardError = err; p.standardOutput = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return "ssh couldn't start (\(error.localizedDescription))" }
        let done = Date().addingTimeInterval(8)
        while p.isRunning && Date() < done { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning { p.terminate(); return "timed out reaching “\(alias)” (is it on and on this network?)" }
        let msg = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0
            ? "ssh works but the mount didn't appear in time (approve FUSE-T in System Settings › Privacy & Security?)"
            : "ssh failed: \(msg)"
    }
}

/// The `Host` aliases in ~/.ssh/config. SSH locations must name one of these, and ssh itself supplies the
/// user, key and port. Wildcard patterns (`*`, `?`, `!`) are not usable as a name and are skipped.
public enum SSHConfig {
    public static var url: URL { AppPaths.home.isEmpty ? URL(fileURLWithPath: "/") : URL(fileURLWithPath: AppPaths.home + "/.ssh/config") }

    public static func hosts(from text: String? = nil) -> [String] {
        guard let text = text ?? (try? String(contentsOf: url, encoding: .utf8)) else { return [] }
        var out: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" }).map(String.init)
            guard parts.count >= 2, parts[0].lowercased() == "host" else { continue }
            for h in parts.dropFirst() where !h.contains(where: { "*?!".contains($0) }) && !out.contains(h) { out.append(h) }
        }
        return out
    }
}
