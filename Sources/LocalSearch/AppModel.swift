import SwiftUI
import AppKit
import Observation
import FinderCore

@MainActor @Observable
final class AppModel {
    let store: FinderStore?
    var tabs: [TabState] = []
    var selectedTabID: UUID
    var entries: [FileEntry] = []
    var loadedTabs: Set<UUID> = []
    var selection: Set<String> = []
    var showHidden = false
    var showAddressField = false
    var warning: String?
    var textSize: Double = 13 { didSet { store?.setKV("text_size", String(textSize)) } }
    var sidebarVersion = 0 // bump to refresh favorites
    var historyVersion = 0 // bump to refresh the History window
    var renamingPath: String?
    var copyJob: CopyJob?
    var undoStack: [UndoRecord] = []
    var showQuickFind = false
    var networkLocations: [NetworkLocation] = []
    var connecting: String?
    @ObservationIgnored var pendingSelection: String?
    var redoStack: [UndoRecord] = []
    var tabDropMark: (tab: UUID, after: Bool, files: Bool)?
    var dropHighlight: (id: UUID, zone: DropZone)?
    @ObservationIgnored private var highlightWatch: Task<Void, Never>?
    @ObservationIgnored let watcher = FolderWatcher()
    var undoLabel: String? { undoStack.last?.label }
    var redoLabel: String? { redoStack.last?.label }
    var retentionDays = 0 { didSet { store?.setKV("retention_days", String(retentionDays)) } }

    init() {
        let s = try? FinderStore(settingsURL: AppPaths.settingsURL)
        store = s
        var tabs: [TabState] = []
        var sel: UUID?
        if let r = try? s?.loadOpenTabs() { tabs = r.tabs; sel = r.selected }
        if tabs.isEmpty { tabs = [TabState(path: AppPaths.home)] }
        self.tabs = tabs
        selectedTabID = (sel.flatMap { id in tabs.contains { $0.id == id } ? id : nil }) ?? tabs[0].id
        showHidden = s?.kv("show_hidden") == "1"
        textSize = Double(s?.kv("text_size") ?? "") ?? 13
        retentionDays = Int(s?.kv("retention_days") ?? "") ?? 0
        try? s?.purgeHistory(olderThanDays: retentionDays)
        networkLocations = NetworkLocation.load()
        watchVolumes()
        if s == nil { warning = "History database could not be opened; nothing will be saved." }
        // Only the visible tab loads at launch.
        Task { @MainActor in self.ensureLoaded(self.selectedTabID) }
    }

    // MARK: Derived

