import AppKit

func runHeadingReversalTests() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("aside-heading-reversal-\(UUID())")
    defer { try? FileManager.default.removeItem(at: path) }
    let owner = AppDelegate(store: try NoteStore(directory: path)); owner.syncEnabled = false
    let note = Note(); owner.store.book.notes = [note]
    let card = NoteCard(note: note, owner: owner), editor = card.editor
    let window = EdgePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = card; window.makeFirstResponder(editor)
    var failures: [String] = []
    func check(_ ok: Bool, _ label: String) {
        print("\(ok ? "PASS" : "FAIL"): \(label)")
        if !ok { failures.append(label) }
    }
    for level in 1...6 {
        editor.textStorage?.setAttributedString(RichDocument(text: "上一段\n标题文字").attributed())
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.typingAttributes = TypeStyle.attributes
        for character in String(repeating: "#", count: level) + " " { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.undoManager?.removeAllActions()
        editor.deleteBackward(nil)
        let body = RichDocument.from(editor.attributedString()).blocks
        check(editor.string == "上一段\n标题文字" && body.count == 2 && body[1].style.tag == "div", "第 \(level) 级标题开头退格恢复正文且不合并段落")
        check(editor.selectedRange() == NSRange(location: 4, length: 0), "第 \(level) 级标题退出后光标保留")
        check((editor.textStorage?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.pointSize == 14, "第 \(level) 级标题恢复正文字号")
        editor.undoManager?.undo()
        check(RichDocument.from(editor.attributedString()).blocks.last?.style.tag == "h\(level)", "撤销恢复第 \(level) 级标题")
        editor.undoManager?.redo()
        check(editor.string == "上一段\n标题文字" && RichDocument.from(editor.attributedString()).blocks.last?.style.tag == "div", "重做取消第 \(level) 级标题")
    }
    editor.textStorage?.setAttributedString(RichDocument(text: "标题文字").attributed())
    editor.setSelectedRange(NSRange(location: 1, length: 0)); editor.formatBlock("h2"); editor.formatBlock("div")
    let body = RichDocument.from(editor.attributedString()).blocks[0]
    check(body.style.tag == "div" && !body.runs[0].style.bold, "菜单恢复正文去除标题附加粗体")
    editor.insertText("新", replacementRange: editor.selectedRange())
    check(RichDocument.from(editor.attributedString()).blocks[0].style.tag == "div", "退出标题后继续输入保持正文")
    guard failures.isEmpty else { throw NSError(domain: "HeadingReversalTests", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "; ")]) }
}
