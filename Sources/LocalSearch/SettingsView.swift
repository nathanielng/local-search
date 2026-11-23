import SwiftUI
import AppKit
import FinderCore

/// ⌘, : a small General tab and a History tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            HistorySettings().tabItem { Label("History", systemImage: "clock") }
            PreviewSettings().tabItem { Label("Previews", systemImage: "eye") }
            NetworkSettings().tabItem { Label("Network", systemImage: "network") }
            LocationsSettings().tabItem { Label("Locations", systemImage: "folder.badge.gearshape") }
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 560, height: 520)
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

/// Projects, Web Locations and OneDrive folders, managed here instead of by editing settings.json.
struct LocationsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var project: String?
    @State private var web: String?
    @State private var cloud: String?
    @State private var filter = ""

    private var webShown: [WebLocation] { WebLocations.search(model.webLocations, filter) }

    var body: some View {
        Form {
            Section("Projects") {
                List(model.projects, id: \.path, selection: $project) { p in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.title)
                        Text(p.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }.frame(height: 90)
                HStack {
                    Button("Add Folder…") { model.promptAddProject() }
                    Button("Remove") { if let p = project { model.removeProject(p); project = nil } }.disabled(project == nil)
                    Button { if let p = project { model.moveProject(p, up: true) } } label: { Image(systemName: "chevron.up") }.disabled(project == nil)
                    Button { if let p = project { model.moveProject(p, up: false) } } label: { Image(systemName: "chevron.down") }.disabled(project == nil)
                }
            }
            Section("Web Locations (https only)") {
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
                List(webShown, id: \.url, selection: $web) { w in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(w.title)
                        Text(w.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }.frame(height: 90)
                HStack {
                    Button("Add…") { model.promptAddWebLocation() }
                    Button("Remove") { if let w = model.webLocations.first(where: { $0.url == web }) { model.removeWebLocation(w); web = nil } }.disabled(web == nil)
                    Text("\(model.webLocations.count) in total").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("OneDrive") {
                List(model.cloudFolders, id: \.path, selection: $cloud) { c in
                    HStack {
                        Text(c.title)
                        Spacer()
                        Text(c.manual ? "added by hand" : "found automatically").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(height: 60)
                HStack {
                    Button("Add Folder…") { model.promptAddOneDriveFolder() }
                    Button("Remove") { if let c = cloud { model.removeCloudFolder(c); cloud = nil } }
                        .disabled(!(model.cloudFolders.first { $0.path == cloud }?.manual ?? false))
                }
            }
            Section {
                HStack {
                    Button("Show settings.json in Finder") { model.revealSettingsFile() }
                    Button("Reload Now") { model.reloadNetworkLocations() }
                }
                Text("Changes made to settings.json by hand are picked up automatically. These lists are stored only on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Limits for the Info & Preview pane.
struct PreviewSettings: View {
    @AppStorage("previewWithholdSecrets") private var withhold = true
    @AppStorage("previewTextKB") private var textKB = Preview.defaultTextKB
    @AppStorage("previewBigMB") private var bigMB = Preview.defaultBigMB

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Hold back files that look like they contain secrets", isOn: $withhold)
                Text("Files such as .env, key files and anything with a password or key in it show a “Show Anyway” button instead of their contents. Turn this off only if you trust everything you browse.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Size limits") {
                Picker("Show the first", selection: $textKB) {
                    ForEach([16, 64, 256, 1024], id: \.self) { Text($0 >= 1024 ? "1 MB" : "\($0) KB").tag($0) }
                }
                Picker("Ask before opening files over", selection: $bigMB) {
                    ForEach([1, 5, 20, 100], id: \.self) { Text("\($0) MB").tag($0) }
                }
                Text("Longer text is cut with a note. Files over the second limit show a “Show Preview” button first. Changes apply to the next file you select.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Defaults") { withhold = true; textKB = Preview.defaultTextKB; bigMB = Preview.defaultBigMB }
            }
        }
        .formStyle(.grouped)
    }
}

/// How long to wait for a network location before giving up.
struct NetworkSettings: View {
    @AppStorage("smbTimeoutSeconds") private var smb = NetworkMounter.defaultSMBSeconds
    @AppStorage("sshTimeoutSeconds") private var ssh = NetworkMounter.defaultSSHSeconds

    var body: some View {
        Form {
            Section("Connection timeouts") {
                Picker("File server (SMB)", selection: $smb) {
                    ForEach([10, 15, 30, 60], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Picker("SSH location", selection: $ssh) {
                    ForEach([15, 25, 45, 90], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Text("How long to wait when you open a network location in the sidebar before showing an error. Raise these for a server that is slow to wake.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Defaults") { smb = NetworkMounter.defaultSMBSeconds; ssh = NetworkMounter.defaultSSHSeconds }
            }
        }
        .formStyle(.grouped)
    }
}
