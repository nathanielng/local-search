import SwiftUI
import FinderCore

/// "?" in the file list, ⌘/ or Help > Keyboard Shortcuts: every shortcut, searchable.
struct ShortcutsView: View {
    @State private var filter = ""
    @FocusState private var focused: Bool

    private var sections: [(String, [ShortcutDef])] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        var order: [String] = [], groups: [String: [ShortcutDef]] = [:]
        for s in Shortcuts.all {
            if !q.isEmpty, !(s.title.lowercased().contains(q) || s.display.lowercased().contains(q) || s.section.lowercased().contains(q)
                             || (s.note ?? "").lowercased().contains(q)) { continue }
            if groups[s.section] == nil { order.append(s.section) }
            groups[s.section, default: []].append(s)
        }
        return order.map { ($0, groups[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search shortcuts", text: $filter).textFieldStyle(.roundedBorder).focused($focused).padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.0) { name, items in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.headline).padding(.bottom, 2)
                            ForEach(items) { s in
                                HStack {
                                    Text(s.title)
                                    if let n = s.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Text(s.display).font(.system(.body, design: .monospaced)).padding(.horizontal, 7).padding(.vertical, 1)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                    }
                    if sections.isEmpty { Text("No shortcut matches “\(filter)”").foregroundStyle(.secondary) }
                    Text("Most of these are also in the menus. In menus, the shortcut shows beside each item.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .onAppear { focused = true }
        .onKeyPress(.escape) { NSApp.keyWindow?.close(); return .handled }
    }
}
