import AppKit
import QuickLookUI

/// Space toggles the Quick Look panel for the selection. Online-only files are never downloaded to preview them.
@MainActor
final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var urls: [URL] = []

    func toggle(_ urls: [URL]) {
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible { panel.orderOut(nil); return }
        guard !urls.isEmpty else { return }
        self.urls = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { urls[index] as NSURL }
}
