import SwiftUI
import FinderCore

@main
struct LocalSearchApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Local Search") {
            ContentView().environment(model)
                .frame(minWidth: 800, minHeight: 480)
        }
        .commands { AppCommands(model: model) }
        Window("History", id: "history") { HistoryView().environment(model) }
        Settings { SettingsView().environment(model) }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("groupByDate") private var groupByDate = false
    @AppStorage("showKindBadges") private var showKindBadges = false
    @Environment(\.openWindow) private var openWindow
    private var editingText: Bool { NSApp.keyWindow?.firstResponder is NSText }
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { model.newTab() }.keyboardShortcut("t")
            Button("Close Tab") { model.closeTab() }.keyboardShortcut("w")
            Button("Reopen Closed Tab") { model.reopenTab() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("New Folder") { model.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Text File") { model.newTextFile() }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Rename") { model.beginRename() }
            Button("Move to Trash") { model.trashSelection() }.keyboardShortcut(.delete, modifiers: .command)
            Button("Show in Finder") { model.showInFinder() }.keyboardShortcut("r", modifiers: [.command, .option])
        }
        // Undo reverses file operations unless a text field is being edited.
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoLabel.map { "Undo \($0)" } ?? "Undo") {
                if editingText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { model.undo() }
            }.keyboardShortcut("z").disabled(model.undoLabel == nil && !editingText)
            Button(model.redoLabel.map { "Redo \($0)" } ?? "Redo") {
                if editingText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) } else { model.redo() }
            }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(model.redoLabel == nil && !editingText)
        }
        // Copy/Paste act on files unless a text field is being edited.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
            Button("Copy") { if editingText { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) } else { model.copyFiles() } }.keyboardShortcut("c")
            Button("Paste") { if editingText { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) } else { model.pasteFiles() } }.keyboardShortcut("v")
            Button("Move Item Here") { model.moveFilesHere() }.keyboardShortcut("v", modifiers: [.command, .option])
            Button("Select All") { NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a")
            Divider()
            Button("Copy Paths") { model.copyPaths() }.keyboardShortcut("c", modifiers: [.command, .option])
            Button("Copy File Text for AI") { model.copyFileText() }.keyboardShortcut("c", modifiers: [.command, .option, .shift])
        }
        CommandMenu("Go") {
            Menu("Add SSH Location") {
                let have = Set(model.networkLocations.compactMap { $0.kind == .ssh ? $0.host : nil })
                let hosts = SSHConfig.hosts().filter { !have.contains($0) }
                if hosts.isEmpty { Text("No more hosts in ~/.ssh/config") }
                ForEach(hosts, id: \.self) { h in Button(h) { model.addSSHLocation(h) } }
            }
            Button("Quick Find…") { model.showQuickFind = true }.keyboardShortcut("f")
            Divider()
            Button("Back") { model.goBack() }.keyboardShortcut("[")
            Button("Forward") { model.goForward() }.keyboardShortcut("]")
            Button("Enclosing Folder") { model.goUp() }.keyboardShortcut(.upArrow)
            Button("Go to Folder…") { model.showAddressField = true }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        CommandMenu("History") {
            Button("Show History") { openWindow(id: "history") }.keyboardShortcut("y")
        }
        CommandMenu("View") {
            Button(showSidebar ? "Hide Sidebar" : "Show Sidebar") { showSidebar.toggle() }.keyboardShortcut("s", modifiers: [.command, .control])
            Button(groupByDate ? "Ungroup by Date" : "Group by Date") {
                groupByDate.toggle()
                // Headers only show when sorted by a date, newest first, so switch to that when turning grouping on.
                if groupByDate {
                    if model.current.sortKey != "date" { model.setSort(key: "date") }
                    if model.current.sortAscending { model.setSort(key: "date") }
                }
            }.keyboardShortcut("g", modifiers: [.command, .control])
            Button(showKindBadges ? "Hide Kind Badges" : "Show Kind Badges") {
                showKindBadges.toggle(); if !showKindBadges { model.clearKindFilter() }
            }.keyboardShortcut("b", modifiers: [.command, .control])
            Button("Show Hidden Files") { model.toggleHidden() }.keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Bigger Text") { model.textSize = min(20, model.textSize + 1) }.keyboardShortcut("+")
            Button("Smaller Text") { model.textSize = max(10, model.textSize - 1) }.keyboardShortcut("-")
            Button("Actual Text Size") { model.textSize = 13 }.keyboardShortcut("0")
            Button("Toggle Favorite") { model.toggleFavorite() }.keyboardShortcut("t", modifiers: [.command, .control])
        }
    }
}
