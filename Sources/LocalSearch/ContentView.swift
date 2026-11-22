import SwiftUI
import FinderCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HSplitView {
            SidebarView().frame(minWidth: 160, idealWidth: 200, maxWidth: 320)
            VStack(spacing: 0) {
                TabBar()
                Divider()
                NavBar()
                Divider()
                FileListView()
                if let job = model.copyJob {
                    HStack {
                        ProgressView(value: Double(job.done), total: Double(max(job.total, 1))).frame(maxWidth: 220)
                        Text("\(job.title) \(job.done) of \(job.total)").font(.caption)
                        Button("Stop") { job.token.cancel() }.controlSize(.small)
                        Spacer()
                    }.padding(6)
                }
                if let w = model.warning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(w).font(.callout).lineLimit(2)
                        Spacer()
                        Button { model.warning = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.25))
                }
            }
            .frame(minWidth: 480)
        }
    }
}

struct TabBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.tabs) { tab in TabButton(tab: tab) }
                    // Dropping a tab here moves it to the very end.
                    Color.clear.frame(width: 60, height: 28).contentShape(Rectangle())
                        .onDrop(of: [.plainText], delegate: TabEndDropDelegate(model: model))
                }.padding(4)
            }
            Button { model.newTab() } label: { Image(systemName: "plus") }.buttonStyle(.plain).padding(.horizontal, 8)
        }
    }
}

struct TabButton: View {
    @Environment(AppModel.self) private var model
    let tab: TabState
    @State private var width: CGFloat = 0

    var body: some View {
        let selected = tab.id == model.selectedTabID
        let mark = model.tabDropMark?.tab == tab.id ? model.tabDropMark : nil
        HStack(spacing: 4) {
            Text(model.titleFor(tab)).lineLimit(1)
            Button { model.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.caption2) }
                .buttonStyle(.plain).opacity(model.tabs.count > 1 ? 0.6 : 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        // Files hovering over the tab highlight it; a tab being reordered shows a bar where it will land.
        .overlay { if mark?.files == true { RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.3)) } }
        .overlay(alignment: mark?.after == true ? .trailing : .leading) {
            if let mark, !mark.files { Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 1).offset(x: mark.after ? 3 : -3) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onTapGesture { model.selectTab(tab.id) }
        .draggable(tab.id.uuidString)
        .onDrop(of: [.fileURL, .plainText], delegate: TabDropDelegate(model: model, tab: tab, width: width))
        .contextMenu {
            Button("Duplicate Tab") { model.duplicateTab() }
            Button("Close Tab") { model.closeTab(tab.id) }
        }
    }
}

struct NavBar: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(model.current.back.isEmpty)
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(model.current.forward.isEmpty)
            Button { model.goUp() } label: { Image(systemName: "arrow.up") }
                .disabled(model.current.parentPath == nil)
            TextField("Path", text: $text)
                .textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { model.navigate(text, .typed); focused = false }
            Button { model.toggleFavorite() } label: {
                Image(systemName: model.store?.isFavorite(model.current.path) == true ? "star.fill" : "star")
            }
        }
        .buttonStyle(.borderless).padding(6)
        .onChange(of: model.current.path, initial: true) { _, p in text = p }
        .onChange(of: model.showAddressField) { _, v in if v { focused = true; model.showAddressField = false } }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("collapsed") private var collapsedRaw = ""

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        let _ = model.sidebarVersion
        let s = model.store
        let home = AppPaths.home
        List {
            section("Special Folders", items: ((try? s?.specialFolders()) ?? []).map { ($0.title, $0.path, "bolt.fill") }, source: .special)
            section("Favorites", items: ((try? s?.favorites()) ?? []).map { ($0.title, $0.path, "star") }, source: .favorite)
            section("Locations", items: [("Home", home, "house"), ("Macintosh HD", "/", "internaldrive"),
                                         ("Volumes", "/Volumes", "externaldrive"), ("Trash", "\(home)/.Trash", "trash")], source: .sidebar)
            section("Config", items: [".kiro", ".claude", ".aws", ".ssh"].map { ($0, "\(home)/\($0)", "gearshape") }, source: .sidebar)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func section(_ title: String, items: [(String, String, String)], source: NavSource) -> some View {
        let isOpen = !collapsed.contains(title)
        Section(isExpanded: Binding(get: { isOpen }, set: { open in
            var c = collapsed; if open { c.remove(title) } else { c.insert(title) }
            collapsedRaw = c.sorted().joined(separator: ",")
        })) {
            ForEach(items.prefix(FinderStore.sidebarLimit), id: \.1) { item in
                let exists = FileManager.default.fileExists(atPath: item.1)
                Button { model.navigate(item.1, source) } label: {
                    // The whole row (no gaps) is clickable and a drop target.
                    Label(item.0, systemImage: item.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).opacity(exists ? 1 : 0.4)
                .folderDropTarget(model, path: item.1, mode: title == "Favorites" ? .shortcutOrMove : .moveInto)
                .listRowInsets(EdgeInsets())
                .contextMenu {
                    Button("Open in New Tab") { model.newTab(path: item.1) }
                    if title == "Favorites" { Button("Remove from Favorites") { model.removeFavorite(item.1) } }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.1)]) }
                }
            }
        } header: {
            if title == "Favorites" {
                // Dropping a folder on the header adds it as a shortcut.
                Text(title).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .folderDropTarget(model, path: "", mode: .addShortcut)
            } else { Text(title) }
        }
    }
}

