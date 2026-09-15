import AppKit

private final class HandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class EdgeHandle: NSObject {
    private let window: NSPanel
    private let button: EdgeHandleButton
    var onOpen: (() -> Void)?
    var onCommandClick: (() -> Void)?
    var isFixedMode = false
    var onToggleFixedMode: (() -> Void)?
    var onPositionChanged: ((Double) -> Void)?
    private var screenFrame = NSRect.zero
    private var dragStartY: CGFloat = 0

    override init() {
        window = HandlePanel(contentRect: NSRect(x: 0, y: 0, width: 44, height: 48),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        button = EdgeHandleButton(frame: NSRect(x: 0, y: 0, width: 44, height: 48))
        super.init()
        window.title = "打开旁白"
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        button.title = ""; button.isBordered = false
        button.toolTip = "单击打开便笺；⌘点击全部固定展开／隐藏；右键固定模式；上下拖动调整位置"
        button.setAccessibilityLabel("打开旁白便笺")
        button.target = self; button.action = #selector(openNotes)
        button.onCommandClick = { [weak self] in self?.onCommandClick?() }
        button.contextMenu = { [weak self] in self?.makeContextMenu() }
        window.contentView = button
        button.onPress = { [weak self] in self?.dragStartY = self?.window.frame.minY ?? 0 }
        button.onDrag = { [weak self] delta in
            guard let self = self else { return }
            let y = HandlePlacement.clampedY(self.dragStartY + delta, screen: self.screenFrame)
            self.window.setFrameOrigin(NSPoint(x: self.window.frame.minX, y: y))
        }
        button.onDrop = { [weak self] in
            guard let self = self else { return }
            let ratio = HandlePlacement.ratio(y: self.window.frame.minY, screen: self.screenFrame)
            self.onPositionChanged?(ratio)
        }
    }
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "固定模式（全部展开并保持显示）", action: #selector(toggleFixedMode), keyEquivalent: "")
        item.target = self; item.state = isFixedMode ? .on : .off
        menu.addItem(item)
        return menu
    }
    @objc private func toggleFixedMode() { onToggleFixedMode?() }
    // Keep the launch position interactive for dismissal checks after its window hides.
    // This is only consulted while notes are already open; hovering never opens them.
    func containsPointer(_ point: NSPoint) -> Bool { window.frame.insetBy(dx: -10, dy: -10).contains(point) }
    func hide() { window.orderOut(nil) }
    @objc private func openNotes() { onOpen?() }
    func update(screen: NSScreen, side: String, behavior: NSWindow.CollectionBehavior, visible: Bool, position: Double? = nil) {
        let frame = screen.visibleFrame
        screenFrame = frame
        let x = side == "left" ? frame.minX : frame.maxX - 44
        let y = HandlePlacement.y(position: position, screen: frame)
        if !button.dragging { window.setFrame(NSRect(x: x, y: y, width: 44, height: 48), display: true) }
        window.collectionBehavior = behavior
        window.level = .floating
        if visible { if !window.isVisible { window.orderFrontRegardless() } }
        else { window.orderOut(nil) }
    }
}

final class EdgeHandleButton: NSButton {
    var onCommandClick: (() -> Void)?
    private var commandPressed = false
    var contextMenu: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() ?? super.menu(for: event) }
    var onPress: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDrop: (() -> Void)?
    private var pressPoint: NSPoint?
    private(set) var dragging = false
    private func globalPoint(_ event: NSEvent) -> NSPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressPoint = globalPoint(event); dragging = false
        commandPressed = event.modifierFlags.contains(.command)
        highlight(true); onPress?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint else { return }
        let point = globalPoint(event)
        if !dragging && hypot(point.x - start.x, point.y - start.y) < 5 { return }
        dragging = true; highlight(false)
        onDrag?(point.y - start.y)
    }
    override func mouseUp(with event: NSEvent) {
        guard pressPoint != nil else { return }
        let wasDragging = dragging
        pressPoint = nil; highlight(false)
        if wasDragging { onDrop?() }
        else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            if commandPressed { onCommandClick?() }
            else { _ = sendAction(action, to: target) }
        }
        commandPressed = false
        dragging = false
    }
    private var hovered = false
    private var tracking: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shift = isHighlighted ? -1.0 : hovered ? 1.0 : 0.0
        let move = NSAffineTransform(); move.translateX(by: 0, yBy: shift); move.concat()
        func sheet(_ rect: NSRect, rotation: CGFloat, start: NSColor, end: NSColor, writing: Bool) {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: rotation)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowOffset = NSSize(width: 0.8, height: -1.6); shadow.shadowBlurRadius = 1.5
            shadow.set()
            let paper = NSBezierPath(rect: rect)
            start.setFill(); paper.fill()
            NSShadow().set()
            NSGradient(starting: start, ending: end)?.draw(in: paper, angle: -90)
            NSColor(calibratedRed: 0.35, green: 0.30, blue: 0.12, alpha: 0.85).setStroke()
            paper.lineWidth = 0.75; paper.stroke()
            NSColor.white.withAlphaComponent(0.75).setStroke()
            let edge = NSBezierPath(); edge.move(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 1))
            edge.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1)); edge.stroke()
            if writing {
                NSColor(calibratedRed: 0.28, green: 0.25, blue: 0.15, alpha: 0.8).setStroke()
                let ink = NSBezierPath()
                for row in 0..<3 {
                    let y = rect.maxY - 9 - CGFloat(row) * 4
                    ink.move(to: NSPoint(x: rect.minX + 5, y: y))
                    ink.line(to: NSPoint(x: rect.minX + 9, y: y + 0.6))
                    ink.line(to: NSPoint(x: rect.minX + (row == 2 ? 17 : 23), y: y - 0.2))
                }
                ink.lineWidth = 0.75; ink.stroke()
                let fold = NSBezierPath()
                fold.move(to: NSPoint(x: rect.maxX - 6, y: rect.minY))
                fold.line(to: NSPoint(x: rect.maxX - 6, y: rect.minY + 6))
                fold.line(to: NSPoint(x: rect.maxX, y: rect.minY + 6)); fold.close()
                NSColor(calibratedRed: 0.87, green: 0.73, blue: 0.37, alpha: 1).setFill(); fold.fill()
                fold.lineWidth = 0.5; fold.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        sheet(NSRect(x: 10, y: 5, width: 27, height: 29), rotation: 5,
              start: NSColor(calibratedRed: 1, green: 0.95, blue: 0.64, alpha: 1),
              end: NSColor(calibratedRed: 0.95, green: 0.83, blue: 0.43, alpha: 1), writing: false)
        sheet(NSRect(x: 6, y: 13, width: 29, height: 29), rotation: 12,
              start: NSColor(calibratedRed: 1, green: 0.99, blue: 0.78, alpha: 1),
              end: NSColor(calibratedRed: 1, green: 0.91, blue: 0.54, alpha: 1), writing: true)
        NSGraphicsContext.restoreGraphicsState()
    }
}


enum HandlePlacement {
    static func clampedY(_ y: CGFloat, screen: NSRect) -> CGFloat {
        min(max(screen.minY, y), max(screen.minY, screen.maxY - 48))
    }
    static func y(position: Double?, screen: NSRect) -> CGFloat {
        guard let position = position, position.isFinite else {
            return clampedY(screen.maxY - screen.height * 0.25 - 24, screen: screen)
        }
        return screen.minY + max(0, screen.height - 48) * min(1, max(0, position))
    }
    static func ratio(y: CGFloat, screen: NSRect) -> Double {
        min(1, max(0, (y - screen.minY) / max(1, screen.height - 48)))
    }
}
