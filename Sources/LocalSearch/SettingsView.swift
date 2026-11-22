import SwiftUI
import AppKit
import FinderCore

/// ⌘, : a small General tab and a History tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            HistorySettings().tabItem { Label("History", systemImage: "clock") }
        }
        .frame(width: 480, height: 380)
    }
}

/// Display defaults. These are the same switches as the View menu, so the two always agree.
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("lsColors") private var lsColors = false
    @AppStorage("showKindBadges") private var showKindBadges = false
    @AppStorage("groupByDate") private var groupByDate = false

    var body: some View {
        @Bindable var m = model
        Form {
            Stepper(value: $m.textSize, in: 10...20, step: 1) { Text("Text size: \(Int(m.textSize)) pt") }
            Picker("Date column", selection: $m.dateMode) {
                ForEach(DateMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Show hidden files", isOn: Binding(get: { model.showHidden }, set: { if $0 != model.showHidden { model.toggleHidden() } }))
            Toggle("Colour file names by type (like ls)", isOn: $lsColors)
            Toggle("Show Kind badges above the list", isOn: Binding(get: { showKindBadges }, set: {
                showKindBadges = $0; if !$0 { model.clearKindFilter() }
            }))
            Toggle("Group by Date", isOn: $groupByDate)
            Text("Group by Date shows its headings when the list is sorted by a date column.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct HistorySettings: View {
    @Environment(AppModel.self) private var model
    @State private var picked: String?

    var body: some View {
        @Bindable var m = model
        Form {
            Section {
                Picker("Keep history for", selection: $m.retentionDays) {
                    Text("Forever").tag(0); Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365)
                }
                Text("History is stored locally in ~/Library/Application Support/LocalSearch/. Older entries are removed at launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ignored folders") {
                if model.ignoredFolders.isEmpty {
                    Text("None. Visits and opens in an ignored folder (and its subfolders) aren't recorded and don't appear in Recent Locations.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    List(model.ignoredFolders, id: \.self, selection: $picked) { p in
                        Text(p).lineLimit(1).truncationMode(.middle).help(p)
                    }.frame(height: 110)
                }
                HStack {
                    Button("Add Folder…") { model.promptAddIgnoredFolder() }
                    Button("Remove") { if let p = picked { model.removeIgnoredFolder(p); picked = nil } }.disabled(picked == nil)
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension AppModel {
    func promptAddIgnoredFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Ignore"; p.message = "Choose a folder to keep out of History and Recent Locations"
        guard p.runModal() == .OK, let u = p.url, let path = FinderStore.normalizedIgnored(u.path) else { return }
        guard !ignoredFolders.contains(path) else { return }
        let a = NSAlert()
        a.messageText = "Ignore “\((path as NSString).lastPathComponent)”?"
        a.informativeText = "Visits to this folder and its subfolders, and files opened in them, won't be recorded or shown in Recent Locations. Delete the history already recorded for it as well?"
        a.addButton(withTitle: "Ignore and Delete History")
        a.addButton(withTitle: "Ignore Only")
        a.addButton(withTitle: "Cancel")
        let r = a.runModal()
        guard r != .alertThirdButtonReturn else { return }
        store?.setIgnoredFolders(ignoredFolders + [path])
        if r == .alertFirstButtonReturn { _ = try? store?.deleteHistory(under: path) }
        ignoredFolders = store?.ignoredFolders() ?? ignoredFolders
        historyVersion += 1
    }

    func removeIgnoredFolder(_ path: String) {
        store?.setIgnoredFolders(ignoredFolders.filter { $0 != path })
        ignoredFolders = store?.ignoredFolders() ?? []
        historyVersion += 1
    }
}
