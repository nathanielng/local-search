import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FinderCore

/// Resolve dropped providers to file URLs.
@MainActor
func loadFileURLs(_ providers: [NSItemProvider]) async -> [URL] {
    var urls: [URL] = []
    for p in providers {
        let url: URL? = await withCheckedContinuation { c in
            _ = p.loadObject(ofClass: URL.self) { u, _ in c.resume(returning: u) }
        }
        if let url, url.isFileURL { urls.append(url) }
    }
    return urls
}

/// Where on a Favorites row a folder landed: the top/bottom edges are the gaps between rows.
enum DropZone { case before, into, after }

/// Per-row drop target. (`ForEach` insertion drops and `.dropDestination` are avoided on purpose:
/// they show the "+" copy cursor and an insertion line, and never fire on `List` rows.)
struct FolderDropDelegate: DropDelegate {
    enum Mode { case moveInto, shortcutOrMove, copyIntoCurrent, addShortcut }
    let model: AppModel
    let path: String
    let mode: Mode
    var rowHeight: CGFloat = 0
    let setState: (Bool, DropZone) -> Void

    /// Folders being dragged (read from the drag pasteboard, which is readable while hovering).
    static func draggedAreAllFolders() -> Bool {
        let urls = (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        return !urls.isEmpty && urls.allSatisfy {
            var d: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &d) && d.boolValue
        }
    }

