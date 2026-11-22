import SwiftUI
import FinderCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 112.0
    @AppStorage("showKindBadges") private var showKindBadges = false
    @AppStorage("showVerticalTabs") private var showVerticalTabs = false
    @AppStorage("showRecent") private var showRecent = false
    @AppStorage("showInfo") private var showInfo = false
    @AppStorage("showCommands") private var showCommands = false
    @AppStorage("rightPanelWidth") private var rightPanelWidth = 240.0

    var body: some View {
        content.overlay { if model.showQuickFind { QuickFindView() } }
    }

    private var content: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView().frame(width: min(max(sidebarWidth, 90), 320))
                SidebarDivider(width: $sidebarWidth)
            }
            VStack(spacing: 0) {
                TabBar()
                Divider()
                NavBar()
                Divider()
                if showKindBadges { KindBadgeBar(); Divider() }
                FileListView()
                if showCommands { Divider(); CommandPanel() }
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
            if showVerticalTabs || showRecent || showInfo {
                RightDivider(width: $rightPanelWidth)
                RightPanel().frame(width: min(max(rightPanelWidth, 160), 480))
            }
        }
    }
}

struct TabBar: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showSidebar") private var showSidebar = true
    @State private var contentHeight: CGFloat = 36
    static let rowHeight: CGFloat = 28
    static let maxRows: CGFloat = 3
    private var maxHeight: CGFloat { Self.rowHeight * Self.maxRows + 2 * (Self.maxRows - 1) + 8 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button { showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.plain).padding(.leading, 10).padding(.top, 10).help("Show or hide the sidebar (⌃⌘S)")
            // Tabs wrap onto up to three rows; beyond that the area scrolls.
            ScrollView(.vertical, showsIndicators: false) {
                TabFlowLayout {
                    ForEach(model.tabs) { tab in TabButton(tab: tab) }
                    // Dropping a tab here moves it to the very end.
                    Color.clear.frame(width: 24, height: Self.rowHeight).contentShape(Rectangle())
                        .onDrop(of: [.plainText], delegate: TabEndDropDelegate(model: model))
                }
                .padding(4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, maxHeight))
            Button { model.newTab() } label: { Image(systemName: "plus") }.buttonStyle(.plain).padding(.leading, 8).padding(.top, 10)
            Button { model.showQuickFind = true } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).padding(.horizontal, 10).padding(.top, 10).help("Quick Find (⌘F)")
        }
    }
}

/// Lays tabs out left to right and wraps onto the next row when the width runs out.
struct TabFlowLayout: Layout {
    var spacing: CGFloat = 2
    var rowSpacing: CGFloat = 2

