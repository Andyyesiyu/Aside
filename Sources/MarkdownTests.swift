import AppKit

func runMarkdownTests() throws {
    func check(_ ok: @autoclosure () -> Bool, _ label: String) throws {
        guard ok() else { throw NSError(domain: "MarkdownTests", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
        print("PASS: \(label)")
    }
    let doc = try Markdown.shared.document("# 标题\n\n* 第一项\n* **重点**\n\n> 引用\n\n[文档](https://example.com/?a=1&b=2)\n\n`code`").get()
    try check(doc.blocks.contains { $0.style.tag == "h1" } && doc.blocks.contains { !$0.style.lists.isEmpty }, "外部 CommonMark 解析器识别标题和列表")
    try check(doc.blocks.flatMap(\.runs).contains { $0.style.bold } && doc.blocks.contains { $0.style.tag == "blockquote" }, "Markdown 强调和引用转为原生富文本")
    let literal = try Markdown.shared.document("<script>alert(1)</script>").get()
    try check(literal.text.contains("<script>"), "Markdown 原始 HTML 按文字保留")
    let code = try Markdown.shared.document("```\n* 不是列表\n```").get()
    try check(code.blocks.allSatisfy { $0.style.lists.isEmpty }, "代码块中的星号不误转为列表")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("desknotes-markdown-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try NoteStore(directory: directory), owner = AppDelegate(store: try NoteStore(directory: directory.appendingPathComponent("owner")))
    owner.syncEnabled = false
    let note = Note(); owner.store.book.notes = [note]
    let card = NoteCard(note: note, owner: owner)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = card; card.frame = window.contentLayoutRect; card.layoutSubtreeIfNeeded()
    let editor = card.editor
    for char in "* xxx" { editor.insertText(String(char), replacementRange: editor.selectedRange()) }
    try check(editor.string == "• xxx", "输入星号和空格后立即显示 bullet，无需重开")
    try check(owner.store.note(note.id)?.effectiveDocument.blocks.first?.style.lists.last?.tag == "ul", "实时编辑同步保存列表结构")
    editor.insertNewline(nil)
    try check(editor.string == "• xxx\n• ", "即时列表回车继续下一项")
    editor.insertNewline(nil)
    try check(RichDocument.from(editor.attributedString()).blocks.last?.style.lists.isEmpty == true, "空列表项回车退出")
    try owner.store.flush()
    let reopened = try NoteStore(directory: owner.store.directory)
    try check(reopened.note(note.id)?.effectiveDocument == owner.store.note(note.id)?.effectiveDocument, "列表重开前后结构一致")
    editor.textStorage?.setAttributedString(RichDocument(text: "").attributed())
    editor.typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: BlockStyle())
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    for char in "**重点**" { editor.insertText(String(char), replacementRange: editor.selectedRange()) }
    try check(editor.string == "重点" && RichDocument.from(editor.attributedString()).blocks.flatMap(\.runs).contains { $0.style.bold }, "输入强调符号即时转换且可继续原生编辑")
    editor.textStorage?.setAttributedString(RichDocument(text: "*").attributed())
    editor.typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: BlockStyle())
    editor.setSelectedRange(NSRange(location: 1, length: 0)); editor.undoManager?.removeAllActions()
    editor.insertText(" ", replacementRange: editor.selectedRange())
    editor.undoManager?.undo()
    try check((editor.string == "*" || editor.string == "* ") && RichDocument.from(editor.attributedString()).blocks.allSatisfy { $0.style.lists.isEmpty }, "撤销自动转换恢复字面输入: \(editor.string.debugDescription)")
    editor.undoManager?.redo()
    try check(editor.string == "• ", "重做恢复项目列表且不重复转换: \(editor.string.debugDescription)")
    let mixed = try RichDocument.parseNotes("<div>0913</div><ul><li>Router 模式比较详细的指标建立，拆分漏斗</li></ul><div><br></div><div>后续内容</div>").get().canonical
    func setupMixed(inheritList: Bool) {
        editor.textStorage?.setAttributedString(mixed.attributed())
        let insertion = (editor.string as NSString).range(of: "\n\n").location + 1
        editor.setSelectedRange(NSRange(location: insertion, length: 0))
        editor.typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: inheritList ? mixed.blocks[1].style : BlockStyle())
        editor.undoManager?.removeAllActions()
    }
    for inherited in [false, true] {
        setupMixed(inheritList: inherited)
        for char in "* Auto 模式的指标建设需要看一看" { editor.insertText(String(char), replacementRange: editor.selectedRange()) }
        try check(editor.string == "0913\n• Router 模式比较详细的指标建立，拆分漏斗\n• Auto 模式的指标建设需要看一看\n后续内容", "已有列表后的中间空行立即转为圆点，继承列表状态=\(inherited)")
        let actual = RichDocument.from(editor.attributedString())
        try check(actual.blocks[2].style.lists.last?.tag == "ul" && actual.blocks[3].style.lists.isEmpty, "只转换当前行，不改变后续段落")
    }
    editor.textStorage?.setAttributedString(RichDocument(text: "0913\nAuto 模式的指标建设需要看一看\n后续内容").attributed())
    editor.setSelectedRange(NSRange(location: 5, length: 0))
    editor.typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: BlockStyle())
    for char in "* " { editor.insertText(NSAttributedString(string: String(char), attributes: editor.typingAttributes), replacementRange: editor.selectedRange()) }
    try check(editor.string == "0913\n• Auto 模式的指标建设需要看一看\n后续内容", "行首已有正文时，带格式字符输入也立即转列表且保留正文")
    editor.textStorage?.setAttributedString(try RichDocument.parse("<ul><li>Router</li></ul>").get().attributed())
    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    editor.typingAttributes = editor.textStorage!.attributes(at: editor.string.utf16.count - 1, effectiveRange: nil)
    editor.insertNewline(nil)
    for char in "* Auto" { editor.insertText(String(char), replacementRange: editor.selectedRange()) }
    try check(editor.string == "• Router\n• Auto", "已有续写圆点时输入星号不残留重复标记")
    editor.textStorage?.setAttributedString(RichDocument(text: "").attributed())
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    editor.typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: BlockStyle())
    for char in "\\* literal" { editor.insertText(String(char), replacementRange: editor.selectedRange()) }
    try check(editor.string == "\\* literal", "显式转义的星号保持字面内容")
    _ = store
}
