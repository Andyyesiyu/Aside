import AppKit

func runSyncSafetyTests() throws {
    func check(_ ok: @autoclosure () -> Bool, _ name: String) throws {
        guard ok() else { throw NSError(domain: "SyncSafetyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS: \(name)")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("desknotes-sync-safety-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try NoteStore(directory: directory)
    let controller = AppDelegate(store: store)
    let document = RichDocument(text: "测试汉字\n\n后续段落")
    let note = Note(text: document.text, remoteID: "synthetic-only", baseHTML: "<div>基线</div>", baseText: "基线", richDocument: document)
    store.book.notes = [note]
    controller.sync(note.id)
    try check(!controller.inFlight.contains(note.id) && controller.deferred[note.id] != nil, "输入尚未稳定时不发起远端写入")
    controller.syncEnabled = false; controller.deferred[note.id]?.cancel()
    let returned = RemoteNote(id: "synthetic-only", text: "测试汉\n后续段落", html: "<div>测试汉</div><div>后续段落</div>", name: "合成测试")
    controller.holdSync(note.id, returned: returned, message: syncDifferenceMessage(sent: document, returnedHTML: returned.html))
    let loaded = try NoteStore(directory: directory)
    let saved = loaded.note(note.id)!
    try check(saved.pendingSync?.sent == document && saved.pendingSync?.returnedHTML == returned.html && saved.text == document.text, "校验失败同时保存提交、回读和当前本地版本")
    try check(saved.pendingSync?.problem.contains("正文字符发生变化") == true, "实际文字变化与格式差异分别说明")
    let reopened = AppDelegate(store: loaded)
    reopened.sync(note.id)
    try check(!reopened.inFlight.contains(note.id) && reopened.deferred[note.id] == nil, "重开后保持暂停，不盲目重试")
    reopened.scheduleSync(note.id)
    try check(reopened.deferred[note.id] == nil, "暂停后的继续编辑不会触发自动覆盖")
    let correct = RemoteNote(id: "synthetic-only", text: document.text, html: document.notesHTML(), name: "合成测试")
    reopened.applyRemote(note.id, remote: correct, replaceText: false)
    try loaded.flush()
    try check(loaded.note(note.id)?.pendingSync == nil && loaded.note(note.id)?.text == document.text, "确认一致后可更新基线且保留正在编辑的本地版本")
    let altered = try RichDocument.parseNotes("<div>测试汉字</div><div>后续段落</div>").get()
    try check(altered.notesSignature != document.notesSignature, "不会为了消除报警忽略空行差异")
}
