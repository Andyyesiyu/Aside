import AppKit

func runResizeShortcutTests() throws {
    func check(_ ok: @autoclosure () -> Bool, _ name: String) throws {
        guard ok() else { throw NSError(domain: "ResizeShortcutTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS: \(name)")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("resize-shortcut-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try NoteStore(directory: directory)
    let owner = AppDelegate(store: store); owner.syncEnabled = false; owner.animateDesktopVisibility = false
    let a = Note(text: "当前便笺"), b = Note(text: "另一张便笺")
    store.book.notes = [a, b]
    owner.panel = EdgePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let screen = NSScreen.screens[0].visibleFrame
    owner.dragCard(a.id, topLeft: NSPoint(x: screen.minX + 50, y: screen.maxY - 60)); owner.finishDesktopDrag(a.id)
    let window = owner.desktopPanels[a.id]!
    defer { window.orderOut(nil); owner.panel.orderOut(nil) }
    window.makeKey(); window.makeFirstResponder(owner.cards[a.id]!.editor)
    owner.selectedID = b.id // A key window must win over a stale selection in another window.
    func event(_ text: String, flags: NSEvent.ModifierFlags = .command) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 24)!
    }
    let beforeDocument = store.note(a.id)!.effectiveDocument
    let selectedRange = owner.cards[a.id]!.editor.selectedRange()
    try check(window.performKeyEquivalent(with: event("=")), "Cmd 等号可直接增大当前便笺")
    try check(store.note(a.id)?.width == 312 && store.note(a.id)?.height == 282 && store.note(b.id)?.width == nil, "只改变当前窗口便笺宽高")
    let card = owner.cards[a.id]!
    card.layoutSubtreeIfNeeded()
    try check(abs(card.scroll.magnification - 1.1) < 0.0001 && store.note(a.id)?.effectiveZoom == 1.1, "快捷键同步放大文字显示")
    try check(card.editor.frame.width <= card.scroll.contentView.bounds.width + 1, "放大后文字按可见区域换行")
    try check(store.note(a.id)!.effectiveDocument == beforeDocument && card.editor.selectedRange() == selectedRange, "显示缩放不修改原文格式或光标位置")
    try check(window.performKeyEquivalent(with: event("+", flags: [.command, .shift])), "支持 Cmd Shift 加号")
    _ = window.performKeyEquivalent(with: event("-"))
    try check(store.note(a.id)?.width == 312 && store.note(a.id)?.height == 282, "Cmd 减号缩小宽高")
    try check(abs(card.scroll.magnification - 1.1) < 0.0001, "缩小快捷键同步缩小文字")
    try check(store.note(a.id)?.text == a.text && owner.cards[a.id]?.editor.string == a.text, "尺寸快捷键不改正文或插入符号")
    try check(NoteSizing.shortcut(event("+", flags: [.command, .option])) == nil && NoteSizing.shortcut(event("=", flags: [])) == nil, "不抢占普通输入和其他组合键")
    owner.store.update(a.id) { $0.collapsed = true }; owner.refresh()
    owner.stepCardSize(a.id, direction: -1)
    try check(store.note(a.id)?.height == 250 && window.frame.height == 32, "折叠时调整展开尺寸且维持折叠")
    owner.resizeCard(a.id, size: NSSize(width: 640, height: 600)); owner.stepCardSize(a.id, direction: 1)
    try check(store.note(a.id)?.width == 640 && store.note(a.id)?.height == 600, "快捷键遵守尺寸上限")
    owner.resizeCard(a.id, size: NSSize(width: 220, height: 130)); owner.stepCardSize(a.id, direction: -1)
    try check(store.note(a.id)?.width == 220 && store.note(a.id)?.height == 130, "快捷键遵守尺寸下限")
    try store.flush()
    let restored = try NoteStore(directory: directory)
    try check(restored.note(a.id)?.effectiveZoom == store.note(a.id)?.effectiveZoom, "每张便笺的文字缩放独立保存")
    try check(store.note(b.id)?.effectiveZoom == 1, "另一张便笺字号不受影响")
    try check(restored.note(a.id)?.width == 220 && restored.note(a.id)?.height == 130, "快捷键调整尺寸保存重开")
}
