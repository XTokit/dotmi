import AppKit
import QuickLookUI

// SwiftUI may retain a host when its window is closed or its selection changes.
// A closed QLPreviewView is terminal: it must never receive another previewItem.
final class PreviewContainer: NSView {
    private var preview: QLPreviewView?
    private(set) var currentURL: URL?

    func show(_ url: URL) {
        guard currentURL != url || preview == nil else { return }
        clear()
        guard let next = QLPreviewView(frame: bounds, style: .compact) else { return }
        next.shouldCloseWithWindow = false
        next.autostarts = false
        next.autoresizingMask = [.width, .height]
        addSubview(next)
        preview = next
        currentURL = url
        next.previewItem = url as NSURL
    }

    func clear() {
        // Drop ownership before closing so later SwiftUI updates can only create
        // a fresh instance, including an update following dismantleNSView.
        let previous = preview
        preview = nil
        currentURL = nil
        previous?.removeFromSuperview()
        previous?.close()
    }
}
