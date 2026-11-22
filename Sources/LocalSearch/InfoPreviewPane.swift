import SwiftUI
import FinderCore
import ImageIO

/// Facts about one item, gathered off the main thread.
struct FileInfo: Sendable {
    var name: String, path: String, kind: String
    var size: Int64?, itemCount: Int?
    var created: Date?, modified: Date?, added: Date?, lastOpened: Date?
    var permissions: String?
    var dimensions: String?
    var isDirectory = false
    var onlineOnly = false

    static func load(path: String, lastOpened: Date?) -> FileInfo? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
                                         .addedToDirectoryDateKey, .localizedTypeDescriptionKey, .ubiquitousItemDownloadingStatusKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDir = v.isDirectory ?? false
        var info = FileInfo(name: url.lastPathComponent, path: path, kind: isDir ? "Folder" : (v.localizedTypeDescription ?? "Document"))
        info.isDirectory = isDir
        info.size = isDir ? nil : v.fileSize.map(Int64.init)
        info.created = v.creationDate; info.modified = v.contentModificationDate; info.added = v.addedToDirectoryDate
        info.lastOpened = lastOpened
        info.onlineOnly = v.ubiquitousItemDownloadingStatus.map { $0 != .current && $0 != .downloaded } ?? false
        if isDir { info.itemCount = (try? FileManager.default.contentsOfDirectory(atPath: path))?.count }
        if let p = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int {
            info.permissions = String(p, radix: 8)
        }
        if Preview.kind(forName: info.name) == .image, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            info.dimensions = "\(w) × \(h)"
        }
        return info
    }
}

enum PreviewContent {
    case none
    case loading
    case result(PreviewResult)
    case markdown([MarkdownBlock], truncated: Bool)
    case image(CGImage)
}

struct InfoPreviewPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage("infoExpanded") private var infoExpanded = true
    @State private var info: FileInfo?
    @State private var content: PreviewContent = .none
    @State private var allowLarge = false
    @State private var showSecrets = false

    /// The one selected item, or the open folder when nothing (or several things) is selected.
    private var target: String {
        model.selection.count == 1 ? model.selection.first! : model.current.path
    }
    private var loadKey: String { "\(target)|\(allowLarge)|\(showSecrets)|\(model.historyVersion)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $infoExpanded) {
                infoGrid.padding(.top, 4)
            } label: {
                Text("Info").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
            Divider()
            ScrollView { previewBody.padding(8).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .task(id: loadKey) { await load() }
        .onChange(of: target) { _, _ in allowLarge = false; showSecrets = false }
    }

    @ViewBuilder private var infoGrid: some View {
        if let i = info {
            Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 2) {
                row("Name", i.name)
                row("Kind", i.kind)
                if let s = i.size { row("Size", s < 1000 ? "\(s) bytes" : "\(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)) (\(s.formatted()) bytes)") }
                if let n = i.itemCount { row("Items", n.formatted()) }
                if let d = i.dimensions { row("Dimensions", d) }
                row("Where", (i.path as NSString).deletingLastPathComponent)
                if let d = i.created { row("Created", fmt(d)) }
                if let d = i.modified { row("Modified", fmt(d)) }
                if let d = i.added { row("Added", fmt(d)) }
                if let d = i.lastOpened { row("Last opened", fmt(d)) }
                if let p = i.permissions { row("Permissions", p) }
                if i.onlineOnly { row("iCloud", "Not downloaded") }
            }.font(.caption).textSelection(.enabled)
        } else {
            Text("No information").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(v).lineLimit(3).truncationMode(.middle)
        }
    }
    private func fmt(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }

    @ViewBuilder private var previewBody: some View {
        switch content {
        case .none: Text("Nothing to preview").font(.caption).foregroundStyle(.secondary)
        case .loading: ProgressView().controlSize(.small)
        case .image(let img):
            Image(decorative: img, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity)
        case .markdown(let blocks, let truncated):
            MarkdownView(blocks: blocks)
            if truncated { note("Showing the first 64 KB") }
        case .result(let r):
            switch r {
            case .text(let t):
                Text(t.text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                if t.truncated { note("Showing the first 64 KB") }
            case .needsClick(let size):
                VStack(alignment: .leading, spacing: 6) {
                    note("This file is \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).")
                    Button("Show Preview") { allowLarge = true }.controlSize(.small)
                }
            case .withheld(let why):
                VStack(alignment: .leading, spacing: 6) {
                    note("Preview hidden. \(why).")
                    Button("Show Anyway") { showSecrets = true }.controlSize(.small)
                }
            case .unsupported(let msg): note(msg)
            }
        }
    }
    private func note(_ s: String) -> some View { Text(s).font(.caption).foregroundStyle(.secondary) }

    private func load() async {
        let path = target, large = allowLarge, secrets = showSecrets
        let opened = lastOpened(path)
        let loaded = await Task.detached(priority: .userInitiated) { () -> (FileInfo?, PreviewContent) in
            let info = FileInfo.load(path: path, lastOpened: opened)
            guard let i = info, !i.isDirectory else { return (info, .none) }
            switch Preview.kind(forName: i.name) {
            case .unsupported(let m): return (info, .result(.unsupported(m)))
            case .image:
                return (info, Self.thumbnail(path).map { .image($0) } ?? .result(.unsupported("Can't read this image")))
            case .markdown:
                let r = Preview.loadText(path: path, size: i.size ?? 0, allowLarge: large, showSecrets: secrets)
                if case .text(let t) = r { return (info, .markdown(MarkdownBlocks.parse(t.text), truncated: t.truncated)) }
                return (info, .result(r))
            case .text:
                return (info, .result(Preview.loadText(path: path, size: i.size ?? 0, allowLarge: large, showSecrets: secrets)))
            }
        }.value
        if Task.isCancelled { return }
        info = loaded.0; content = loaded.1
    }

    private func lastOpened(_ path: String) -> Date? {
        guard let rows = try? model.store?.db.query("SELECT MAX(opened_at) AS at FROM file_opens WHERE path=?", [.text(path)]),
              let s = rows.first?["at"]?.string else { return nil }
        return parseISO8601(s)
    }

    /// ImageIO thumbnail, so a huge photo never loads at full size.
    nonisolated static func thumbnail(_ path: String) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 1024]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// Renders the parsed Markdown blocks; inline styling comes from AttributedString.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let level, let t):
                    inline(t).font(.system(size: [18, 16, 14, 13, 12, 12][min(level, 6) - 1], weight: .semibold))
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); inline(t) }.font(.callout)
                case .code(let c):
                    Text(c).font(.system(size: 11, design: .monospaced)).padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                case .paragraph(let t): inline(t).font(.callout)
                case .rule: Divider()
                }
            }
        }.textSelection(.enabled)
    }
    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) { return Text(a) }
        return Text(s)
    }
}
