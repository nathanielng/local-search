import SwiftUI
import FinderCore

/// Right panel: Vertical Tabs, Recent Locations and Info & Preview, each toggled on its own.
/// Recent Locations flexes; Tabs sits on top and Info & Preview at the bottom, each with a draggable height.
struct RightPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showVerticalTabs") private var showTabs = false
    @AppStorage("showRecent") private var showRecent = false
    @AppStorage("showInfo") private var showInfo = false
    @AppStorage("tabsPaneHeight") private var tabsHeight = 220.0
    @AppStorage("infoPaneHeight") private var infoHeight = 320.0
    var body: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let tabsFixed = showTabs && (showRecent || showInfo)
            let infoFixed = showInfo && showRecent
            let tabsMax = max(total - 120 - (infoFixed ? min(max(infoHeight, 120), total - 200) : 0), 80)
            let infoMax = max(total - 120 - (tabsFixed ? min(max(tabsHeight, 80), tabsMax) : 0), 120)
            VStack(spacing: 0) {
                if showTabs {
                    if tabsFixed { VerticalTabsPane().frame(height: min(max(tabsHeight, 80), tabsMax)) } else { VerticalTabsPane() }
                }
                if showTabs && (showRecent || showInfo) { PaneDivider(height: $tabsHeight, maxHeight: tabsMax) }
                if showRecent { RecentPane() }
                if showRecent && showInfo { PaneDivider(height: $infoHeight, maxHeight: infoMax, inverted: true) }
                if showInfo {
                    if infoFixed { InfoPreviewPane().frame(height: min(max(infoHeight, 120), infoMax)) } else { InfoPreviewPane() }
                }
            }
        }
    }
}

/// Horizontal splitter between two panes; drag it up or down.
struct PaneDivider: View {
    @Binding var height: Double
    let maxHeight: Double
    var inverted = false
    var minHeight: Double? = nil
    @State private var start: Double?
    var body: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            .overlay {
                Color.clear.frame(height: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            if start == nil { start = height }
                            let dy = inverted ? -v.translation.height : v.translation.height
                            height = min(max((start ?? height) + dy, minHeight ?? (inverted ? 120 : 80)), maxHeight)
                        }
                        .onEnded { _ in start = nil })
            }
    }
}

struct VerticalTabsPane: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    private var tabs: [TabState] {
        filter.isEmpty ? model.tabs : model.tabs.filter {
            model.titleFor($0).localizedCaseInsensitiveContains(filter) || $0.path.localizedCaseInsensitiveContains(filter)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PaneHeader(title: "Tabs", key: "showVerticalTabs")
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).controlSize(.small).padding(.horizontal, 8)
            List {
                ForEach(tabs) { t in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(model.titleFor(t)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button { model.closeTab(t.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .listRowBackground(t.id == model.selectedTabID ? Color.accentColor.opacity(0.25) : Color.clear)
                    .onTapGesture { model.selectTab(t.id) }
                    .help(t.path)
                }
            }.listStyle(.plain)
        }
    }
}

struct RecentPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage("recentMode") private var mode = "folders"
    @State private var items: [RecentFolder] = []
    private var isFiles: Bool { mode == "files" }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PaneHeader(title: "Recent Locations", key: "showRecent")
            Picker("", selection: $mode) { Text("Folders").tag("folders"); Text("Files Opened").tag("files") }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).padding(.horizontal, 8)
            List {
                ForEach(RecentBand.order, id: \.self) { band in
                    let rows = items.filter { $0.band == band }
                    if !rows.isEmpty {
                        Section(band) {
                            ForEach(rows, id: \.path) { r in row(r) }
                        }
                    }
                }
            }.listStyle(.plain).environment(\.defaultMinListRowHeight, 21)
        }
        .onAppear(perform: reload)
        .onChange(of: mode) { _, _ in reload() }
        .onChange(of: model.current.path) { _, _ in reload() }
        .onChange(of: model.historyVersion) { _, _ in reload() }
    }

    @ViewBuilder private func row(_ r: RecentFolder) -> some View {
        let line = HStack(spacing: 4) {
            Text(label(r.path)).font(.callout).lineLimit(1)
            Spacer(minLength: 0)
            Button { remove(r.path) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove from Recent Locations")
        }
        .help(r.path).contentShape(Rectangle())
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 8))
        .onTapGesture { isFiles ? model.openFile(r.path) : model.navigate(r.path, .recent) }
        .contextMenu {
            if isFiles {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) }
                Button("Open Containing Folder") { model.navigate((r.path as NSString).deletingLastPathComponent, .recent) }
            } else {
                Button("Open in New Tab") { model.newTab(path: r.path) }
            }
            Button("Remove from Recent") { remove(r.path) }
        }
        // Files dropped on a folder row are moved into it (hold ⌥ to copy).
        if isFiles { line } else { line.folderDropTarget(model, path: r.path) }
    }

    private func remove(_ path: String) {
        if isFiles { try? model.store?.deleteOpens(of: path) } else { try? model.store?.hideRecent(path) }
        reload()
    }
    private func label(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        if name.isEmpty { return path }
        guard items.filter({ ($0.path as NSString).lastPathComponent == name }).count > 1 else { return name }
        return "\(name) — \(((path as NSString).deletingLastPathComponent as NSString).lastPathComponent)"
    }
    private func reload() {
        items = ((isFiles ? try? model.store?.recentFiles() : try? model.store?.recentFolders()) ?? nil) ?? []
    }
}

/// Draggable divider for the right panel (drags the opposite way to the sidebar's).
struct RightDivider: View {
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
                            width = min(max((start ?? width) - v.translation.width, 160), 480)
                        }
                        .onEnded { _ in start = nil })
            }
    }
}


/// Title row of a right-panel pane with a close button. Closing only turns that pane off (View menu turns it back on).
struct PaneHeader: View {
    let title: String
    let key: String
    var body: some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { UserDefaults.standard.set(false, forKey: key) } label: { Image(systemName: "xmark").font(.caption2) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Close \(title)")
        }
        .padding(.horizontal, 8).padding(.top, 6)
    }
}
