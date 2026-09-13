import AppKit

func runListIndentTests() throws {
    func check(_ ok: @autoclosure () -> Bool, _ message: String) throws {
        guard ok() else { throw NSError(domain: "ListIndentTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: \(message)")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("desknotes-list-depth-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try NoteStore(directory: directory), owner = AppDelegate(store: try NoteStore(directory: directory.appendingPathComponent("owner")))
    owner.syncEnabled = false
    let doc = try RichDocument.parse("<ul><li>父项</li><li>二级</li></ul>").get().canonical
    let note = Note(text: doc.text, richDocument: doc); owner.store.book.notes = [note]
    let card = NoteCard(note: note, owner: owner)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 460), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = card; card.frame = window.contentLayoutRect; card.layoutSubtreeIfNeeded()
    let editor = card.editor
    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    editor.typingAttributes = editor.textStorage!.attributes(at: editor.string.utf16.count - 1, effectiveRange: nil)
    for depth in 2...5 {
        if depth > 2 {
            editor.insertNewline(nil)
            editor.insertText("第\(depth)级", replacementRange: editor.selectedRange())
        }
        editor.insertTab(nil)
        try check(RichDocument.from(editor.attributedString()).blocks.last?.style.lists.count == depth, "Tab 进入第 \(depth) 级列表")
    }
    let five = RichDocument.from(editor.attributedString()).canonical
    editor.insertTab(nil)
    try check(RichDocument.from(editor.attributedString()).canonical == five && !editor.string.contains("\t"), "五级上限不插入伪缩进或第六级")
    editor.insertNewline(nil)
    editor.insertText("同级续项", replacementRange: editor.selectedRange())
    try check(RichDocument.from(editor.attributedString()).blocks.last?.style.lists.count == 5, "五级列表回车保持层级")
    let before = RichDocument.from(editor.attributedString()).canonical
    editor.undoManager?.removeAllActions()
    editor.insertBacktab(nil)
    let after = RichDocument.from(editor.attributedString()).canonical
    try check(after.blocks.last?.style.lists.count == 4, "Shift Tab 退回一级")
    editor.undoManager?.undo()
    try check(RichDocument.from(editor.attributedString()).canonical == before, "列表层级支持撤销")
    editor.undoManager?.redo()
    try check(RichDocument.from(editor.attributedString()).canonical == after, "列表层级支持重做")
    try owner.store.flush()
    let loaded = try NoteStore(directory: owner.store.directory)
    try check(loaded.note(note.id)?.effectiveDocument == after, "五级列表保存重开保留结构")
    let htmlRoundTrip = try RichDocument.parse(after.html()).get().canonical
    try check(htmlRoundTrip == after, "五级列表 HTML 往返保留结构")
    // Outdenting a parent moves its descendants as one subtree.
    let nested = try RichDocument.parse("<ul><li>A<ul><li>B<ul><li>C</li></ul></li></ul></li></ul>").get().canonical
    editor.textStorage?.setAttributedString(nested.attributed())
    let range = (editor.string as NSString).range(of: "B")
    editor.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
    editor.insertBacktab(nil)
    let moved = RichDocument.from(editor.attributedString())
    try check(moved.blocks.map { $0.style.lists.count } == [1, 1, 2], "父项退级时子项一起移动")
    try check(editor.selectedRange().location == (editor.string as NSString).range(of: "B").location + 1, "调整层级后光标仍停在原文字位置")
    _ = store
}
