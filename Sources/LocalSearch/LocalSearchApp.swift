import SwiftUI
import FinderCore

@main
struct LocalSearchApp: App {
    @State private var model = AppModel()

    init() { NSWindow.allowsAutomaticWindowTabbing = false }   // the app has its own tabs

    var body: some Scene {
        WindowGroup("Local Search") {
            ContentView().environment(model)
                .frame(minWidth: 800, minHeight: 480)
        }
        .commands { AppCommands(model: model) }
        Window("History", id: "history") { HistoryView().environment(model) }
        Window("Web Locations", id: "web-locations") { WebLocationsView().environment(model) }
        Window("Keyboard Shortcuts", id: "shortcuts") { ShortcutsView() }
            .defaultSize(width: 560, height: 640)
        Settings { SettingsView().environment(model) }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("groupByDate") private var groupByDate = false
    @AppStorage("showKindBadges") private var showKindBadges = false
    @AppStorage("lsColors") private var lsColors = false
    @AppStorage("showVerticalTabs") private var showVerticalTabs = false
    @AppStorage("showRecent") private var showRecent = false
    @AppStorage("showInfo") private var showInfo = false
    @AppStorage("showCommands") private var showCommands = false
    @AppStorage("showRightPanel") private var showRightPanel = true
    @AppStorage("showPermissions") private var showPermissions = false
    @Environment(\.openWindow) private var openWindow
    private var editingText: Bool { NSApp.keyWindow?.firstResponder is NSText }
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { model.newTab() }.shortcut("newTab")
            Button("Close Tab") { model.closeTab() }.shortcut("closeTab")
            Button("Reopen Closed Tab") { model.reopenTab() }.shortcut("reopenTab")
            Button("Next Tab") { model.selectAdjacentTab(1) }.shortcut("nextTab")
            Button("Previous Tab") { model.selectAdjacentTab(-1) }.shortcut("prevTab")
            Divider()
            Button("New Folder") { model.newFolder() }.shortcut("newFolder")
            Button("New Text File") { model.newTextFile() }.shortcut("newTextFile")
            Button("Rename") { model.beginRename() }
            Button("Move to Trash") { model.trashSelection() }.shortcut("trash")
            Button("Show in Finder") { model.showInFinder() }.shortcut("showInFinder")
            Button("Toggle Favorite") { model.toggleFavorite() }.shortcut("favorite")
        }
        // Undo reverses file operations unless a text field is being edited.
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoLabel.map { "Undo \($0)" } ?? "Undo") {
                if editingText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { model.undo() }
            }.shortcut("undo").disabled(model.undoLabel == nil && !editingText)
            Button(model.redoLabel.map { "Redo \($0)" } ?? "Redo") {
                if editingText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) } else { model.redo() }
            }.shortcut("redo").disabled(model.redoLabel == nil && !editingText)
        }
        // Copy/Paste act on files unless a text field is being edited.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
            Button("Copy") { if editingText { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) } else { model.copyFiles() } }.shortcut("copy")
            Button("Paste") { if editingText { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) } else { model.pasteFiles() } }.shortcut("paste")
            Button("Move Item Here") { model.moveFilesHere() }.shortcut("moveHere")
            Button("Select All") { NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil) }.shortcut("selectAll")
            Divider()
            Button("Copy Paths") { model.copyPaths() }.shortcut("copyPaths")
            Button("Copy File Text for AI") { model.copyFileText() }.shortcut("copyText")
        }
        CommandMenu("Go") {
            Menu("Add SSH Location") {
                let have = Set(model.networkLocations.compactMap { $0.kind == .ssh ? $0.host : nil })
                let hosts = SSHConfig.hosts().filter { !have.contains($0) }
                if hosts.isEmpty { Text("No more hosts in ~/.ssh/config") }
                ForEach(hosts, id: \.self) { h in Button(h) { model.addSSHLocation(h) } }
            }
            Button("Web Locations…") { openWindow(id: "web-locations") }.shortcut("webLocations")
            Button("Add Web Location…") { model.promptAddWebLocation() }
            Button("Add OneDrive Folder…") { model.promptAddOneDriveFolder() }
            Divider()
            Button("Quick Find…") { model.showQuickFind = true }.shortcut("quickFind")
            Divider()
            Button("Back") { model.goBack() }.shortcut("back")
            Button("Forward") { model.goForward() }.shortcut("forward")
            Button("Enclosing Folder") { model.goUp() }.shortcut("up")
            Button("Go to Folder…") { model.showAddressField = true }.shortcut("goToFolder")
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }.shortcut("shortcuts")
        }
        CommandMenu("History") {
            Button("Show History") { openWindow(id: "history") }.shortcut("history")
        }
        // Part of the system View menu, so there is only one.
        CommandGroup(after: .toolbar) {
            Button(showSidebar ? "Hide Sidebar" : "Show Sidebar") { showSidebar.toggle() }.shortcut("sidebar")
            Button(groupByDate ? "Ungroup by Date" : "Group by Date") {
                groupByDate.toggle()
                // Headers only show when sorted by a date, newest first, so switch to that when turning grouping on.
                if groupByDate {
                    if model.current.sortKey != "date" { model.setSort(key: "date") }
                    if model.current.sortAscending { model.setSort(key: "date") }
                }
            }.shortcut("group")
            Picker("Date Column", selection: Binding(get: { model.dateMode }, set: { model.dateMode = $0 })) {
                ForEach(DateMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button(showRightPanel && (showVerticalTabs || showRecent || showInfo) ? "Hide Right Panel" : "Show Right Panel") { RightPanelState.toggle() }.shortcut("rightPanel")
            Button(showVerticalTabs ? "Hide Vertical Tabs" : "Show Vertical Tabs") { showVerticalTabs.toggle(); if showVerticalTabs { showRightPanel = true } }.shortcut("verticalTabs")
            Button(showRecent ? "Hide Recent Locations" : "Show Recent Locations") { showRecent.toggle(); if showRecent { showRightPanel = true } }.shortcut("recent")
            Button(showCommands ? "Hide Command Panel" : "Show Command Panel") { showCommands.toggle() }.shortcut("commands")
            Button(showInfo ? "Hide Info & Preview" : "Show Info & Preview") { showInfo.toggle(); if showInfo { showRightPanel = true } }.shortcut("info")
            Button(lsColors ? "Hide File Colours" : "Show File Colours") { lsColors.toggle() }.shortcut("colours")
            Button(showKindBadges ? "Hide Kind Badges" : "Show Kind Badges") {
                showKindBadges.toggle(); if !showKindBadges { model.clearKindFilter() }
            }.shortcut("badges")
            Button(model.showHidden ? "Hide Hidden Files" : "Show Hidden Files") { model.toggleHidden() }.shortcut("hidden")
            Button(showPermissions ? "Hide Permissions Column" : "Show Permissions Column") { showPermissions.toggle() }.shortcut("permissions")
            Button("Bigger Text") { model.textSize = min(20, model.textSize + 1) }.shortcut("bigger")
            Button("Smaller Text") { model.textSize = max(10, model.textSize - 1) }.shortcut("smaller")
            Button("Actual Text Size") { model.textSize = 13 }.shortcut("actualSize")
        }
    }
}


extension ShortcutDef {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case "up": .upArrow
        case "down": .downArrow
        case "return": .return
        case "delete": .delete
        case "space": .space
        case "escape": .escape
        case "tab": .tab
        case "left": .leftArrow
        case "right": .rightArrow
        default: KeyEquivalent(Character(key))
        }
    }
    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        for x in mods { switch x { case .command: m.insert(.command); case .shift: m.insert(.shift); case .option: m.insert(.option); case .control: m.insert(.control) } }
        return m
    }
}

extension View {
    /// Attach a shortcut from the catalog, so menus and the shortcuts window can't disagree.
    @ViewBuilder func shortcut(_ id: String) -> some View {
        let s = ShortcutStore.shared.def(id)
        if s.isOff { self } else { keyboardShortcut(s.keyEquivalent, modifiers: s.eventModifiers) }
    }
}
