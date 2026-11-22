import FinderCore
import Foundation
import UniformTypeIdentifiers

struct FileEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    let added: Date
    let kind: String
    let isOnlineOnly: Bool
    var isSymlink = false
    var isExecutable = false
    /// A bundle such as an .app: it opens like a file, and its contents are shown on request.
    var isPackage = false
    var mode: UInt16 = 0
    /// A section header row (Group by Date); never selectable, draggable or openable.
    var isHeader = false

    static func header(_ title: String) -> FileEntry {
        FileEntry(path: "hdr:\(title)", name: title, isDirectory: false, size: 0, modified: .distantPast, added: .distantPast, kind: "", isOnlineOnly: false, isHeader: true)
    }

    /// "Added or Modified": the later of the two.
    var addedOrModified: Date { max(modified, added) }
    func date(_ mode: DateMode) -> Date {
        switch mode { case .addedOrModified: addedOrModified; case .modified: modified; case .added: added }
    }
    var url: URL { URL(fileURLWithPath: path) }
    var sizeKey: Int64 { isDirectory ? -1 : size }

    static let alwaysShown: Set<String> = [".bashrc", ".zshrc", ".bash_profile", ".zprofile", ".env", ".envrc", ".gitconfig", ".gitignore"]

    static func list(_ folder: String, showHidden: Bool) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                                      .addedToDirectoryDateKey, .localizedTypeDescriptionKey, .isHiddenKey,
                                      .ubiquitousItemDownloadingStatusKey, .isSymbolicLinkKey, .isExecutableKey, .isPackageKey]
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder),
                                                               includingPropertiesForKeys: keys, options: [])
        return urls.compactMap { u in
            let name = u.lastPathComponent
            if name == ".DS_Store" { return nil }
            if name.hasPrefix(".") && !showHidden && !alwaysShown.contains(name) { return nil }
            let v = try? u.resourceValues(forKeys: Set(keys))
            let mod = v?.contentModificationDate ?? .distantPast
            let isDir = v?.isDirectory ?? false
            let online = v?.ubiquitousItemDownloadingStatus.map { $0 != .current && $0 != .downloaded } ?? false
            return FileEntry(path: u.path, name: name, isDirectory: isDir, size: Int64(v?.fileSize ?? 0),
                             modified: mod, added: v?.addedToDirectoryDate ?? mod,
                             kind: isDir ? "Folder" : (v?.localizedTypeDescription ?? "Document"), isOnlineOnly: online,
                             isSymlink: v?.isSymbolicLink ?? false, isExecutable: !isDir && (v?.isExecutable ?? false),
                             isPackage: v?.isPackage ?? false, mode: Permissions.mode(of: u.path) ?? 0)
        }
    }
}

extension FileEntry {
    var color: FileColor { FileColor.classify(name: name, isDirectory: isDirectory, isSymlink: isSymlink, isExecutable: isExecutable) }
}

/// Which date the date column shows, sorts by and groups by.
enum DateMode: String, CaseIterable {
    case addedOrModified, modified, added
    var title: String {
        switch self { case .addedOrModified: "Added or Modified"; case .modified: "Modified"; case .added: "Added" }
    }
}

extension FileEntry {
    var permissionString: String { Permissions.string(mode: mode, isDirectory: isDirectory, isSymlink: isSymlink) }
    var permissionText: String { isHeader ? "" : permissionString + "  " + Permissions.octal(mode) }
}
