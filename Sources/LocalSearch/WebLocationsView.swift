import SwiftUI
import FinderCore

/// All Web Locations in a searchable window (⇧⌘L). Every word typed must match the title, address or notes.
struct WebLocationsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @FocusState private var focused: Bool
    private var shown: [WebLocation] { WebLocations.search(model.webLocations, query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search title, address and notes", text: $query).textFieldStyle(.plain).focused($focused)
                Text("\(shown.count) of \(model.webLocations.count)").font(.caption).foregroundStyle(.secondary)
                Button { model.promptAddWebLocation() } label: { Image(systemName: "plus") }.help("Add Web Location")
            }.padding(8)
            Divider()
            if model.webLocations.isEmpty {
                Text("No web locations yet. Use Go › Add Web Location…").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { w in
                    HStack(spacing: 8) {
                        Image(systemName: w.symbol).frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.title)
                            Text(w.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if !w.notes.isEmpty { Text(w.notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(2) }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.openWebLocation(w) }
                    .help(w.notes.isEmpty ? w.url : w.notes)
                    .contextMenu {
                        Button("Open in Browser") { model.openWebLocation(w) }
                        Button("Copy Address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(w.url, forType: .string) }
                        Divider()
                        Button("Remove from Web Locations") { model.removeWebLocation(w) }
                    }
                }.listStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear { focused = true }
    }
}
