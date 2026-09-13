import AppKit

func runLinkTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NSError(domain: "LinksTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: \(message)")
    }
    let text = "进度📝 https://example.com/path?q=1&x=2\n联系 test@example.com"
    let links = NoteLinks.matches(text)
    try check(links.count == 2, "识别中英文混排网址和邮箱")
    try check((text as NSString).substring(with: links[0].range) == "https://example.com/path?q=1&x=2", "中文与 emoji 后的 UTF-16 链接范围")
    try check(links[0].url.query == "q=1&x=2" && links[1].url.scheme == "mailto", "保留查询参数与邮箱目标")
    try check(!NoteLinks.allowed(URL(string: "javascript:alert(1)")!) && !NoteLinks.allowed(URL(string: "file:///tmp/example")!), "非网页或邮箱地址不作为可执行链接")
    let stored = NSTextStorage(string: text, attributes: TypeStyle.attributes)
    NoteLinks.decorate(stored)
    try check(stored.string == text, "链接装饰不改变原始正文")
    try check((stored.attribute(.font, at: links[0].range.location, effectiveRange: nil) as? NSFont)?.pointSize == 14, "链接保留 14 字号")
    stored.replaceCharacters(in: NSRange(location: 0, length: stored.length), with: "现在没有链接")
    NoteLinks.decorate(stored)
    try check(stored.attribute(.link, at: 0, effectiveRange: nil) == nil, "删除网址后清除过期链接属性")

    let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let window = NSWindow(contentRect: editor.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = editor
    editor.isRichText = false
    editor.textStorage?.setAttributedString(NSAttributedString(string: "https://example.com\n普通正文", attributes: TypeStyle.attributes))
    editor.refreshLinks()
    let url = URL(string: "https://example.com")!
    var opened: [URL] = []
    editor.openURL = { opened.append($0); return true }
    editor.clicked(onLink: url, at: 0)
    try check(opened == [url], "原生链接激活传递完整地址（测试替身不打开浏览器）")
    guard let manager = editor.layoutManager, let container = editor.textContainer else { fatalError("Missing TextKit") }
    manager.ensureLayout(for: container)
    let rect = manager.boundingRect(forGlyphRange: NSRange(location: 3, length: 1), in: container)
    let point = NSPoint(x: rect.midX + editor.textContainerOrigin.x, y: rect.midY + editor.textContainerOrigin.y)
    try check(editor.link(at: point) == url, "链接字形点击命中")
    try check(editor.link(at: NSPoint(x: 390, y: point.y)) == nil, "行尾空白区域不误打开链接")
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: editor.convert(point, to: nil), modifierFlags: .command,
                                  timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    editor.mouseDown(with: event)
    try check(opened == [url, url], "Command 点击沿真实编辑器事件处理打开链接")
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    editor.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "前缀 ")
    editor.didChangeText()
    try check(editor.string.hasPrefix("前缀 https://") && editor.textStorage?.attribute(.link, at: 3, effectiveRange: nil) != nil, "编辑后链接范围重新定位")
    try check(editor.typingAttributes[.link] == nil, "普通输入不继承链接属性")
    editor.setMarkedText("拼音输入", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: 0, length: 0))
    let composition = editor.string
    editor.refreshLinks()
    try check(editor.hasMarkedText() && editor.string == composition, "链接识别不打断输入法组合文本")
    editor.unmarkText()
    try check(!editor.hasMarkedText(), "输入法提交后恢复链接识别")
}
