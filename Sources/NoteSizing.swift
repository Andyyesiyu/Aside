import AppKit

enum NoteSizing {
    static func shortcut(_ event: NSEvent) -> Int? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags == .command || flags == [.command, .shift] else { return nil }
        switch event.characters {
        case "+", "=": return 1
        case "-" where !flags.contains(.shift): return -1
        default: return nil
        }
    }
    static func width(_ note: Note, defaultWidth: Double, screenWidth: CGFloat) -> CGFloat {
        min(max(220, note.width ?? defaultWidth), min(640, max(220, screenWidth - 24)))
    }
    static func dragged(initial: NSSize, start: NSPoint, current: NSPoint, side: String) -> NSSize {
        let dx = side == "right" ? start.x - current.x : current.x - start.x
        return NSSize(width: min(640, max(220, initial.width + dx)), height: min(600, max(130, initial.height + start.y - current.y)))
    }
}

extension AppDelegate {
    func stepCardSize(_ id: UUID, direction: Int) {
        guard let note = store.note(id) else { return }
        cards[id]?.editor.lastKeyboardInput = ProcessInfo.processInfo.systemUptime
        let width = note.width ?? store.book.preferences.width
        store.update(id) { $0.zoom = min(2, max(0.8, (note.effectiveZoom * 10 + Double(direction)).rounded() / 10)) }
        resizeCard(id, size: NSSize(width: width + Double(direction * 32), height: note.height + Double(direction * 32)))
    }
    func resizeCard(_ id: UUID, size: NSSize) {
        let screenWidth = (desktopPanels[id]?.screen ?? selectedScreen())?.visibleFrame.width ?? 1440
        let width = min(size.width, max(220, screenWidth - 24))
        store.update(id) { $0.width = max(220, min(640, width)); $0.height = max(130, min(600, size.height)) }
        refresh()
    }
    func sizeMenu(_ id: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: "便笺大小", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.addItem(self.item("增大便笺  ⌘+") { [weak self] in self?.stepCardSize(id, direction: 1) })
        menu.addItem(self.item("缩小便笺  ⌘−") { [weak self] in self?.stepCardSize(id, direction: -1) })
        menu.addItem(.separator())
        for (label, size) in [("小 · 240 × 180", NSSize(width: 240, height: 180)), ("中 · 280 × 250", NSSize(width: 280, height: 250)), ("大 · 400 × 350", NSSize(width: 400, height: 350))] {
            menu.addItem(self.item(label) { [weak self] in self?.resizeCard(id, size: size) })
        }
        menu.addItem(.separator())
        menu.addItem(self.item("恢复默认大小") { [weak self] in
            self?.store.update(id) { $0.width = nil; $0.height = 250; $0.zoom = nil }; self?.refresh()
        })
        item.submenu = menu
        return item
    }
}
