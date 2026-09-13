import AppKit

func runLastLineTests() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("desknotes-last-line-\(UUID())")
    defer { try? FileManager.default.removeItem(at: path) }
    let owner = AppDelegate(store: try NoteStore(directory: path)); owner.syncEnabled = false
    let note = Note(text: (1...25).map { "第\($0)行测试文字" }.joined(separator: "\n"), height: 150)
    owner.store.book.notes = [note]
    let card = NoteCard(note: note, owner: owner)
    let window = EdgePanel(contentRect: NSRect(x: 100, y: 100, width: 280, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.contentView = card; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(card.editor)
    defer { window.orderOut(nil) }
    let editor = card.editor
    var failures: [String] = []
    func settle() {
        card.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
    }
    func verify(_ label: String) {
        settle()
        let manager = editor.layoutManager!, container = editor.textContainer!
        let contentBottom = max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY) + editor.textContainerOrigin.y
        let capacity = editor.bounds.maxY >= contentBottom + editor.textContainerInset.height - 1
        var actual = NSRange()
        let caretScreen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: &actual)
        let caret = editor.convert(window.convertFromScreen(caretScreen), from: nil)
        let visible = editor.visibleRect
        let caretVisible = caret.height > 1 && caret.minY >= visible.minY - 1 && caret.maxY <= visible.maxY + 1
        let bottomClear = (visible.maxY - caret.maxY) * card.scroll.magnification >= 23
        let ok = capacity && caretVisible && bottomClear
        print("\(ok ? "PASS" : "FAIL"): \(label); document=\(editor.bounds.height), needed=\(contentBottom + editor.textContainerInset.height), caret=\(caret.minY)...\(caret.maxY), viewport=\(visible.minY)...\(visible.maxY)")
        if !ok { failures.append(label) }
    }
    for zoom in [1.0, 1.2, 1.5, 2.0, 0.8] {
        owner.store.update(note.id) { $0.zoom = zoom }
        card.update(owner.store.note(note.id)!); settle()
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange()); settle()
        editor.insertText("末行输入", replacementRange: editor.selectedRange())
        verify("缩放 \(zoom) 的末行连续输入")
        editor.insertNewline(nil)
        verify("缩放 \(zoom) 的末尾空行")
        editor.insertText("新增最后一行", replacementRange: editor.selectedRange())
        card.update(owner.store.note(note.id)!) // Background refresh must not clip or move the active last line.
        verify("缩放 \(zoom) 输入后后台刷新")
        for character in String(repeating: "较长末行需要自动换行", count: 8) {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
        verify("缩放 \(zoom) 末行自动折行")
        editor.setMarkedText("正在拼写的中文候选", selectedRange: NSRange(location: 10, length: 0), replacementRange: editor.selectedRange())
        verify("缩放 \(zoom) 中文组合输入")
        editor.insertText("中文确认", replacementRange: editor.markedRange())
        verify("缩放 \(zoom) 中文提交")
        var normalized = owner.store.note(note.id)!.effectiveDocument
        for i in normalized.blocks.indices { for j in normalized.blocks[i].runs.indices { normalized.blocks[i].runs[j].style.css["font-family"] = "Helvetica" } }
        owner.store.update(note.id) { $0.richDocument = normalized }
        card.update(owner.store.note(note.id)!)
        verify("缩放 \(zoom) 同步返回等价文字格式")
        window.setContentSize(NSSize(width: 248, height: 130)); card.needsLayout = true
        verify("缩放 \(zoom) 末行编辑时缩小窗口")
        editor.insertText("继续输入末行", replacementRange: editor.selectedRange())
        verify("缩放 \(zoom) 重排后继续输入")
        window.setContentSize(NSSize(width: 280, height: 150)); card.needsLayout = true

    }
    owner.store.update(note.id) { $0.zoom = 1.2 }; card.update(owner.store.note(note.id)!)
    window.setContentSize(NSSize(width: 447.65234375, height: 536)); card.needsLayout = true; settle()
    editor.insertText("分数宽度末行输入", replacementRange: editor.selectedRange())
    verify("120% 缩放及非整数宽度")
    editor.scroll(NSPoint.zero); settle()
    let readingPosition = card.scroll.contentView.bounds.origin
    card.update(owner.store.note(note.id)!); settle()
    let stayed = abs(card.scroll.contentView.bounds.origin.y - readingPosition.y) < 1
    print("\(stayed ? "PASS" : "FAIL"): 后台刷新不打断手动向上阅读")
    if !stayed { failures.append("后台刷新不打断手动向上阅读") }
    let preserved = RichDocument.from(editor.attributedString()).text == owner.store.note(note.id)?.text
    print("\(preserved ? "PASS" : "FAIL"): 末行修复不丢失或合并原文")
    if !preserved { failures.append("末行修复不丢失或合并原文") }
    guard failures.isEmpty else { throw NSError(domain: "LastLineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "; ")]) }
}
