import AppKit

func runSizingTests() throws {
    func check(_ ok: @autoclosure () -> Bool, _ message: String) throws {
        guard ok() else { throw NSError(domain: "SizingTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: \(message)")
    }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNotes-sizing-\(UUID())")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try NoteStore(directory: path)
    let a = Note(text: "宽高测试 A"), b = Note(text: "宽高测试 B")
    store.book.notes = [a, b]
    let controller = AppDelegate(store: store)
    controller.panel = EdgePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    controller.resizeCard(a.id, size: NSSize(width: 410, height: 320))
    try check(store.note(a.id)?.width == 410 && store.note(a.id)?.height == 320 && store.note(b.id)?.width == nil, "每张便笺独立调整宽高")
    try check(controller.cards[a.id]?.frame.maxX == controller.cards[b.id]?.frame.maxX, "不同宽度便笺仍沿停靠边对齐")
    try store.flush()
    let reopened = try NoteStore(directory: path)
    try check(reopened.note(a.id)?.width == 410 && reopened.note(a.id)?.height == 320, "自定义宽高重开后恢复")
    let encoded = try JSONEncoder().encode(a)
    let legacy = try JSONDecoder().decode(Note.self, from: encoded)
    try check(legacy.width == nil && NoteSizing.width(legacy, defaultWidth: 280, screenWidth: 1440) == 280, "旧便笺使用默认宽度")
    let initial = NSSize(width: 280, height: 250)
    let start = NSPoint(x: 100, y: 500)
    try check(NoteSizing.dragged(initial: initial, start: start, current: NSPoint(x: 50, y: 450), side: "right") == NSSize(width: 330, height: 300), "右侧停靠从左下角向内拉宽")
    try check(NoteSizing.dragged(initial: initial, start: start, current: NSPoint(x: 150, y: 450), side: "left") == NSSize(width: 330, height: 300), "左侧停靠从右下角向内拉宽")
    try check(NoteSizing.dragged(initial: initial, start: start, current: NSPoint(x: 5000, y: -5000), side: "left") == NSSize(width: 640, height: 600), "拖动尺寸上限")
    let plain = "<div><span style=\"font-size: 9px\">测试</span><span style=\"font-size: 9px\"> text</span></div>"
    try check(simpleHTML(plain) && plainNoteFormat(plain)?.fontSize == "9px", "识别备忘录自动生成的统一字号 span")
    try check(noteHTML("新内容", fontSize: plainNoteFormat(plain)?.fontSize).contains("font-size: 9px"), "回写保留备忘录原有统一字号")
    try check(!simpleHTML(plain + "<div><span style=\"font-size: 20px\">大标题</span></div>"), "混合字号仍保护为只读")
    try check(!simpleHTML("<div><span style=\"font-weight: bold\">加粗</span></div>") && !simpleHTML("<table><tr><td>表格</td></tr></table>"), "复杂格式与表格不转成纯文本覆盖")
    controller.panel.orderOut(nil)
}
