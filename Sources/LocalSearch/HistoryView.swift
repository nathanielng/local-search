import SwiftUI
import AppKit
import FinderCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    enum Section: String, CaseIterable, Identifiable {
        case timeline = "Timeline", folders = "Folders", files = "Files Opened", ops = "File Operations", commands = "Commands"
        var id: String { rawValue }
        var kind: HistoryKind? {
            switch self { case .timeline: nil; case .folders: .folder; case .files: .fileOpen; case .ops: .fileOp; case .commands: .command }
        }
    }
    @State private var section: Section = .timeline
    @State private var search = ""
    @State private var entries: [HistoryEntry] = []
    @State private var selection: Set<String> = []
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) { ForEach(Section.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().padding(8)
            HStack {
                TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                Button("Export CSV…") { export() }.disabled(entries.isEmpty)
                Button("Clear…") { confirmClear = true }.disabled(entries.isEmpty)
            }.padding([.horizontal, .bottom], 8)
            Divider()
            Table(entries, selection: $selection) {
                TableColumn("Time") { e in Text(local(e.at)).foregroundStyle(.secondary) }.width(min: 120, ideal: 140)
                TableColumn("Item") { e in Text(e.displayTitle).lineLimit(1).truncationMode(.middle) }
                TableColumn("Detail") { e in Text(e.detail).foregroundStyle(.secondary).lineLimit(1) }.width(min: 80, ideal: 140)
            }
            .contextMenu(forSelectionType: String.self) { ids in menu(for: ids) } primaryAction: { ids in
                let cmd = NSEvent.modifierFlags.contains(.command)
                for e in entries where ids.contains(e.id) { if let f = e.folder { model.openFolder(f, newTab: cmd) } }
            }
            .onDeleteCommand { delete(selection) }
        }
        .frame(minWidth: 640, minHeight: 360)
        .task(id: "\(section.rawValue)|\(search)|\(model.historyVersion)") { reload() }
        .confirmationDialog("Clear \(section.rawValue == "Timeline" ? "all history" : section.rawValue)?",
                            isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { try? model.store?.clear(section.kind); model.historyVersion += 1 }
        } message: { Text("This can't be undone.") }
    }

    @ViewBuilder private func menu(for ids: Set<String>) -> some View {
        let picked = entries.filter { ids.contains($0.id) }
        if let f = picked.first?.folder {
            Button("Open Folder") { model.openFolder(f, newTab: false) }
            Button("Open Folder in New Tab") { model.openFolder(f, newTab: true) }
        }
        if let e = picked.first, e.kind == .folder {
            Button("Delete All Visits to “\((e.title as NSString).lastPathComponent)”") {
                try? model.store?.deleteVisits(toFolder: e.title); model.historyVersion += 1
            }
        }
        if !picked.isEmpty { Button("Delete Entry") { delete(ids) } }
    }

    private func reload() {
        guard let s = model.store else { return }
        entries = (try? section.kind.map { try s.history($0, search: search) } ?? s.timeline(search: search)) ?? []
    }

    private func delete(_ ids: Set<String>) {
        for e in entries where ids.contains(e.id) { try? model.store?.delete(e) }
        selection = []; model.historyVersion += 1
    }

    private func local(_ iso: String) -> String {
        parseISO8601(iso)?.formatted(date: .abbreviated, time: .standard) ?? iso
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "local-search-\(section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FinderStore.csv(entries).write(to: url, atomically: true, encoding: .utf8)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var m = model
        Form {
            Picker("Keep history for", selection: $m.retentionDays) {
                Text("Forever").tag(0); Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365)
            }
            Text("History is stored locally in ~/Library/Application Support/LocalSearch/. Older entries are removed at launch.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 420)
    }
}