struct FileListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        let rows = model.sortedEntries
        Table(rows, selection: Binding(get: { model.selection }, set: { model.setSelection($0) })) {
            TableColumn("Name") { e in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: e.path)).resizable().frame(width: 16, height: 16)
                    if model.renamingPath == e.path {
                        RenameField(initial: e.name, isDirectory: e.isDirectory,
                                    onCommit: { model.commitRename(e.path, to: $0) }, onCancel: { model.renamingPath = nil })
                    } else { Text(e.name).lineLimit(1) }
                    Spacer(minLength: 0)
                    if e.isOnlineOnly { Image(systemName: "icloud").font(.caption).foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
                .modifier(FolderRowDrop(model: model, entry: e))
            }
            TableColumn("Added or Modified") { e in
                Text(e.addedOrModified.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }.width(min: 120, ideal: 150)
            TableColumn("Size") { e in
                Text(e.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)).foregroundStyle(.secondary)
            }.width(min: 60, ideal: 80)
            TableColumn("Kind") { e in Text(e.kind).foregroundStyle(.secondary).lineLimit(1) }.width(min: 80, ideal: 120)
        }
        .font(.system(size: model.textSize))
        .background(AppKitDragFix(paths: rows.map(\.path)))
        .onDrop(of: [.fileURL], delegate: FolderDropDelegate(model: model, path: model.current.path, mode: .copyIntoCurrent) { _, _ in })
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                if ids.count == 1 { Button("Rename") { model.renamingPath = ids.first } }
                Button("Quick Look") { model.quickLook() }
                Button("Show in Finder") { model.showInFinder() }
                Button("Copy") { model.copyFiles() }
                Button("Copy Paths") { model.copyPaths() }
                Button("Move to Trash") { model.trash(Array(ids)) }
                Divider()
            }
            Button("New Folder") { model.newFolder() }
            Button("New Text File") { model.newTextFile() }
            Button("Paste") { model.pasteFiles() }
        } primaryAction: { ids in
            let cmd = NSEvent.modifierFlags.contains(.command)
            for e in rows where ids.contains(e.path) { model.open(e, newTab: cmd) }
        }
        .onKeyPress(.space) { model.quickLook(); return .handled }
        .onKeyPress(.return) {
            guard model.renamingPath == nil, model.selection.count == 1 else { return .ignored }
            model.beginRename(); return .handled
        }
        .overlay(alignment: .topTrailing) { sortMenu }
    }

    private var sortMenu: some View {
        Menu {
            ForEach([("name", "Name"), ("date", "Added or Modified"), ("size", "Size"), ("kind", "Kind")], id: \.0) { k in
                Button(k.1 + (model.current.sortKey == k.0 ? (model.current.sortAscending ? "  ↑" : "  ↓") : "")) { model.setSort(key: k.0) }
            }
        } label: { Image(systemName: "arrow.up.arrow.down") }
            .menuStyle(.borderlessButton).frame(width: 30).padding(4)
    }
}

/// Folders in the list accept drops (moved in; ⌥ copies), like Finder.
struct FolderRowDrop: ViewModifier {
    let model: AppModel
    let entry: FileEntry
    func body(content: Content) -> some View {
        if entry.isDirectory { content.folderDropTarget(model, path: entry.path) } else { content }
    }
}
