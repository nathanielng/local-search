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
    var retentionDays = 0 { didSet { store?.setKV("retention_days", String(retentionDays)) } }

    init() {
        let s = try? FinderStore()
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
                warning = "Can't open \(path)"; return
            }
            guard let j = tabs.firstIndex(where: { $0.id == id }) else { return }
            let changed = tabs[j].path != path
            tabs[j].commit(to: path, source: source)
            loadedTabs.insert(id)
            if id == selectedTabID { entries = list; selection = [] }
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

    func moveTab(_ id: UUID, before target: UUID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let t = tabs.remove(at: from)
        let to = tabs.firstIndex { $0.id == target } ?? tabs.count
        tabs.insert(t, at: to)
        persist()
    }

    // MARK: State

    func setSort(key: String) {
        guard let i = tabIndex else { return }
        if tabs[i].sortKey == key { tabs[i].sortAscending.toggle() } else { tabs[i].sortKey = key; tabs[i].sortAscending = true }
        persist()
    }

    func setSelection(_ s: Set<String>) {
        selection = s
        if let i = tabIndex { tabs[i].selection = s.map { ($0 as NSString).lastPathComponent }; persist() }
    }

    func persist() { try? store?.saveTabs(tabs, selected: selectedTabID); historyVersion += 1 }

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
    func handleDrop(_ urls: [URL], onto folder: String, mode: FolderDropDelegate.Mode, option: Bool, command: Bool) {
        var paths = urls.map { $0.standardized.path }
        guard !paths.isEmpty, let store else { return }
        // A folder dropped on a sidebar row becomes a shortcut; ⌘ moves it in instead.
        if mode == .shortcutOrMove && !command && urls.allSatisfy({ $0.hasDirectoryPath }) {
            for p in paths where (try? store.addFavorite(path: p)) == false { warning = "Favorites is full (20 items)"; break }
            sidebarVersion += 1
            return
        }
        let kind: FileOpKind = (mode == .copyIntoCurrent || option) ? .copy : .move
        if mode == .copyIntoCurrent { paths.removeAll { ($0 as NSString).deletingLastPathComponent == folder } }
        guard !paths.isEmpty else { return }
        let sources = paths
        Task {
            let results = await Task.detached { FileOps.perform(kind, sources: sources, into: folder, store: store) }.value
            let refused = results.filter { $0.result != "done" }
            warning = refused.isEmpty ? nil : "\(refused.count) item(s) not \(kind == .move ? "moved" : "copied"): \(refused[0].message ?? refused[0].result)"
            refresh(); historyVersion += 1
        }
    }

    func openFolder(_ path: String, newTab: Bool) {
        if newTab { self.newTab(path: path) } else { navigate(path, .history) }
    }

    // MARK: File operations

    func newFolder() {
        let base = current.path
        var name = "untitled folder", n = 2
        while FileManager.default.fileExists(atPath: "\(base)/\(name)") { name = "untitled folder \(n)"; n += 1 }
        let dst = "\(base)/\(name)"
        do {
            try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: false)
            logOp("create", src: nil, dst: dst, ok: true)
            refresh(); selection = [dst]
        } catch { warning = error.localizedDescription; logOp("create", src: nil, dst: dst, ok: false) }
    }

    func trash(_ paths: [String]) {
        for p in paths {
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil); logOp("trash", src: p, dst: nil, ok: true) }
            catch { warning = error.localizedDescription; logOp("trash", src: p, dst: nil, ok: false) }
        }
        refresh()
    }

    private func logOp(_ op: String, src: String?, dst: String?, ok: Bool) {
        try? store?.db.exec("INSERT INTO file_ops(batch_id,op,src,dst,result,actor,at) VALUES(?,?,?,?,?,'app',?)",
                            [.text(UUID().uuidString), .text(op), src.map { .text($0) } ?? .null,
                             dst.map { .text($0) } ?? .null, .text(ok ? "done" : "failed"), .text(iso8601Now())])
    }
}
