import AppKit
import SearchCore

// 非模态预览：保留搜索窗口，允许上下切换文件，关闭时释放 Quick Look 视图。
final class FilePreviewPanel: NSObject, NSWindowDelegate {
    static let shared = FilePreviewPanel()
    private let host = PreviewContainer(frame: NSRect(x: 0, y: 0, width: 640, height: 440))
    private var panel: PreviewKeyPanel?
    private var onClose: (() -> Void)?

    func show(_ file: FileRecord, onClose: @escaping () -> Void) {
        self.onClose = onClose
        if panel == nil {
            let window = PreviewKeyPanel(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = host
            window.identifier = NSUserInterfaceItemIdentifier("file-preview")
            window.minSize = NSSize(width: 440, height: 320)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            panel = window
        }
        host.show(file.url)
        panel?.title = file.name
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        onClose = nil
        host.clear()
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let completion = onClose
        onClose = nil
        host.clear()
        completion?()
    }
}

private final class PreviewKeyPanel: NSPanel {
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 49, 53: SearchModel.shared.preview = nil
        case 125: SearchModel.shared.moveSelection(1)
        case 126: SearchModel.shared.moveSelection(-1)
        default: super.keyDown(with: event)
        }
    }
}
