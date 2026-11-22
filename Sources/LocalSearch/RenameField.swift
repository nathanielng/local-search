import SwiftUI
import AppKit

/// Inline rename editor: the stem is selected (not the extension), Return commits, Esc cancels.
struct RenameField: NSViewRepresentable {
    let initial: String
    let isDirectory: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: initial)
        tf.delegate = context.coordinator
        tf.font = .systemFont(ofSize: NSFont.systemFontSize)
        tf.lineBreakMode = .byTruncatingMiddle
        tf.focusRingType = .exterior
        DispatchQueue.main.async {
            tf.window?.makeFirstResponder(tf)
            let stem = isDirectory ? (initial as NSString).length : (initial as NSString).deletingPathExtension.count
            tf.currentEditor()?.selectedRange = NSRange(location: 0, length: stem)
        }
        return tf
    }
    func updateNSView(_ nsView: NSTextField, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit, onCancel: onCancel) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let onCommit: (String) -> Void, onCancel: () -> Void
        private var finished = false
        init(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) { self.onCommit = onCommit; self.onCancel = onCancel }

        func controlTextDidEndEditing(_ n: Notification) { // Return or focus loss
            guard !finished, let tf = n.object as? NSTextField else { return }
            finished = true
            onCommit(tf.stringValue)
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard sel == #selector(NSResponder.cancelOperation(_:)) else { return false }
            finished = true
            onCancel()
            return true
        }
    }
}
