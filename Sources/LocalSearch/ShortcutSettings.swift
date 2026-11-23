import SwiftUI
import FinderCore

/// Settings > Shortcuts: click a shortcut, press the keys you want. Only your changes are saved, in shortcuts.json.
struct ShortcutSettings: View {
    private let store = ShortcutStore.shared
    @State private var filter = ""
    @State private var recording: String?
    @State private var recorder = ChordRecorder()
    @State private var notice: Notice?

    struct Notice: Equatable { var id: String; var chord: Chord; var problem: ShortcutOverrides.Problem }

    /// Pairs that share keys, possible after editing shortcuts.json by hand.
    private var clashes: [String: String] {
        var m: [String: String] = [:]
        for (a, b) in Shortcuts.clashes(store.list) { m[a] = b; m[b] = a }
        return m
    }

    private var sections: [(String, [ShortcutDef])] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        var order: [String] = [], groups: [String: [ShortcutDef]] = [:]
        for s in store.list {
            if !q.isEmpty, !(s.title.lowercased().contains(q) || s.display.lowercased().contains(q) || s.section.lowercased().contains(q)) { continue }
            if groups[s.section] == nil { order.append(s.section) }
            groups[s.section, default: []].append(s)
        }
        return order.map { ($0, groups[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search shortcuts", text: $filter).textFieldStyle(.roundedBorder)
                Button("Reset All") { store.resetAll(); stopRecording() }.disabled(store.changedCount == 0)
            }.padding(12)
            if store.malformed {
                Label("shortcuts.json can't be read, so your changes are ignored until it's fixed.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 12).padding(.bottom, 6)
            }
            if let n = notice { noticeBar(n) }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections, id: \.0) { name, items in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(.headline).padding(.bottom, 2)
                            ForEach(items) { row($0) }
                        }
                    }
                    if sections.isEmpty { Text("No shortcut matches “\(filter)”").foregroundStyle(.secondary) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Click a shortcut, then press the new keys. Esc cancels. Keys that only work inside a list are fixed.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show shortcuts.json") { store.revealFile() }.controlSize(.small)
            }.padding(10)
        }
        .onDisappear { stopRecording() }
    }

    private func row(_ s: ShortcutDef) -> some View {
        HStack(spacing: 6) {
            Text(s.title).foregroundStyle(s.rebindable ? .primary : .secondary)
            if let n = s.note { Text(n).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if let other = clashes[s.id] {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("Same keys as “\(store.def(other).title)”. Only one of them will work.")
            }
            if s.rebindable {
                if store.isChanged(s.id) {
                    Button { store.reset(s.id); notice = nil } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.plain).help("Back to the original, \(Shortcuts.def(s.id).display)")
                    if !s.isOff {
                        Button { store.turnOff(s.id); notice = nil } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).help("Turn this shortcut off")
                    }
                } else if !s.isOff {
                    Button { store.turnOff(s.id); notice = nil } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary).help("Turn this shortcut off")
                }
                Button { startRecording(s.id) } label: { chordLabel(s) }.buttonStyle(.plain)
            } else {
                chordLabel(s, fixed: true)
            }
        }
    }

    private func chordLabel(_ s: ShortcutDef, fixed: Bool = false) -> some View {
        let isRecording = recording == s.id
        return Text(isRecording ? "Press keys…" : s.display)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(isRecording ? Color.accentColor : fixed ? .secondary : s.isOff ? .secondary : .primary)
            .frame(minWidth: 70).padding(.horizontal, 7).padding(.vertical, 1)
            .background(isRecording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(store.isChanged(s.id) ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder private func noticeBar(_ n: Notice) -> some View {
        let name = store.def(n.id).title
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            switch n.problem {
            case .fixed: Text("That shortcut can't be changed.")
            case .needsModifier: Text("Include ⌘, ⌃ or ⌥, or typing would trigger “\(name)”.")
            case .reserved(let why): Text("\(display(n.chord)) is kept by macOS for \(why).")
            case .taken(let other):
                Text("\(display(n.chord)) is already used by “\(store.def(other).title)”.")
                Button("Use it for “\(name)” instead") { store.replace(other, with: n.id, chord: n.chord); notice = nil }.controlSize(.small)
            }
            Spacer()
            Button { notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .font(.caption).padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func display(_ c: Chord) -> String {
        ShortcutDef(id: "", section: "", title: "", key: c.key, mods: c.mods, scope: "App", note: nil).display
    }

    private func startRecording(_ id: String) {
        stopRecording(); notice = nil; recording = id
        recorder.start({ chord in
            recording = nil
            if let p = store.problem(setting: chord, for: id) { notice = Notice(id: id, chord: chord, problem: p) }
            else { store.set(id, to: chord) }
        }, onCancel: { recording = nil })
    }
    private func stopRecording() { recorder.stop(); recording = nil }
}
