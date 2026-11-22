import SwiftUI
import FinderCore

/// Right panel: Vertical Tabs and Recent Locations, each toggled on its own.
struct RightPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showVerticalTabs") private var showTabs = false
    @AppStorage("showRecent") private var showRecent = false
    var body: some View {
        VStack(spacing: 0) {
            if showTabs { VerticalTabsPane() }
            if showTabs && showRecent { Divider() }
            if showRecent { RecentPane() }
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
            Text("Tabs").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 6)
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
    @State private var items: [RecentFolder] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Locations").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 6)
            List {
                ForEach(RecentBand.order, id: \.self) { band in
                    let rows = items.filter { $0.band == band }
                    if !rows.isEmpty {
                        Section(band) {
                            ForEach(rows, id: \.path) { r in
                                HStack(spacing: 4) {
                                    Text(label(r.path)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Button { try? model.store?.hideRecent(r.path); reload() } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove from Recent Locations")
                                }
                                    .help(r.path).contentShape(Rectangle())
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 8))
                                    .onTapGesture { model.navigate(r.path, .recent) }
                                    .contextMenu {
                                        Button("Open in New Tab") { model.newTab(path: r.path) }
                                        Button("Remove from Recent") { try? model.store?.hideRecent(r.path); reload() }
                                    }
                            }
                        }
                    }
                }
            }.listStyle(.plain).environment(\.defaultMinListRowHeight, 21)
        }
        .onAppear(perform: reload)
        .onChange(of: model.current.path) { _, _ in reload() }
        .onChange(of: model.historyVersion) { _, _ in reload() }
    }
    private func label(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        if name.isEmpty { return path }
        guard items.filter({ ($0.path as NSString).lastPathComponent == name }).count > 1 else { return name }
        return "\(name) — \(((path as NSString).deletingLastPathComponent as NSString).lastPathComponent)"
    }
    private func reload() { items = (try? model.store?.recentFolders()) ?? [] }
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
