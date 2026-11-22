import SwiftUI
import AppKit
import FinderCore

/// ⌃` : pick an action for the selection, review the exact command, run it, watch the output.
struct CommandPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showCommands") private var showCommands = false
    @AppStorage("commandPanelHeight") private var panelHeight = 300.0
    @State private var picked: Action?
    @State private var variantID: String?
    @State private var asks: [String: String] = [:]
    @State private var command = ""
    @State private var edited = false
    @State private var showAll = false
    @State private var group: String?
    @State private var showExplain = false
    @State private var confirming = false

    private var ctx: ActionContext { model.actionContext }
    /// The picked action with its chosen variant applied.
    private var active: Action? { picked.map { Actions.resolved($0, variant: variantID) } }
    private static let variantsKey = "actionVariants"
    private func remembered(_ id: String) -> String? { (UserDefaults.standard.dictionary(forKey: Self.variantsKey) as? [String: String])?[id] }
    private func remember(_ id: String, variant: String?) {
        var d = (UserDefaults.standard.dictionary(forKey: Self.variantsKey) as? [String: String]) ?? [:]
        d[id] = variant
        UserDefaults.standard.set(d, forKey: Self.variantsKey)
    }
    private var groups: [String] { var seen: [String] = []; for a in model.actions where !seen.contains(a.group) { seen.append(a.group) }; return seen }
    private var running: Bool { model.commandRun?.running == true }

    var body: some View {
        let c = ctx
        let rows = model.actions
            .filter { group == nil || $0.group == group }
            .map { ($0, Actions.availability(of: $0, in: c)) }
            .filter { showAll || $0.1.isAvailable }
        VStack(spacing: 0) {
            header(count: model.actions.count)
            Divider()
            badges(rows)
            Divider()
            editor
            if showExplain, let a = active, let lines = a.explain, !lines.isEmpty { explain(lines) }
            Divider()
            output
        }
        .frame(height: min(max(panelHeight, 180), 600))
        .background(.background)
        .onChange(of: model.selection) { _, _ in refreshIfUnedited() }
        .onChange(of: model.current.path) { _, _ in refreshIfUnedited() }
        .confirmationDialog("Run this command?", isPresented: $confirming) {
            Button("Run") { model.runCommand(command) }
            Button("Cancel", role: .cancel) {}
        } message: { Text(command) }
    }

    // MARK: Parts

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Label("Commands", systemImage: "terminal").font(.headline)
            Text("in \((model.current.path as NSString).lastPathComponent)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Toggle("All \(count)", isOn: $showAll).toggleStyle(.button).controlSize(.small)
                .help("Also show actions that don't fit the selection, with the reason")
            Button { NSWorkspace.shared.open(AppModel.actionsURL) } label: { Image(systemName: "doc.text") }
                .buttonStyle(.plain).help("Open actions.json to edit or add actions")
            Button { showCommands = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close (⌃`)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func badges(_ rows: [(Action, Availability)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Everything", on: group == nil) { group = nil }
                    ForEach(groups, id: \.self) { g in chip(g, on: group == g) { group = (group == g) ? nil : g } }
                }
            }
            if let e = model.actionsError {
                Text(e).font(.caption).foregroundStyle(.orange)
            }
            ScrollView(.vertical) {
                FlowRows(spacing: 6) {
                    ForEach(rows, id: \.0.id) { a, av in
                        Button { pick(a) } label: {
                            Text(a.title).font(.callout).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(picked?.id == a.id ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15), in: Capsule())
                                .opacity(av.isAvailable ? 1 : 0.45)
                        }
                        .buttonStyle(.plain).disabled(!av.isAvailable)
                        .help(av.isAvailable ? a.description : "\(a.description)\n\(unavailableText(av))")
                    }
                    if rows.isEmpty {
                        Text(model.selection.isEmpty ? "Nothing fits this folder. Select items to see more actions." : "No action fits this selection. Turn on “All” to see why.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 2)
            }.frame(maxHeight: 84)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func unavailableText(_ a: Availability) -> String { if case .unavailable(let r) = a { return "Not available: \(r)" } else { return "" } }

    private func chip(_ t: String, on: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Text(t).font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                .background(on ? Color.accentColor.opacity(0.3) : .clear, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
        }.buttonStyle(.plain)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let base = picked, let vs = base.variants, !vs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Variant").font(.caption).foregroundStyle(.secondary)
                        chip(base.baseLabel ?? "Standard", on: variantID == nil) { setVariant(nil) }
                            .help(base.description)
                        ForEach(vs) { v in chip(v.title, on: variantID == v.id) { setVariant(v.id) }.help(v.description ?? base.description) }
                    }
                }
            }
            if let a = active {
                let fields = Actions.asks(in: a.command)
                if !fields.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(fields, id: \.label) { f in
                            HStack(spacing: 4) {
                                Text(f.label).font(.caption).foregroundStyle(.secondary)
                                TextField("", text: Binding(get: { asks[f.label] ?? f.def }, set: { asks[f.label] = $0; edited = false; rerender() }))
                                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                TextEditor(text: Binding(get: { command }, set: { if $0 != command { command = $0; edited = true } }))
                    .font(.system(size: 12, design: .monospaced)).frame(height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
                    .overlay(alignment: .topLeading) {
                        if command.isEmpty { Text("Pick an action, or type a command to run in this folder").font(.caption).foregroundStyle(.tertiary).padding(6).allowsHitTesting(false) }
                    }
                VStack(spacing: 4) {
                    if running {
                        Button("Stop") { model.stopCommand() }.keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button("Run") { run() }.keyboardShortcut(.return, modifiers: .command)
                            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let a = active, a.explain?.isEmpty == false {
                        Button(showExplain ? "Hide" : "What this does") { showExplain.toggle() }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func explain(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
    }

    @ViewBuilder private var output: some View {
        if let run = model.commandRun {
            OutputView(run: run, clickable: active?.results == true)
        } else {
            Text("Nothing runs until you press Run (⌘↩).").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Actions

    private func pick(_ a: Action) {
        picked = a; asks = [:]; edited = false
        let r = remembered(a.id)
        variantID = (r != nil && a.variants?.contains { $0.id == r } == true) ? r : nil
        rerender()
    }
    private func setVariant(_ id: String?) {
        variantID = id; asks = [:]; edited = false
        if let p = picked { remember(p.id, variant: id) }
        rerender()
    }
    private func rerender() { if let a = active { command = Actions.render(a, in: ctx, asks: asks) } }
    private func refreshIfUnedited() { if !edited { rerender() } }
    private func run() {
        if active?.confirm == true { confirming = true } else { model.runCommand(command) }
    }
}

struct OutputView: View {
    @Environment(AppModel.self) private var model
    var run: CommandRun
    var clickable: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if clickable && !run.running {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(run.output.split(separator: "\n", omittingEmptySubsequences: false).prefix(2000).enumerated()), id: \.offset) { _, l in
                                Text(String(l)).font(.system(size: 12, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle()).onTapGesture { open(String(l)) }
                                    .help("Click to show in the file list")
                            }
                        }.padding(8)
                    } else {
                        Text(run.output.isEmpty && run.running ? "Running…" : run.output)
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: run.output) { _, _ in if run.running { proxy.scrollTo("end") } }
            }
            Divider()
            HStack(spacing: 6) {
                if run.running { ProgressView().controlSize(.small); Text("Running") }
                else if let c = run.exitCode {
                    Image(systemName: c == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(c == 0 ? .green : .red)
                    Text(c == 0 ? "Finished" : c == 143 ? "Stopped" : "Failed (exit code \(c))")
                }
                if run.truncated { Text("Output was cut at 400 KB").foregroundStyle(.orange) }
                Spacer()
                Button("Copy Output") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(run.output, forType: .string) }
                    .buttonStyle(.link).disabled(run.output.isEmpty)
            }
            .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
        }
    }

    private func open(_ line: String) {
        guard let path = model.pathsInOutput(line) else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue { model.navigate(path, .click) }
        else { model.pendingSelection = path; model.navigate((path as NSString).deletingLastPathComponent, .click) }
    }
}

/// Wraps its children onto as many rows as needed.
struct FlowRows: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 600, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(bounds.width, subviews).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var out: [CGRect] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            out.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x)
        }
        return (out, CGSize(width: min(maxX, width), height: y + rowH))
    }
}
