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
                if let w = model.warning {
                    Text(w).font(.caption).padding(4).frame(maxWidth: .infinity, alignment: .leading)
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
                    ForEach(model.tabs) { tab in
                        let selected = tab.id == model.selectedTabID
                        HStack(spacing: 4) {
                            Text(model.titleFor(tab)).lineLimit(1)
                            Button { model.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.caption2) }
                                .buttonStyle(.plain).opacity(model.tabs.count > 1 ? 0.6 : 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectTab(tab.id) }
                        .draggable(tab.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            if let s = items.first, let id = UUID(uuidString: s) { model.moveTab(id, before: tab.id) }
                            return true
                        }
                        .contextMenu {
                            Button("Duplicate Tab") { model.duplicateTab() }
                            Button("Close Tab") { model.closeTab(tab.id) }
                        }
                    }
                }.padding(4)
            }
            Button { model.newTab() } label: { Image(systemName: "plus") }.buttonStyle(.plain).padding(.horizontal, 8)
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
                Button { model.navigate(item.1, source) } label: { Label(item.0, systemImage: item.2) }
                    .buttonStyle(.plain).opacity(exists ? 1 : 0.4)
            }
        } header: { Text(title) }
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
                    Text(e.name).lineLimit(1)
                    if e.isOnlineOnly { Image(systemName: "icloud").font(.caption).foregroundStyle(.secondary) }
                }
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
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty { Button("Move to Trash") { model.trash(Array(ids)) } }
            Button("New Folder") { model.newFolder() }
        } primaryAction: { ids in
            let cmd = NSEvent.modifierFlags.contains(.command)
            for e in rows where ids.contains(e.path) { model.open(e, newTab: cmd) }
        }
        .onKeyPress(.space) { quickLook(); return .handled }
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

    private func quickLook() {
        guard let p = model.selection.first else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: p)) // placeholder until QLPreviewPanel is wired up
    }
}