    var tabIndex: Int? { tabs.firstIndex { $0.id == selectedTabID } }
    var current: TabState { tabs[tabIndex ?? 0] }
    var sortedEntries: [FileEntry] {
        let t = current
        let asc = t.sortAscending
        if t.sortKey == "none" { return entries } // no sorting: the order the folder lists in
        let items = entries.sorted { a, b in
            if a.isDirectory != b.isDirectory && t.sortKey == "name" { return a.isDirectory }
            let r: Bool
            switch t.sortKey {
            case "date": r = a.addedOrModified < b.addedOrModified
            case "size": r = a.sizeKey < b.sizeKey
            case "kind": r = a.kind.localizedStandardCompare(b.kind) == .orderedAscending
            default: r = a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return asc ? r : !r
        }
        return items
    }
    func titleFor(_ tab: TabState) -> String {
        let dup = tabs.contains { $0.id != tab.id && $0.title == tab.title }
        guard dup, let p = tab.parentPath else { return tab.title }
        return "\(tab.title) — \((p as NSString).lastPathComponent)"
    }

    // MARK: Loading and navigation

    /// Explains an unreadable folder. A rebuilt app has a new ad-hoc signature, so macOS may ask for access again.
    nonisolated static func accessHint(_ path: String) -> String {
        "Can't read \((path as NSString).abbreviatingWithTildeInPath). If macOS asked for folder access, allow it in System Settings › Privacy & Security › Files and Folders (or Full Disk Access). A rebuilt app counts as a new app."
    }

    nonisolated static func listAsync(_ path: String, hidden: Bool) async -> [FileEntry]? {
        await Task.detached { try? FileEntry.list(path, showHidden: hidden) }.value
    }

    /// Load a tab the first time it is shown. A missing folder falls back to its nearest parent.
    func ensureLoaded(_ id: UUID) {
        guard !loadedTabs.contains(id), let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        loadedTabs.insert(id)
        let fallback = nearestExistingFolder(tabs[i].path)
        Task {
            let list = await Self.listAsync(fallback, hidden: showHidden)
            if list == nil { warning = Self.accessHint(fallback) }
            guard let j = tabs.firstIndex(where: { $0.id == id }) else { return }
            if fallback != tabs[j].path { tabs[j].commit(to: fallback, source: .restore) }
            if id == selectedTabID, let list { entries = list; selection = Set(tabs[j].selection) }
            try? store?.logVisit(tabID: id, path: tabs[j].path, source: .restore)
            persist()
        }
    }

    /// Navigation commits to the stacks only once the folder has loaded.
    func navigate(_ path: String, _ source: NavSource) {
        guard let i = tabIndex else { return }
        let id = tabs[i].id
        let path = (path as NSString).expandingTildeInPath
        Task {
            guard let list = await Self.listAsync(path, hidden: showHidden) else {
                warning = Self.accessHint(path); return
            }
            guard let j = tabs.firstIndex(where: { $0.id == id }) else { return }
            let changed = tabs[j].path != path
            tabs[j].commit(to: path, source: source)
            loadedTabs.insert(id)
            if id == selectedTabID {
                entries = list; selection = []
                if let sel = pendingSelection { setSelection([sel]) } // e.g. a Quick Find hit
            }
            pendingSelection = nil
            if changed && source != .refresh { try? store?.logVisit(tabID: id, path: path, source: source) }
            warning = nil
            persist()
        }
    }

    func refresh() {
        guard let i = tabIndex else { return }
        let id = tabs[i].id, path = tabs[i].path
        Task {
            if let list = await Self.listAsync(path, hidden: showHidden), id == selectedTabID { entries = list }
        }
    }

    func goBack() { if let t = current.backTarget { navigate(t, .back) } }
    func goForward() { if let t = current.forwardTarget { navigate(t, .forward) } }
    func goUp() { if let p = current.parentPath { navigate(p, .parent) } }

    func open(_ entry: FileEntry, newTab: Bool = false) {
        if entry.isDirectory {
            if newTab { self.newTab(path: entry.path) } else { navigate(entry.path, .click) }
        } else {
            NSWorkspace.shared.open(entry.url)
            try? store?.db.exec("INSERT INTO file_opens(path,opened_at,app) VALUES(?,?,NULL)",
                                [.text(entry.path), .text(iso8601Now())])
        }
    }

    // MARK: Tabs

    func selectTab(_ id: UUID) {
        guard id != selectedTabID, let t = tabs.first(where: { $0.id == id }) else { return }
        selectedTabID = id
        selection = Set(t.selection)
        if loadedTabs.contains(id) { refresh() } else { entries = []; ensureLoaded(id) }
        persist()
    }

    func newTab(path: String? = nil) {
        let t = TabState(path: path ?? current.path)
        tabs.insert(t, at: (tabIndex ?? tabs.count - 1) + 1)
        selectedTabID = t.id
        entries = []; selection = []
        try? store?.logVisit(tabID: t.id, path: t.path, source: .newTab)
        loadedTabs.insert(t.id)
        refresh()
        persist()
    }

    func duplicateTab() {
        let d = current.duplicated()
        tabs.insert(d, at: (tabIndex ?? 0) + 1)
        selectedTabID = d.id; loadedTabs.insert(d.id)
        refresh(); persist()
    }

    func closeTab() { closeTab(selectedTabID) }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let t = tabs.remove(at: i)
        try? store?.closeTab(t.id, state: t)
        if id == selectedTabID {
            selectedTabID = tabs[min(i, tabs.count - 1)].id
            entries = []; loadedTabs.remove(selectedTabID); ensureLoaded(selectedTabID)
        }
        persist()
    }

    func reopenTab() {
        guard let t = (try? store?.closedTabs(limit: 1))?.first else { return }
        let folder = nearestExistingFolder(t.path)
        var t2 = t
        if folder != t.path { t2.commit(to: folder, source: .restore) }
        tabs.append(t2)
        selectedTabID = t2.id
        loadedTabs.insert(t2.id)
        try? store?.logVisit(tabID: t2.id, path: t2.path, source: .reopen)
        refresh(); persist()
    }

