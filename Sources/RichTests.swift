import AppKit

func runRichTests() throws {
    func check(_ ok: @autoclosure () -> Bool, _ name: String) throws {
        if !ok() { throw NSError(domain: "RichTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS: \(name)")
    }
    let html = "<h1>标题📝</h1><div><b>粗体</b> <i>斜体</i> <u>下划线</u> <s>删除</s> <a href=\"https://example.com/path?a=1&amp;b=2\">项目文档</a></div><ul><li>事项一<ul><li>子项</li></ul></li><li>事项二</li></ul><ol start=\"3\"><li>步骤三</li><li>步骤四</li></ol><blockquote>引用</blockquote>"
    let doc = try RichDocument.parse(html).get().canonical
    let decoded = try RichDocument.parse(doc.html()).get().canonical
    try check(doc == decoded, "标题、行内格式、嵌套列表、编号和引用往返保留")
    try check(doc.blocks[0].style.tag == "h1" && doc.text.contains("3. 步骤三"), "标题层级与编号起点保留")
    let spans = doc.blocks.flatMap(\.runs)
    try check(spans.contains { $0.text == "项目文档" && $0.style.link == "https://example.com/path?a=1&b=2" }, "自定义链接文字与完整目标保留")
    try check(!RichDocument.supported("<div>图<img src=\"https://example.com/image.png\"></div>") && !RichDocument.supported("<table><tr><td>表</td></tr></table>"), "图片和表格不会进入有损回写路径")
    try check(!RichDocument.supported("<div style=\"background-image:url(https://example.com/image)\">X</div>"), "解析不加载外部资源")
    let mixed = try RichDocument.parse("<h2><span style=\"font-size: 20px\">小标题</span></h2><div><span style=\"font-size: 9px\">正文</span></div>").get().canonical
    let mixedAgain = try RichDocument.parse(mixed.html()).get().canonical
    try check(mixedAgain == mixed, "混合字号随原文格式回写")
    try check(RichDocument.notesIssue("<div><u>文档名称</u></div>") != nil, "缺失目标的潜在链接阻止回写")
    try check(doc.notesWriteIssue != nil, "本地富文本不等同于备忘录安全回写范围")
    try check(RichDocument.notesIssue("<ol start=\"3\"><li>项</li></ol>") != nil, "未验证的编号起点阻止回写")
    try check(RichDocument.notesIssue("<ul><li>项</li></ul><ol><li>步骤</li></ol>") != nil, "会被合并的相邻列表阻止回写")
    let notesHeading = try RichDocument.parse("<div><b><span style=\"font-size: 16px\">标题</span></b></div>").get()
    try check(notesHeading.notesHTML().contains("<h1>"), "备忘录标题字号恢复为可回写的标题样式")
    let legacyURL = try RichDocument.parse("<div>https://example.com/?a=1&ampb=2</div>").get()
    try check(legacyURL.text == "https://example.com/?a=1&b=2", "备忘录省略实体分号时保留 URL 参数")
    let wrapped = try RichDocument.parse("<div><h1>标题</h1><div>正文</div></div>").get()
    try check(wrapped.blocks.count == 2, "段落包装不引入额外空行")
    let corrupted = RichDocument(text: "被改变的文字")
    try check(notesHeading.notesSignature != corrupted.notesSignature, "回读核对检测文字及格式变化")
    let padded = try RichDocument.parseNotes("<div>正文<br></div><div>第二行</div>").get()
    try check(padded.text == "正文\n第二行", "备忘录段尾占位换行不会变成正文空行")
    let softBreak = try RichDocument.parseNotes("<div>第一行<br>第二行<br></div>").get()
    try check(softBreak.text == "第一行\u{2028}第二行", "内部软换行保持不变")
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    let editor = NoteTextView(frame: window.contentLayoutRect)
    editor.richEditing = true; editor.isRichText = true; editor.allowsUndo = true
    window.contentView = editor
    editor.textStorage?.setAttributedString(doc.attributed()); editor.refreshLinks()
    let linkRange = (editor.string as NSString).range(of: "项目文档")
    try check((editor.textStorage?.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL)?.query == "a=1&b=2", "自动识别不抹掉富文本链接")
    let boldRange = (editor.string as NSString).range(of: "粗体")
    editor.setSelectedRange(boldRange)
    editor.typingAttributes = editor.textStorage!.attributes(at: boldRange.location, effectiveRange: nil)
    editor.insertText("改后的粗体", replacementRange: boldRange)
    let edited = RichDocument.from(editor.attributedString()).canonical
    try check(edited.blocks.flatMap(\.runs).contains { $0.text.contains("改后的粗体") && $0.style.bold }, "原生编辑保留所在文字格式")
    let modifiedRange = (editor.string as NSString).range(of: "改后的粗体")
    editor.setSelectedRange(modifiedRange)
    editor.undoManager?.removeAllActions()
    let textBefore = editor.string
    editor.formatInline(\.underline)
    let formatted = RichDocument.from(editor.attributedString()).canonical
    try check(editor.string == textBefore && formatted != edited && formatted.blocks.flatMap(\.runs).contains { $0.text.contains("改后的粗体") && $0.style.bold && $0.style.underline }, "仅修改格式可被识别并保留正文")
    editor.undoManager?.undo()
    try check(RichDocument.from(editor.attributedString()).canonical == edited, "格式修改支持撤销")
    let data = try JSONEncoder().encode(Note(text: formatted.text, richDocument: formatted, baseRichDocument: edited))
    let restored = try JSONDecoder().decode(Note.self, from: data)
    try check(restored.richDocument == formatted && restored.baseRichDocument == edited, "富文本与同步基线保存恢复")
    let legacy = Note(text: "粗体", remoteID: "test", baseHTML: "<div><b>粗体</b></div>", baseText: "粗体", readOnly: true)
    try check(!legacy.effectiveReadOnly && legacy.effectiveDocument.blocks[0].runs[0].style.bold, "旧版只读关联笔记自动解锁已支持格式")
    let list = try RichDocument.parse("<ol><li>第一项</li></ol>").get().canonical
    editor.textStorage?.setAttributedString(list.attributed())
    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    editor.typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: list.blocks[0].style)
    editor.insertNewline(nil)
    try check(editor.string == "1. 第一项\n2. ", "回车续写编号列表")
    editor.insertNewline(nil)
    try check(RichDocument.from(editor.attributedString()).blocks.last?.style.lists.isEmpty == true, "空列表项回车退出列表")
}
