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
    }
}

struct AppCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { model.newTab() }.keyboardShortcut("t")
            Button("Close Tab") { model.closeTab() }.keyboardShortcut("w")
            Button("Reopen Closed Tab") { model.reopenTab() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("New Folder") { model.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            Button("Back") { model.goBack() }.keyboardShortcut("[")
            Button("Forward") { model.goForward() }.keyboardShortcut("]")
            Button("Enclosing Folder") { model.goUp() }.keyboardShortcut(.upArrow)
            Button("Go to Folder…") { model.showAddressField = true }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        CommandMenu("View") {
            Button("Show Hidden Files") { model.toggleHidden() }.keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Bigger Text") { model.textSize = min(20, model.textSize + 1) }.keyboardShortcut("+")
            Button("Smaller Text") { model.textSize = max(10, model.textSize - 1) }.keyboardShortcut("-")
            Button("Actual Text Size") { model.textSize = 13 }.keyboardShortcut("0")
            Button("Toggle Favorite") { model.toggleFavorite() }.keyboardShortcut("t", modifiers: [.command, .control])
        }
    }
}
