import Foundation

public enum NavSource: String, Codable, Sendable, CaseIterable {
    case typed, click, sidebar, favorite, back, forward, parent
    case newTab = "new_tab", restore, reopen, history
    case pathBar = "path_bar", refresh, special
    case quickFind = "quick_find", project, recent
}

/// One tab: a UUID assigned at creation plus independent Back/Forward stacks.
public struct TabState: Codable, Sendable, Identifiable, Equatable {
    public static let stackLimit = 500

    public let id: UUID
    public var path: String
    public var back: [String]
    public var forward: [String]
    public var sortKey: String
    public var sortAscending: Bool
    public var selection: [String]

    public init(id: UUID = UUID(), path: String, back: [String] = [], forward: [String] = [],
                sortKey: String = "name", sortAscending: Bool = true, selection: [String] = []) {
        self.id = id; self.path = path; self.back = back; self.forward = forward
        self.sortKey = sortKey; self.sortAscending = sortAscending; self.selection = selection
    }

    public var title: String {
        path == "/" ? "/" : (path as NSString).lastPathComponent
    }

    public var parentPath: String? {
        path == "/" ? nil : (path as NSString).deletingLastPathComponent
    }

    /// Where Back/Forward would go, without committing.
    public var backTarget: String? { back.last }
    public var forwardTarget: String? { forward.last }

    /// Commit a navigation after the folder has loaded.
    public mutating func commit(to newPath: String, source: NavSource) {
        guard newPath != path else { return }
        switch source {
        case .back:
            if !back.isEmpty { back.removeLast() }
            forward.append(path)
        case .forward:
            if !forward.isEmpty { forward.removeLast() }
            back.append(path)
        case .restore, .refresh:
            break // path replaced without touching the stacks
        default:
            back.append(path)
            forward.removeAll()
        }
        if back.count > Self.stackLimit { back.removeFirst(back.count - Self.stackLimit) }
        path = newPath
        selection = []
    }

    /// Duplicate gets a new UUID but inherits the stacks.
    public func duplicated() -> TabState {
        var t = self; t = TabState(id: UUID(), path: path, back: back, forward: forward,
                                   sortKey: sortKey, sortAscending: sortAscending, selection: selection)
        return t
    }
}

public func nearestExistingFolder(_ path: String, fileManager fm: FileManager = .default) -> String {
    var p = path
    var isDir: ObjCBool = false
    while p != "/" && !(fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue) {
        p = (p as NSString).deletingLastPathComponent
        if p.isEmpty { return "/" }
    }
    return p
}