    /// Reorder: put `id` just before or after `target`.
    func moveTab(_ id: UUID, relativeTo target: UUID, after: Bool) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let t = tabs.remove(at: from)
        guard let to = tabs.firstIndex(where: { $0.id == target }) else { tabs.append(t); persist(); return }
        tabs.insert(t, at: after ? to + 1 : to)
        persist()
    }

    func moveTabToEnd(_ id: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == id }), from != tabs.count - 1 else { return }
        tabs.append(tabs.remove(at: from))
        persist()
    }

    // MARK: State

    /// Set both the column and the direction (what clicking a column header does).
    func setSort(key: String, ascending: Bool) {
        guard let i = tabIndex else { return }
        tabs[i].sortKey = key; tabs[i].sortAscending = ascending
        persist()
    }

    /// Remove all sorting.
    func clearSort() { setSort(key: "none", ascending: true) }

    func setSort(key: String) {
        guard let i = tabIndex else { return }
        if tabs[i].sortKey == key { tabs[i].sortAscending.toggle() } else { tabs[i].sortKey = key; tabs[i].sortAscending = true }
        persist()
    }

    func setSelection(_ all: Set<String>) {
        let s = all.filter { !$0.hasPrefix("hdr:") } // group headers can't be selected
        selection = s
        if let i = tabIndex { tabs[i].selection = s.map { ($0 as NSString).lastPathComponent }; persist() }
    }

    func persist() {
        try? store?.saveTabs(tabs, selected: selectedTabID)
        historyVersion += 1
        // Follow the visible folder so changes made elsewhere (a terminal, another app) show up.
        watcher.watch(current.path) { [weak self] in
            guard let self, self.renamingPath == nil else { return }
            self.refresh()
        }
    }

    func toggleHidden() {
        showHidden.toggle()
        store?.setKV("show_hidden", showHidden ? "1" : "0")
        refresh()
    }

    func toggleFavorite() {
        guard let s = store else { return }
        if s.isFavorite(current.path) { try? s.removeFavorite(path: current.path) }
        else if (try? s.addFavorite(path: current.path)) == false { warning = "Favorites is full (20 items)" }
        sidebarVersion += 1
    }

    // MARK: Drag and drop

    /// Moving is the default; ⌥ copies. Dropping on the file list copies into the current folder.
    func handleDrop(_ urls: [URL], onto folder: String, mode: FolderDropDelegate.Mode, zone: DropZone = .into, option: Bool, command: Bool) {
        var paths = urls.map { $0.standardized.path }
        guard !paths.isEmpty, let store else { return }
        // A folder dropped on a sidebar row becomes a shortcut; ⌘ moves it in instead.
        func isDir(_ p: String) -> Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
        if mode == .addShortcut {
            let dirs = paths.filter(isDir)
            if dirs.isEmpty { warning = "Only folders can be added to Favorites"; return }
            addShortcuts(dirs, after: nil, before: nil)
            return
        }
        // On a Favorites row, a folder dropped in the gap (top/bottom edge) becomes a shortcut there;
        // dropped on the middle of the row it is moved into that favorite like any other item.
        if mode == .shortcutOrMove && zone != .into && paths.allSatisfy(isDir) {
            addShortcuts(paths, after: zone == .after ? folder : nil, before: zone == .before ? folder : nil)
            return
        }
        let kind: FileOpKind = (mode == .copyIntoCurrent || option) ? .copy : .move
        if mode == .copyIntoCurrent { paths.removeAll { ($0 as NSString).deletingLastPathComponent == folder } }
        guard !paths.isEmpty else { return }
        runJob(kind, paths: paths, into: folder)
    }

    /// New shortcuts go right after the row they were dropped on (the end when dropped on the header).
    private func addShortcuts(_ folders: [String], after: String?, before: String?) {
        guard let store else { return }
        var anchor = after, upcoming = before
        for p in folders {
            if (try? store.insertFavorite(path: p, after: anchor, before: upcoming)) == false { warning = "Favorites is full (20 items)"; break }
            anchor = p; upcoming = nil
        }
        sidebarVersion += 1
    }

    /// Drag a sidebar shortcut to a new place in its own list.
    func reorderSidebar(section: String, path: String, relativeTo target: String, after: Bool) {
        let ok = section == "favorites"
            ? (try? store?.moveFavorite(path, relativeTo: target, after: after))
            : (try? store?.moveSpecialFolder(path, relativeTo: target, after: after))
        if ok == true { sidebarVersion += 1 }
    }

    func addSpecialFolder(_ path: String) {
        if (try? store?.addSpecialFolder(path: path)) == false { warning = "Special Folders is full (20 items)" }
        sidebarVersion += 1
    }

    func removeSpecialFolder(_ path: String) {
        try? store?.removeSpecialFolder(path: path)
        sidebarVersion += 1
    }

    func removeFavorite(_ path: String) {
        try? store?.removeFavorite(path: path)
        sidebarVersion += 1
    }

    /// A Quick Find hit: folders open in the tab (⌘: new tab); files are revealed in their folder
    /// (⌘: opened in their app).
    func openQuickFindResult(_ path: String, isDirectory: Bool, newTab: Bool) {
        if isDirectory {
            if newTab { self.newTab(path: path) } else { navigate(path, .quickFind) }
        } else if newTab {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            try? store?.db.exec("INSERT INTO file_opens(path,opened_at,app) VALUES(?,?,NULL)", [.text(path), .text(iso8601Now())])
        } else {
            pendingSelection = path
            navigate((path as NSString).deletingLastPathComponent, .quickFind)
        }
    }

    func openFolder(_ path: String, newTab: Bool) {
        if newTab { self.newTab(path: path) } else { navigate(path, .history) }
    }

    // MARK: File operations

    func trash(_ paths: [String]) {
        let (rec, results) = FileOps.trash(paths, store: store)
        if let rec { pushUndo(rec) }
        if let f = results.first(where: { $0.result == "failed" }) { warning = f.message }
        refresh(); historyVersion += 1
    }

    // MARK: Drop highlight

    func setDropHighlight(id: UUID, zone: DropZone) {
        if dropHighlight?.id != id || dropHighlight?.zone != zone { dropHighlight = (id, zone) }
        watchDragEnd()
    }

    func clearDropHighlight(id: UUID) {
        if dropHighlight?.id == id { dropHighlight = nil }
    }

    func setTabDropMark(tab: UUID, after: Bool, files: Bool) {
        if tabDropMark?.tab != tab || tabDropMark?.after != after || tabDropMark?.files != files { tabDropMark = (tab, after, files) }
        watchDragEnd()
    }

    func clearTabDropMark(tab: UUID) {
        if tabDropMark?.tab == tab { tabDropMark = nil }
    }

    /// Safety net: when the mouse button is up the drag is over, whatever drop callbacks were skipped.
    private func watchDragEnd() {
        guard highlightWatch == nil else { return }
        highlightWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 { self.dropHighlight = nil; self.tabDropMark = nil }
                if self.dropHighlight == nil && self.tabDropMark == nil { self.highlightWatch = nil; return }
            }
        }
    }

    /// A new action starts a new history: Redo is cleared.
    func pushUndo(_ r: UndoRecord, clearRedo: Bool = true) {
        undoStack.append(r)
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        if clearRedo { redoStack.removeAll() }
    }

    /// ⌘Z for file operations. Never overwrites; a step fails if the original name is taken again.
    func undo() { step(from: &undoStack, label: "undo") }

    /// ⇧⌘Z: re-applies what ⌘Z reversed.
    func redo() { step(from: &redoStack, label: "redo") }

    private func step(from stack: inout [UndoRecord], label: String) {
        guard let rec = stack.popLast(), let store else { return }
        let isUndo = label == "undo"
        Task {
            let out = await Task.detached { FileOps.undoWithRedo(rec, store: store) }.value
            if let inverse = out.redo {
                if isUndo { redoStack.append(inverse) } else { pushUndo(inverse, clearRedo: false) }
            }
            let failed = out.results.filter { $0.result != "done" }
            warning = failed.isEmpty ? nil : "Couldn't fully \(label) \(rec.label): \(failed[0].message ?? failed[0].result)"
            refresh(); historyVersion += 1
        }
    }

    private func logOp(_ op: String, src: String?, dst: String?, ok: Bool) {
        try? store?.db.exec("INSERT INTO file_ops(batch_id,op,src,dst,result,actor,at) VALUES(?,?,?,?,?,'app',?)",
                            [.text(UUID().uuidString), .text(op), src.map { .text($0) } ?? .null,
                             dst.map { .text($0) } ?? .null, .text(ok ? "done" : "failed"), .text(iso8601Now())])
    }
}
