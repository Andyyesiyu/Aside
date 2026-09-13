import AppKit

struct DesktopPosition: Codable, Equatable {
    var x: Double
    var y: Double // Top-left in global macOS screen coordinates.
}

enum DesktopPlacement {
    static func frame(position: DesktopPosition, size: NSSize, screens: [NSRect]) -> NSRect {
        let proposed = NSRect(x: position.x, y: position.y - size.height, width: size.width, height: size.height)
        guard let screen = screens.max(by: {
            let a = $0.intersection(proposed), b = $1.intersection(proposed)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }) else { return proposed }
        return NSRect(x: min(max(proposed.minX, screen.minX), max(screen.minX, screen.maxX - size.width)),
                      y: min(max(proposed.minY, screen.minY), max(screen.minY, screen.maxY - size.height)),
                      width: size.width, height: size.height)
    }
}

extension AppDelegate {
    func updateDesktopCard(_ card: NoteCard, note: Note, size: NSSize) {
        guard let position = note.desktopPosition else { return }
        let floating: EdgePanel
        if let existing = desktopPanels[note.id] { floating = existing }
        else {
            floating = EdgePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            floating.isOpaque = false; floating.backgroundColor = .clear
            floating.hasShadow = true; floating.hidesOnDeactivate = false
            floating.isReleasedWhenClosed = false; floating.animationBehavior = .none
            floating.contentView = FlippedView()
            desktopPanels[note.id] = floating
            let transition = PanelTransition(panel: floating, content: floating.contentView!)
            transition.slideDistance = 0
            desktopTransitions[note.id] = transition
        }
        if card.superview !== floating.contentView {
            card.removeFromSuperview(); floating.contentView?.addSubview(card)
        }
        let frame = draggingNotes.contains(note.id)
            ? NSRect(x: position.x, y: position.y - size.height, width: size.width, height: size.height)
            : ScreenLayout.restored(position: position, anchor: note.screenAnchor, size: size, screens: ScreenLayout.current)
        floating.setFrame(frame, display: true)
        card.frame = NSRect(origin: .zero, size: frame.size)
        floating.level = panel.level; floating.collectionBehavior = panel.collectionBehavior

    }
    func dragCard(_ id: UUID, topLeft: NSPoint) {
        hidden = false; edgeState.concealed = false; edgeState.outsideSince = nil
        draggingNotes.insert(id)
        store.update(id) { $0.desktopPosition = DesktopPosition(x: topLeft.x, y: topLeft.y); $0.screenAnchor = nil }
        if let floating = desktopPanels[id] {
            floating.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - floating.frame.height))
        } else { refresh() }
        desktopPanels[id]?.orderFrontRegardless()
    }
    func finishDesktopDrag(_ id: UUID) {
        draggingNotes.remove(id)
        guard let window = desktopPanels[id] else { return }
        let frame = ScreenLayout.restored(position: DesktopPosition(x: window.frame.minX, y: window.frame.maxY), anchor: nil, size: window.frame.size, screens: ScreenLayout.current)
        window.setFrame(frame, display: true)
        store.update(id) {
            $0.desktopPosition = DesktopPosition(x: frame.minX, y: frame.maxY)
            $0.screenAnchor = ScreenLayout.anchor(frame: frame, screens: ScreenLayout.current)
        }
    }
    func dockCard(_ id: UUID) {
        cards[id]?.commitText()
        store.update(id) { $0.desktopPosition = nil; $0.screenAnchor = nil; $0.pinned = false }
        hidden = false; edgeState.concealed = false; edgeState.outsideSince = nil
        refresh()
    }
    func togglePin(_ id: UUID) {
        guard let note = store.note(id) else { return }
        if !note.isPinned && note.desktopPosition == nil { detachCard(id) }
        store.update(id) { $0.pinned = !note.isPinned }
        if note.isPinned { hidden = false; edgeState.concealed = false; edgeState.outsideSince = nil }
        refresh()
    }
    func detachCard(_ id: UUID) {
        guard let card = cards[id], let window = card.window else { return }
        let rect = window.convertToScreen(card.convert(card.bounds, to: nil))
        dragCard(id, topLeft: NSPoint(x: rect.minX - 40, y: rect.maxY - 20))
        finishDesktopDrag(id)
    }
}
