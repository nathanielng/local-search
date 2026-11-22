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

    /// "Added or Modified": the later of the two.
    var addedOrModified: Date { max(modified, added) }
    var url: URL { URL(fileURLWithPath: path) }
    var sizeKey: Int64 { isDirectory ? -1 : size }

    static let alwaysShown: Set<String> = [".bashrc", ".zshrc", ".bash_profile", ".zprofile", ".env", ".envrc", ".gitconfig", ".gitignore"]

    static func list(_ folder: String, showHidden: Bool) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                                      .addedToDirectoryDateKey, .localizedTypeDescriptionKey, .isHiddenKey,
                                      .ubiquitousItemDownloadingStatusKey]
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
                             kind: isDir ? "Folder" : (v?.localizedTypeDescription ?? "Document"), isOnlineOnly: online)
        }
    }
}
