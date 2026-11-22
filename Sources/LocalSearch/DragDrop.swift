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

/// Per-row drop target. (`ForEach` insertion drops and `.dropDestination` are avoided on purpose:
/// they show the "+" copy cursor and an insertion line, and never fire on `List` rows.)
struct FolderDropDelegate: DropDelegate {
    enum Mode { case moveInto, shortcutOrMove, copyIntoCurrent }
    let model: AppModel
    let path: String
    let mode: Mode
    let setTargeted: (Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { setTargeted(true) }
    func dropExited(info: DropInfo) { setTargeted(false) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let option = NSEvent.modifierFlags.contains(.option)
        return DropProposal(operation: (mode == .copyIntoCurrent || option) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        setTargeted(false)
        let flags = NSEvent.modifierFlags
        let providers = info.itemProviders(for: [.fileURL])
        let model = model, path = path, mode = mode
        Task { @MainActor in
            let urls = await loadFileURLs(providers)
            model.handleDrop(urls, onto: path, mode: mode, option: flags.contains(.option), command: flags.contains(.command))
        }
        return true
    }
}

struct DropTargetModifier: ViewModifier {
    let model: AppModel
    let path: String
    let mode: FolderDropDelegate.Mode
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .background(targeted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .onDrop(of: [.fileURL], delegate: FolderDropDelegate(model: model, path: path, mode: mode) { targeted = $0 })
    }
}

extension View {
    func folderDropTarget(_ model: AppModel, path: String, mode: FolderDropDelegate.Mode = .moveInto) -> some View {
        modifier(DropTargetModifier(model: model, path: path, mode: mode))
    }
}

/// Tabs accept both files (moved into the tab's folder) and other tabs (reorder).
struct TabDropDelegate: DropDelegate {
    let model: AppModel
    let tab: TabState
    let setTargeted: (Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL, .plainText]) }
    func dropEntered(info: DropInfo) { setTargeted(true) }
    func dropExited(info: DropInfo) { setTargeted(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if info.hasItemsConforming(to: [.fileURL]) {
            return DropProposal(operation: NSEvent.modifierFlags.contains(.option) ? .copy : .move)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        setTargeted(false)
        let model = model, tab = tab
        if info.hasItemsConforming(to: [.fileURL]) {
            let providers = info.itemProviders(for: [.fileURL])
            let option = NSEvent.modifierFlags.contains(.option)
            Task { @MainActor in
                model.handleDrop(await loadFileURLs(providers), onto: tab.path, mode: .moveInto, option: option, command: false)
            }
        } else if let p = info.itemProviders(for: [.plainText]).first {
            Task { @MainActor in
                let s: String? = await withCheckedContinuation { c in
                    _ = p.loadObject(ofClass: String.self) { s, _ in c.resume(returning: s) }
                }
                if let s, let id = UUID(uuidString: s) { model.moveTab(id, before: tab.id) }
            }
        }
        return true
    }
}

/// Dragging files out of the list must hand real file URLs to other apps (Chromium/Electron apps such
/// as Slack read them synchronously). SwiftUI's `TableRow.itemProvider` supplies data lazily, so we
/// start the drag ourselves from the table's NSOutlineView and write the pasteboard eagerly.
private struct EventBox: @unchecked Sendable { let event: NSEvent? }

struct AppKitDragFix: NSViewRepresentable {
    let selectedPaths: @MainActor () -> [String]

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        context.coordinator.anchor = v
        context.coordinator.install()
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.selectedPaths = selectedPaths }
    func makeCoordinator() -> Coordinator { Coordinator(selectedPaths) }

    @MainActor
    final class Coordinator: NSObject, NSDraggingSource {
        var selectedPaths: @MainActor () -> [String]
        weak var anchor: NSView?
        nonisolated(unsafe) private var monitor: Any?
        private var downPoint: NSPoint?
        private weak var downView: NSOutlineView?
        private static let dragDistance: CGFloat = 4 // NSEvent has no startDragDistance on macOS

        init(_ s: @escaping @MainActor () -> [String]) { selectedPaths = s }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }

        func install() {
            guard monitor == nil else { return }
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
                let box = EventBox(event: e) // monitors always run on the main thread
                return MainActor.assumeIsolated { EventBox(event: self?.handle(box.event) ?? box.event) }.event
            }
        }

        /// The file list is the outline view with four columns.
        private func fileList(in window: NSWindow?) -> NSOutlineView? {
            func find(_ v: NSView) -> NSOutlineView? {
                if let o = v as? NSOutlineView, o.tableColumns.count == 4 { return o }
                for s in v.subviews { if let f = find(s) { return f } }
                return nil
            }
            return window?.contentView.flatMap(find)
        }

        private func handle(_ e: NSEvent?) -> NSEvent? {
            guard let e else { return nil }
            switch e.type {
            case .leftMouseDown:
                downPoint = nil; downView = nil
                guard let ov = fileList(in: e.window), e.window === anchor?.window else { return e }
                let p = ov.convert(e.locationInWindow, from: nil)
                if ov.bounds.contains(p), ov.row(at: p) >= 0 { downPoint = p; downView = ov }
            case .leftMouseDragged:
                guard let ov = downView, let start = downPoint else { return e }
                let p = ov.convert(e.locationInWindow, from: nil)
                guard hypot(p.x - start.x, p.y - start.y) > Self.dragDistance else { return e }
                downPoint = nil; downView = nil
                let paths = selectedPaths()
                guard !paths.isEmpty else { return e }
                begin(in: ov, paths: paths, event: e, at: p)
                return nil // consume it so SwiftUI's own drag never starts
            case .leftMouseUp:
                downPoint = nil; downView = nil
            default: break
            }
            return e
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
