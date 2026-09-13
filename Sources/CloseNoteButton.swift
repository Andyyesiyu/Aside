import AppKit

final class CloseNoteButton: NSButton {
    var paperBorder = NSColor.gray { didSet { needsDisplay = true } }
    private var hovered = false
    private var hoverTracking: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = hoverTracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
        if hovered || isHighlighted {
            paperBorder.withAlphaComponent(isHighlighted ? 0.65 : 0.35).setFill()
            outline.fill()
        }
        (paperBorder.blended(withFraction: 0.28, of: .black) ?? paperBorder).setStroke()
        outline.lineWidth = 1; outline.stroke()
        NSColor.black.withAlphaComponent(hovered || isHighlighted ? 0.85 : 0.6).setStroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: rect.minX + 5, y: rect.minY + 5))
        cross.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 5))
        cross.move(to: NSPoint(x: rect.maxX - 5, y: rect.minY + 5))
        cross.line(to: NSPoint(x: rect.minX + 5, y: rect.maxY - 5))
        cross.lineWidth = 1.2; cross.stroke()
    }
}
