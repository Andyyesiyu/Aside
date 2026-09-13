import AppKit

func runHeadingTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NSError(domain: "HeadingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: \(message)")
    }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("desknotes-headings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: path) }
    let owner = AppDelegate(store: try NoteStore(directory: path)); owner.syncEnabled = false
    let note = Note(); owner.store.book.notes = [note]
    let card = NoteCard(note: note, owner: owner)
    let window = EdgePanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.contentView = card; window.makeFirstResponder(card.editor)
    defer { window.orderOut(nil) }
    let editor = card.editor
    func reset(_ text: String = "") {
        editor.textStorage?.setAttributedString(RichDocument(text: text).attributed())
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: BlockStyle())
        editor.undoManager?.removeAllActions()
    }
    let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11)!
    reset("中文 bold"); editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
    try check(editor.performKeyEquivalent(with: key), "独立便笺编辑器处理 Cmd B")
    try check(RichDocument.from(editor.attributedString()).blocks[0].runs.allSatisfy { $0.style.bold }, "Cmd B 加粗选中的中英文")
    _ = editor.performKeyEquivalent(with: key)
    try check(RichDocument.from(editor.attributedString()).blocks[0].runs.allSatisfy { !$0.style.bold }, "再次 Cmd B 取消加粗")
    reset(); _ = editor.performKeyEquivalent(with: key); editor.insertText("重点", replacementRange: editor.selectedRange())
    try check(RichDocument.from(editor.attributedString()).blocks[0].runs[0].style.bold, "无选区时 Cmd B 切换后续输入样式")
    for level in 1...6 {
        reset()
        for character in String(repeating: "#", count: level) + " 标题" { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
        let doc = RichDocument.from(editor.attributedString())
        try check(editor.string == "标题" && doc.blocks[0].style.tag == "h\(level)", "实时输入第 \(level) 级标题")
        let font = editor.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        try check(font.pointSize == [24.0, 21, 18, 16, 15, 14][level - 1], "第 \(level) 级标题字号")
        let restored = try JSONDecoder().decode(RichDocument.self, from: JSONEncoder().encode(doc))
        try check(restored.canonical.blocks[0].style.tag == "h\(level)", "第 \(level) 级标题保存保留")
        if level <= 2 { try check(doc.notesWriteIssue == nil, "已支持的标题可回写") }
        else { try check(doc.notesWriteIssue?.contains("三级至六级") == true, "未验证的标题层级不会静默降级回写") }
        editor.insertNewline(nil); editor.insertText("正文", replacementRange: editor.selectedRange())
        let body = RichDocument.from(editor.attributedString()).blocks.last!
        try check(body.style.tag == "div" && !body.runs[0].style.bold, "标题回车恢复普通正文")
    }
    reset("已有文字\n下一段")
    for character in "### " { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
    let converted = RichDocument.from(editor.attributedString())
    try check(converted.blocks[0].style.tag == "h3" && converted.blocks[1].style.tag == "div" && editor.string == "已有文字\n下一段", "现有段落前输入井号只转换当前段落")
    reset(); for character in "####### 原文" { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
    try check(editor.string == "####### 原文", "七个井号保持原文")
    reset(); for character in "* 项目" { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count)); _ = editor.performKeyEquivalent(with: key)
    try check(RichDocument.from(editor.attributedString()).blocks[0].runs.map(\.text).joined() == "项目", "列表整行加粗不把 bullet 混入正文")
}