    func zone(_ info: DropInfo) -> DropZone {
        guard mode == .shortcutOrMove, rowHeight > 0, Self.draggedAreAllFolders() else { return .into }
        let y = info.location.y
        return y < rowHeight * 0.3 ? .before : (y > rowHeight * 0.7 ? .after : .into)
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { setState(true, zone(info)) }
    func dropExited(info: DropInfo) { setState(false, .into) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        setState(true, zone(info))
        let option = NSEvent.modifierFlags.contains(.option)
        return DropProposal(operation: (mode == .copyIntoCurrent || option) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = zone(info)
        setState(false, .into)
        let flags = NSEvent.modifierFlags
        let providers = info.itemProviders(for: [.fileURL])
        let model = model, path = path, mode = mode
        Task { @MainActor in
            let urls = await loadFileURLs(providers)
            model.handleDrop(urls, onto: path, mode: mode, zone: zone, option: flags.contains(.option), command: flags.contains(.command))
        }
        return true
    }
}

struct DropTargetModifier: ViewModifier {
    let model: AppModel
    let path: String
    let mode: FolderDropDelegate.Mode
    @State private var id = UUID()
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        // One shared highlight, so a row whose "exited" callback was skipped can't keep a stale one.
        let active = model.dropHighlight?.id == id
        let zone = model.dropHighlight?.zone ?? .into
        content
            .background(active && zone == .into ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
            // A folder dropped in the gap between two favorites adds a shortcut there.
            .overlay(alignment: zone == .before ? .top : .bottom) {
                if active && zone != .into { Capsule().fill(Color.accentColor).frame(height: 3).padding(.horizontal, 6) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrop(of: [.fileURL], delegate: FolderDropDelegate(model: model, path: path, mode: mode, rowHeight: height) { [id] on, z in
                if on { model.setDropHighlight(id: id, zone: z) } else { model.clearDropHighlight(id: id) }
            })
    }
}

extension View {
    func folderDropTarget(_ model: AppModel, path: String, mode: FolderDropDelegate.Mode = .moveInto) -> some View {
        modifier(DropTargetModifier(model: model, path: path, mode: mode))
    }
}

/// Tabs accept both files (moved into the tab's folder) and other tabs (reorder). A tab dropped on the
/// left half of another tab goes before it, on the right half after it.
struct TabDropDelegate: DropDelegate {
    let model: AppModel
    let tab: TabState
    let width: CGFloat

    private func isFiles(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL, .plainText]) }
    func dropEntered(info: DropInfo) { mark(info) }
    func dropExited(info: DropInfo) { model.clearTabDropMark(tab: tab.id) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        mark(info)
        if isFiles(info) { return DropProposal(operation: NSEvent.modifierFlags.contains(.option) ? .copy : .move) }
        return DropProposal(operation: .move)
    }
    private func mark(_ info: DropInfo) {
        model.setTabDropMark(tab: tab.id, after: width > 0 && info.location.x > width / 2, files: isFiles(info))
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = width > 0 && info.location.x > width / 2
        model.clearTabDropMark(tab: tab.id)
        let model = model, tab = tab
        if isFiles(info) {
            let providers = info.itemProviders(for: [.fileURL])
            let option = NSEvent.modifierFlags.contains(.option)
            Task { @MainActor in
                model.handleDrop(await loadFileURLs(providers), onto: tab.path, mode: .moveInto, zone: .into, option: option, command: false)
            }
        } else if let p = info.itemProviders(for: [.plainText]).first {
            Task { @MainActor in
                let s: String? = await withCheckedContinuation { c in
                    _ = p.loadObject(ofClass: String.self) { s, _ in c.resume(returning: s) }
                }
                if let s, let id = UUID(uuidString: s) { model.moveTab(id, relativeTo: tab.id, after: after) }
            }
        }
        return true
    }
}

/// The empty space after the last tab: dropping a tab here moves it to the very end.
struct TabEndDropDelegate: DropDelegate {
    let model: AppModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { if let last = model.tabs.last { model.setTabDropMark(tab: last.id, after: true, files: false) } }
    func dropExited(info: DropInfo) { if let last = model.tabs.last { model.clearTabDropMark(tab: last.id) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let last = model.tabs.last { model.clearTabDropMark(tab: last.id) }
        guard let p = info.itemProviders(for: [.plainText]).first else { return false }
        let model = model
        Task { @MainActor in
            let s: String? = await withCheckedContinuation { c in
                _ = p.loadObject(ofClass: String.self) { s, _ in c.resume(returning: s) }
            }
            if let s, let id = UUID(uuidString: s) { model.moveTabToEnd(id) }
        }
        return true
    }
}

/// Dragging files out of the list must hand real file URLs to other apps (Chromium/Electron apps such
/// as Slack read them synchronously). SwiftUI's own row drag supplies data lazily (0 bytes), and NSTableView
/// runs a private mouse-tracking loop on mouse-down that hides the drag from event monitors.
/// So on a mouse-down over a row we take the click, track it ourselves, and either start a drag session
/// (pointer moved more than 4 pt) or hand the click back to the table untouched.
struct AppKitDragFix: NSViewRepresentable {
    /// File paths in row order.
    let paths: [String]

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        context.coordinator.anchor = v
        context.coordinator.install()
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.paths = paths }
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, NSDraggingSource {
        var paths: [String] = []
        weak var anchor: NSView?
        nonisolated(unsafe) private var monitor: Any?
        private weak var table: NSOutlineView?
        private static let dragDistance: CGFloat = 4 // NSEvent has no startDragDistance on macOS

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
                let box = EventBox(event: e) // monitors always run on the main thread
                return MainActor.assumeIsolated { () -> EventBox in
                    guard let me = self, let ev = box.event else { return box }
                    return EventBox(event: me.mouseDown(ev)) // nil = we took the click
                }.event
            }
        }

        /// The file list is the outline view with four columns.
        private func fileList(in window: NSWindow?) -> NSOutlineView? {
            if let t = table, t.window === window { return t }
            func find(_ v: NSView) -> NSOutlineView? {
                if let o = v as? NSOutlineView, o.tableColumns.count == 4 { return o }
                for s in v.subviews { if let f = find(s) { return f } }
                return nil
            }
            table = window?.contentView.flatMap(find)
            return table
        }

        /// Plain clicks are never consumed or replayed (that broke double-click and delayed the table).
        /// While the button is held we only watch the pointer; if it moves past the drag distance we
        /// take over and start a file drag, otherwise the click reaches the table untouched.
        private func mouseDown(_ e: NSEvent) -> NSEvent? {
            guard e.clickCount == 1, e.window === anchor?.window, let ov = fileList(in: e.window), let win = e.window else { return e }
            let flags = e.modifierFlags.intersection([.shift, .command, .control])
            guard flags.isEmpty else { return e } // range/extend selection clicks stay with the table
            let p = ov.convert(e.locationInWindow, from: nil)
            let row = ov.row(at: p)
            guard ov.bounds.contains(p), row >= 0, row < paths.count else { return e }
            // Clicks inside a text field (inline rename) belong to the field.
            if let hit = win.contentView?.hitTest(e.locationInWindow), hit is NSText || hit is NSTextField { return e }

            // Highlight right away (the table only sees the click after we hand it back on release).
            if !ov.selectedRowIndexes.contains(row) { ov.selectRowIndexes([row], byExtendingSelection: false) }
            let start = win.convertPoint(toScreen: e.locationInWindow)
            let began = Date()
            var dragged = false
            while NSEvent.pressedMouseButtons & 1 != 0 {
                let now = NSEvent.mouseLocation
                if hypot(now.x - start.x, now.y - start.y) > Self.dragDistance { dragged = true; break }
                if Date().timeIntervalSince(began) > 30 { break }
                usleep(3000)
            }
            guard dragged else { return e }
            // Use the newest pending drag event for the session (older ones are moot).
            var drag: NSEvent?
            while let n = NSApp.nextEvent(matching: .leftMouseDragged, until: Date(timeIntervalSinceNow: 0.02),
                                          inMode: .eventTracking, dequeue: true) { drag = n }
            guard let drag else { return e }
            if !ov.selectedRowIndexes.contains(row) { ov.selectRowIndexes([row], byExtendingSelection: false) }
            let files = ov.selectedRowIndexes.filter { $0 < paths.count }.map { paths[$0] }
            begin(in: ov, paths: files, event: drag, at: ov.convert(drag.locationInWindow, from: nil))
            return nil
        }

        private func begin(in view: NSView, paths: [String], event: NSEvent, at p: NSPoint) {
            let items = paths.enumerated().map { i, path -> NSDraggingItem in
                let pb = NSPasteboardItem()
                // Written eagerly: lazy providers give 0 bytes to Chromium/Electron.
                pb.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                pb.setPropertyList([path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
                let item = NSDraggingItem(pasteboardWriter: pb)
                let off = CGFloat(min(i, 5) * 4)
                item.setDraggingFrame(NSRect(x: p.x - 16 + off, y: p.y - 16 + off, width: 32, height: 32),
                                      contents: NSWorkspace.shared.icon(forFile: path))
                return item
            }
            view.beginDraggingSession(with: items, event: event, source: self)
        }

        nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .move]
        }
    }
}

private struct EventBox: @unchecked Sendable { let event: NSEvent? }
