import AppKit
import SwiftUI

// 原生按钮显式接管首响应者，避免 popover 默认把焦点交给第一个 SwiftUI Button。
struct SortOptionsPanel: NSViewRepresentable {
    let selected: SearchSort
    let choose: (SearchSort) -> Void
    let dismiss: () -> Void
    func makeNSView(context: Context) -> SortChoiceView { SortChoiceView() }
    func updateNSView(_ view: SortChoiceView, context: Context) {
        view.configure(selected: selected, choose: choose, dismiss: dismiss)
    }
}

final class SortChoiceView: NSView {
    private var buttons: [SortChoiceButton] = []
    private var selection = SearchSort.relevance
    private var choose: ((SearchSort) -> Void)?
    private var dismiss: (() -> Void)?
    private var didFocus = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for (index, order) in SearchSort.allCases.enumerated() {
            let button = SortChoiceButton(title: order.title, target: self, action: #selector(pick(_:)))
            button.tag = index
            button.isBordered = false
            button.focusRingType = .none
            button.routeKey = { [weak self] event in self?.handle(event) ?? false }
            addSubview(button)
            buttons.append(button)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 10, y: CGFloat(10 + index * 40), width: max(CGFloat(0), bounds.width - 20), height: 36)
        }
    }
    func configure(selected: SearchSort, choose: @escaping (SearchSort) -> Void, dismiss: @escaping () -> Void) {
        selection = selected
        self.choose = choose
        self.dismiss = dismiss
        for (index, button) in buttons.enumerated() {
            button.current = SearchSort.allCases[index] == selected
            button.setAccessibilityHelp(button.current ? "当前排序" : nil)
            button.needsDisplay = true
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didFocus else { return }
        didFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = SearchSort.allCases.firstIndex(of: self.selection) else { return }
            self.window?.makeKey()
            self.window?.makeFirstResponder(self.buttons[index])
        }
    }
    @objc private func pick(_ sender: NSButton) { choose?(SearchSort.allCases[sender.tag]) }
    private func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let current = buttons.firstIndex(where: { window?.firstResponder === $0 }) ?? 0
        switch event.keyCode {
        case 125, 126:
            let next = min(buttons.count - 1, max(0, current + (event.keyCode == 125 ? 1 : -1)))
            buttons.forEach { $0.keyboardFocus = true; $0.needsDisplay = true }
            window?.makeFirstResponder(buttons[next])
        case 36, 49: choose?(SearchSort.allCases[current])
        case 53: dismiss?()
        default: return false
        }
        return true
    }
}

private final class SortChoiceButton: NSButton {
    var current = false
    var keyboardFocus = false
    var routeKey: ((NSEvent) -> Bool)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { keyboardFocus = true; needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        if routeKey?(event) != true { super.keyDown(with: event) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        (current ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.labelColor.withAlphaComponent(hovered ? 0.07 : 0.025)).setFill()
        shape.fill()
        if current || keyboardFocus && window?.firstResponder === self {
            NSColor.controlAccentColor.withAlphaComponent(current ? 0.3 : 0.7).setStroke()
            shape.lineWidth = 1; shape.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: current ? .medium : .regular), .foregroundColor: current ? NSColor.controlAccentColor : NSColor.labelColor]
        (title as NSString).draw(at: NSPoint(x: 12, y: (bounds.height - 15) / 2), withAttributes: attrs)
        if current { ("✓" as NSString).draw(at: NSPoint(x: bounds.width - 25, y: (bounds.height - 15) / 2), withAttributes: attrs) }
    }
}