    private func frames(width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        var out: [CGRect] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowH + rowSpacing; rowH = 0 }
            out.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return (out, y + rowH)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 800
        return CGSize(width: w, height: frames(width: w, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (s, f) in zip(subviews, frames(width: bounds.width, subviews).frames) {
            s.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
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
            Text(model.titleFor(tab)).lineLimit(1).frame(maxWidth: 170, alignment: .leading).fixedSize(horizontal: true, vertical: false)
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
    @AppStorage("showKindBadges") private var showKindBadges = false
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
            Button { showKindBadges.toggle(); if !showKindBadges { model.clearKindFilter() } } label: {
                Image(systemName: showKindBadges ? "tag.fill" : "tag")
            }.help("Show or hide Kind badges: filter this folder by type")
            Menu {
                Picker("Date column", selection: Binding(get: { model.dateMode }, set: { model.dateMode = $0 })) {
                    ForEach(DateMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.inline)
            } label: { Image(systemName: "calendar") }
                .menuIndicator(.hidden).fixedSize().help("Date column: Added or Modified, Modified, or Added")
            Button { model.toggleFavorite() } label: {
                Image(systemName: model.store?.isFavorite(model.current.path) == true ? "star.fill" : "star")
            }
        }
        .buttonStyle(.borderless).padding(6)
        .onChange(of: model.current.path, initial: true) { _, p in text = p }
        .onChange(of: model.showAddressField) { _, v in if v { focused = true; model.showAddressField = false } }
    }
}

/// One badge per kind in the folder ("Folder 12", "Markdown 4"); click to show only those kinds.
struct KindBadgeBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let counts = Dictionary(grouping: model.entries, by: \.kind).mapValues(\.count)
        let kinds = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let active = model.kindFilterActive
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if active {
                    Button { model.clearKindFilter() } label: { Label("Show all", systemImage: "xmark.circle.fill").font(.caption) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                ForEach(kinds, id: \.key) { kind, n in
                    let on = active && model.kindFilter.contains(kind)
                    Button { model.toggleKind(kind) } label: {
                        Text("\(kind) \(n)").font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(on ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15), in: Capsule())
                            .overlay { if on { Capsule().stroke(Color.accentColor) } }
                    }.buttonStyle(.plain)
                }
                if kinds.isEmpty { Text("No files").font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal, 8).padding(.vertical, 5)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) var model
    @AppStorage("collapsed") var collapsedRaw = ""
    @Environment(\.openWindow) var openWindow

    var collapsedSet: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    private var collapsed: Set<String> { collapsedSet }

    var body: some View {
        let _ = model.sidebarVersion
        let s = model.store
        let home = AppPaths.home
        List {
            section("Special Folders", reorder: "special", rows: ((try? s?.specialFolders()) ?? []).map { SidebarRow(title: $0.title, path: $0.path, symbol: "bolt.fill") }, source: .special)
            section("Projects", reorder: "projects", rows: model.projects.map { SidebarRow(title: $0.title, path: $0.path, symbol: "briefcase") }, source: .project)
            section("Favorites", reorder: "favorites", rows: ((try? s?.favorites()) ?? []).map { SidebarRow(title: $0.title, path: $0.path, symbol: "star") }, source: .favorite)
            if !model.cloudFolders.isEmpty {
                let running = model.oneDriveRunning
                section("Cloud", rows: model.cloudFolders.map { SidebarRow(title: $0.title, path: $0.path, symbol: "cloud", running: running, manual: $0.manual) }, source: .sidebar)
            }
            if !model.webLocations.isEmpty { webSection }
            section("Locations", rows: model.locationRows(), source: .sidebar)
            section("Config", rows: [".kiro", ".claude", ".aws", ".ssh"].map { SidebarRow(title: $0, path: "\(home)/\($0)", symbol: "gearshape") }, source: .sidebar)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func section(_ title: String, reorder: String? = nil, rows: [SidebarRow], source: NavSource) -> some View {
        let isOpen = !collapsed.contains(title)
        Section(isExpanded: Binding(get: { isOpen }, set: { open in
            var c = collapsed; if open { c.remove(title) } else { c.insert(title) }
            collapsedRaw = c.sorted().joined(separator: ",")
        })) {
            ForEach(rows.prefix(FinderStore.sidebarLimit)) { row in
                // Never probe mounted volumes here: a stalled network share would freeze the sidebar.
                let missing = (row.needsConnect || row.ejectable) ? false : !FileManager.default.fileExists(atPath: row.path)
                Button { model.openRow(row, source: source) } label: {
                    // The whole row (no gaps) is clickable and a drop target.
                    HStack {
                        Label(row.title, systemImage: row.symbol)
                        if row.running { Circle().fill(.green).frame(width: 6, height: 6).help("The OneDrive app is running") }
                        if model.connecting == row.title { ProgressView().controlSize(.small) }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).opacity(missing || row.needsConnect ? 0.45 : 1)
                .help(row.needsConnect ? "Click to connect" : row.path)
                .reorderDragSource(section: reorder, path: row.path)
                .modifier(OptionalFolderDrop(enabled: !row.needsConnect, model: model, path: row.path,
                                             mode: title == "Favorites" ? .shortcutOrMove : .moveInto, section: reorder))
                .listRowInsets(EdgeInsets())
                .contextMenu {
                    if row.needsConnect, let loc = row.network { Button("Connect") { model.connect(loc) } }
                    else {
                        Button("Open in New Tab") { model.newTab(path: row.path) }
                        if title == "Favorites" { Button("Remove from Favorites") { model.removeFavorite(row.path) } }
                        if title == "Special Folders" { Button("Remove from Special Folders") { model.removeSpecialFolder(row.path) } }
                        if title == "Projects" { Button("Remove from Projects") { model.removeProject(row.path) } }
                        if title == "Cloud" && row.manual { Button("Remove from Cloud") { model.removeCloudFolder(row.path) } }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.path)]) }
                    }
                    if let loc = row.network { Divider(); Button("Remove from Locations") { model.removeNetworkLocation(loc.title) } }
                    if row.ejectable { Divider(); Button(row.network == nil ? "Eject" : "Disconnect") { model.eject(row.path, title: row.title) } }
                }
            }
        } header: {
            if title == "Favorites" {
                // Dropping a folder on the header adds it as a shortcut.
                Text(title).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .folderDropTarget(model, path: "", mode: .addShortcut)
            } else if title == "Projects" {
                Text(title).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .folderDropTarget(model, path: "", mode: .addProject)
            } else { Text(title) }
        }
    }
}

