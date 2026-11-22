import SwiftUI
import AppKit
import FinderCore

/// ⌘F. Results from what the app already knows appear instantly; Spotlight results join them shortly after.
@MainActor @Observable
final class QuickFindModel {
    var query = "" { didSet { if query != oldValue { update() } } }
    var results: [QuickFindResult] = []
    var selected = 0
    var searching = false

    private var task: Task<Void, Never>?
    private var frecency: [String: Double] = [:]
    private var local: [String] = []
    private var found: [String] = []
    private var currentFolder: String?

    func begin(model: AppModel) {
        currentFolder = model.current.path
        query = ""; found = []; selected = 0
        let store = model.store
        var candidates = model.entries.map(\.path) + model.tabs.map(\.path)
        candidates += ((try? store?.favorites()) ?? []).map(\.path) + ((try? store?.specialFolders()) ?? []).map(\.path)
        frecency = (try? store?.frecencyScores()) ?? [:]
        candidates += frecency.keys
        local = candidates
        results = QuickFind.recents(frecency: frecency)
    }

    func end() { task?.cancel(); task = nil; searching = false }

    private func update() {
        task?.cancel()
        selected = 0
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { found = []; searching = false; results = QuickFind.recents(frecency: frecency); return }
        rank(q)
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200)) // debounce
            guard !Task.isCancelled else { return }
            self?.searching = true
            let paths = await MDFind.search(query: q)
            guard !Task.isCancelled, let self else { return }
            self.found = paths
            self.searching = false
            self.rank(q)
        }
    }

    private func rank(_ q: String) {
        let ranked = QuickFind.rank(paths: local + found, query: q, currentFolder: currentFolder, frecency: frecency)
        let keep = results.indices.contains(selected) ? results[selected].path : nil
        results = ranked
        if let keep, let i = ranked.firstIndex(where: { $0.path == keep }) { selected = i } else { selected = 0 }
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(selected + delta, 0), results.count - 1)
    }
}

struct QuickFindView: View {
    @Environment(AppModel.self) private var model
    @State private var find = QuickFindModel()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.15).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find files and folders", text: $find.query)
                        .textFieldStyle(.plain).font(.title3).focused($focused)
                        .onKeyPress(.downArrow) { find.move(1); return .handled }
                        .onKeyPress(.upArrow) { find.move(-1); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                        .onKeyPress(.return) { choose(newTab: NSEvent.modifierFlags.contains(.command)); return .handled }
                    if find.searching { ProgressView().controlSize(.small) }
                }.padding(12)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(find.results.enumerated()), id: \.element.id) { i, r in
                                row(r, selected: i == find.selected).id(i)
                                    .onTapGesture { find.selected = i; choose(newTab: NSEvent.modifierFlags.contains(.command)) }
                            }
                        }
                    }
                    .onChange(of: find.selected) { _, i in proxy.scrollTo(i) }
                }
                .frame(maxHeight: 360)
                if find.results.isEmpty {
                    VStack(spacing: 4) {
                        Text(find.query.isEmpty ? "Type to search. Your most used folders and files show first." : (find.searching ? "Searching…" : "No matches"))
                        if !find.query.isEmpty && !find.searching {
                            Text("Missing files in Desktop, Documents or Downloads? macOS hides them from an app that hasn't been allowed to read them: System Settings › Privacy & Security › Files and Folders.")
                                .font(.caption)
                        }
                    }.font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(14)
                }
                Divider()
                Text("↩ go to it   ⌘↩ new tab / open file   esc close").font(.caption).foregroundStyle(.secondary).padding(6)
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 20)
            .padding(.top, 50)
        }
        .onAppear { find.begin(model: model); focused = true }
        .onDisappear { find.end() }
    }

    private func row(_ r: QuickFindResult, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: r.path)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted(r.name)).lineLimit(1)
                Text((r.path as NSString).deletingLastPathComponent.replacingOccurrences(of: AppPaths.home, with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.3) : .clear)
        .contentShape(Rectangle())
    }

    /// The full file name, with the parts that matched your search in bold accent colour.
    private func highlighted(_ name: String) -> AttributedString {
        var out = AttributedString(name)
        for w in find.query.split(separator: " ") {
            var from = name.startIndex
            while from < name.endIndex,
                  let r = name.range(of: w, options: [.caseInsensitive, .diacriticInsensitive], range: from..<name.endIndex) {
                if let ar = Range(r, in: out) {
                    out[ar].foregroundColor = .accentColor
                    out[ar].inlinePresentationIntent = .stronglyEmphasized
                }
                from = r.upperBound
            }
        }
        return out
    }

    private func close() { model.showQuickFind = false }

    private func choose(newTab: Bool) {
        guard find.results.indices.contains(find.selected) else { return }
        let r = find.results[find.selected]
        close()
        model.openQuickFindResult(r.path, isDirectory: r.isDirectory, newTab: newTab)
    }
}
