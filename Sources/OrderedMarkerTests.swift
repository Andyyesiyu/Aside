import AppKit

func runOrderedMarkerTests() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aside-marker-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = AppDelegate(store: try NoteStore(directory: directory)); owner.syncEnabled = false
    let doc = try RichDocument.parse("<ol><li>Alpha</li><li>Beta</li><li>Gamma</li></ol>").get().canonical
    let note = Note(text: doc.text, richDocument: doc); owner.store.book.notes = [note]
    let card = NoteCard(note: note, owner: owner), editor = card.editor
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = card
    var failures: [String] = []
    func check(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL"): \(name)")
        if !condition { failures.append(name) }
    }
    func reset() {
        owner.store.update(note.id) { $0.richDocument = doc; $0.text = doc.text }
        card.update(owner.store.note(note.id)!)
    }
    func refreshUnchanged(_ label: String) {
        let text = editor.string, selection = editor.selectedRange()
        check(owner.store.note(note.id)!.text == text, label + " 保存与输入一致")
        card.update(owner.store.note(note.id)!)
        check(editor.string == text && editor.selectedRange() == selection, label + " 刷新不改序号或光标")
    }
    // Replacing just the number keeps the generated marker's paragraph metadata.
    let number = (editor.string as NSString).range(of: "2. ").location
    editor.setSelectedRange(NSRange(location: number, length: 1))
    editor.insertText("9", replacementRange: editor.selectedRange())
    refreshUnchanged("修改中间序号")
    reset()
    editor.setSelectedRange(NSRange(location: number + 1, length: 0)); editor.deleteBackward(nil)
    refreshUnchanged("删除序号数字")
    editor.insertText("12", replacementRange: editor.selectedRange())
    refreshUnchanged("重新输入两位序号")
    reset()
    editor.setSelectedRange(NSRange(location: number, length: 3)); editor.deleteBackward(nil)
    refreshUnchanged("删除完整编号前缀")
    check(editor.string == "1. Alpha\nBeta\n3. Gamma", "删除编号不吞正文或重编后项")
    editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "Beta").location + 4, length: 0))
    editor.typingAttributes = editor.textStorage!.attributes(at: editor.selectedRange().location - 1, effectiveRange: nil)
    editor.insertNewline(nil)
    check(editor.string == "1. Alpha\nBeta\n\n3. Gamma", "移除编号后回车不恢复列表")
    refreshUnchanged("移除编号后回车")
    try owner.store.flush()
    let loaded = try NoteStore(directory: directory)
    check(loaded.note(note.id)?.text == editor.string, "编号修改保存重开一致")
    guard failures.isEmpty else { throw NSError(domain: "OrderedMarkerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "; ")]) }
}