extension SidebarView {
    /// Web Locations: https pages that open in the browser. The first ten show; the rest are in the search window.
    @ViewBuilder var webSection: some View {
        let isOpen = !collapsedSet.contains("Web Locations")
        Section(isExpanded: Binding(get: { isOpen }, set: { open in
            var c = collapsedSet; if open { c.remove("Web Locations") } else { c.insert("Web Locations") }
            collapsedRaw = c.sorted().joined(separator: ",")
        })) {
            ForEach(model.webLocations.prefix(WebLocations.sidebarCount)) { w in
                Button { model.openWebLocation(w) } label: {
                    HStack {
                        Label(w.title, systemImage: w.symbol)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(w.notes.isEmpty ? w.url : "\(w.notes)\n\(w.url)")
                .listRowInsets(EdgeInsets())
                .contextMenu {
                    Button("Open in Browser") { model.openWebLocation(w) }
                    Button("Copy Address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(w.url, forType: .string) }
                    Divider()
                    Button("Remove from Web Locations") { model.removeWebLocation(w) }
                }
            }
            if model.webLocations.count > WebLocations.sidebarCount {
                Button { openWindow(id: "web-locations") } label: {
                    Label("All \(model.webLocations.count) Web Locations…", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5).padding(.horizontal, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).listRowInsets(EdgeInsets())
            }
        } header: {
            HStack {
                Text("Web Locations")
                Spacer()
                Button { openWindow(id: "web-locations") } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).help("Search Web Locations (⇧⌘L)")
            }
        }
    }
}

/// Rows that aren't mounted yet can't take drops.
struct OptionalFolderDrop: ViewModifier {
    let enabled: Bool
    let model: AppModel
    let path: String
    let mode: FolderDropDelegate.Mode
    let section: String?
    func body(content: Content) -> some View {
        if enabled { content.folderDropTarget(model, path: path, mode: mode, section: section) } else { content }
    }
}

extension FileColor {
    var swiftUI: Color? {
        switch self {
        case .directory: .blue
        case .symlink: .cyan
        case .archive: .red
        case .image, .video: .purple
        case .audio: .teal
        case .executable: .green
        case .plain: nil
        }
    }
}

struct FileListView: View {
    @AppStorage("lsColors") private var lsColors = false
    @Environment(AppModel.self) private var model
    @AppStorage("groupByDate") private var groupByDate = false

    /// With Group by Date on and the list sorted by date, a header row precedes each period.
    private var listRows: [FileEntry] {
        let items = model.sortedEntries
        guard groupByDate, model.current.sortKey == "date" else { return items }
        var out: [FileEntry] = [], last = ""
        for e in items {
            let g = DateGroup.label(for: e.date(model.dateMode))
            if g != last { out.append(.header(g)); last = g }
            out.append(e)
        }
        return out
    }

    private func nameColor(_ e: FileEntry) -> Color {
        guard lsColors, let c = e.color.swiftUI else { return .primary }
        return c
    }

    var body: some View {
        @Bindable var m = model
        let rows = listRows
        Table(rows, selection: Binding(get: { model.selection }, set: { model.setSelection($0) }), sortOrder: sortOrder) {
            TableColumn("Name", value: \.name) { e in
                if e.isHeader {
                    Text(e.name).font(.system(size: model.textSize, weight: .semibold)).foregroundStyle(.secondary)
                } else {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: e.path)).resizable().frame(width: 16, height: 16)
                    if model.renamingPath == e.path {
                        RenameField(initial: e.name, isDirectory: e.isDirectory,
                                    onCommit: { model.commitRename(e.path, to: $0) }, onCancel: { model.renamingPath = nil })
                    } else { Text(e.name).lineLimit(1).foregroundStyle(nameColor(e)) }
                    Spacer(minLength: 0)
                    if e.isOnlineOnly { Image(systemName: "icloud").font(.caption).foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
                .modifier(FolderRowDrop(model: model, entry: e))
                }
            }
            TableColumn(model.dateMode.title, value: \.addedOrModified) { e in
                if !e.isHeader { Text(e.date(model.dateMode).formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
            }.width(min: 120, ideal: 150)
            TableColumn("Size", value: \.sizeKey) { e in
                if !e.isHeader { Text(e.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)).foregroundStyle(.secondary) }
            }.width(min: 60, ideal: 80)
            TableColumn("Kind", value: \.kind) { e in if !e.isHeader { Text(e.kind).foregroundStyle(.secondary).lineLimit(1) } }.width(min: 80, ideal: 120)
        }
        .font(.system(size: model.textSize))
        .id(lsColors)
        .background(AppKitDragFix(paths: rows.map { $0.isHeader ? "" : $0.path }))
        .onDrop(of: [.fileURL], delegate: FolderDropDelegate(model: model, path: model.current.path, mode: .copyIntoCurrent) { _, _ in })
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                if ids.count == 1 { Button("Rename") { model.renamingPath = ids.first } }
                if ids.count == 1, let e = rows.first(where: { ids.contains($0.path) }), e.isDirectory {
                    Button("Add to Favorites") { try? model.store?.addFavorite(path: e.path); model.sidebarVersion += 1 }
                    Button("Add to Special Folders") { model.addSpecialFolder(e.path) }
                    Button("Add to Projects") { model.addProject(e.path) }
                }
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
            for e in rows where ids.contains(e.path) && !e.isHeader { model.open(e, newTab: cmd) }
        }
        .onKeyPress(.space) { model.quickLook(); return .handled }
        .onKeyPress(.return) {
            guard model.renamingPath == nil, model.selection.count == 1 else { return .ignored }
            model.beginRename(); return .handled
        }
        .overlay(alignment: .topTrailing) { sortMenu }
    }

    /// Clicking a column header sorts by it; clicking again reverses. The model owns the (per-tab, saved) order.
    private var sortOrder: Binding<[KeyPathComparator<FileEntry>]> {
        Binding(get: {
            let order: SortOrder = model.current.sortAscending ? .forward : .reverse
            switch model.current.sortKey {
            case "name": return [KeyPathComparator(\.name, order: order)]
            case "date": return [KeyPathComparator(\.addedOrModified, order: order)]
            case "size": return [KeyPathComparator(\.sizeKey, order: order)]
            case "kind": return [KeyPathComparator(\.kind, order: order)]
            default: return []
            }
        }, set: { new in
            guard let c = new.first else { model.clearSort(); return }
            let key: String
            switch c.keyPath {
            case \FileEntry.name: key = "name"
            case \FileEntry.addedOrModified: key = "date"
            case \FileEntry.sizeKey: key = "size"
            case \FileEntry.kind: key = "kind"
            default: return
            }
            model.setSort(key: key, ascending: c.order == .forward)
        })
    }

    private var sortMenu: some View {
        Button { model.clearSort() } label: { Image(systemName: "arrow.up.arrow.down") }
            .buttonStyle(.plain).padding(8)
            .disabled(model.current.sortKey == "none")
            .help("Remove sorting (show files in the folder's own order)")
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

/// Drag to resize the sidebar. The width is stored in UserDefaults by the @AppStorage binding.
struct SidebarDivider: View {
    @Binding var width: Double
    @State private var start: Double?
    var body: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            if start == nil { start = width }
                            width = min(max((start ?? width) + v.translation.width, 90), 320)
                        }
                        .onEnded { _ in start = nil })
            }
    }
}
