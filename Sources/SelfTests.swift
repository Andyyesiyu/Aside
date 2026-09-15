import AppKit
import CoreText

func runSelfTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        if !condition() { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
        print("PASS: \(label)")
    }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("DeskNotes-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try NoteStore(directory: path)
    let note = Note(text: "英文 Geneva\n中文进度与上下文 <>&\n下一步", color: "green", collapsed: true, archived: true)
    store.book.notes = [note]; store.book.preferences.side = "left"; try store.flush()
    let reopened = try NoteStore(directory: path)
    try check(reopened.book.notes == [note] && reopened.book.preferences.side == "left", "保存、重新打开、中文、折叠与归档")
    store.book.notes[0].text = "第二版"; try store.flush()
    try Data("broken".utf8).write(to: store.file)
    let recovered = try NoteStore(directory: path)
    try check(recovered.book.notes == [note] && recovered.loadMessage != nil, "损坏文件恢复有效备份")
    try check(simpleHTML("<div>Hello<br></div>"), "纯文本备忘录可同步")
    try check(!simpleHTML("<div><b>标题</b><img src='x'></div>"), "复杂备忘录保护")
    try check(noteHTML("<>&\n\"hi\"") == "<div>&lt;&gt;&amp;</div><div>&quot;hi&quot;</div>", "HTML 特殊字符安全转义")
    for (local, html, readonly, expected) in [("base", "html", false, SyncDecision.unchanged), ("edit", "html", false, .push), ("base", "new", false, .pull), ("edit", "new", false, .conflict), ("base", "new", true, .pull), ("edit", "html", true, .readOnly)] {
        try check(decideSync(local: local, baseline: "base", remoteHTML: html, baselineHTML: "html", readOnly: readonly) == expected, "同步分支 \(expected)")
    }
    try check(!TypeStyle.fusionName.isEmpty, "Fusion Pixel 字体已打包注册")
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Geneva 中文记录", attributes: TypeStyle.attributes))
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    let fonts = runs.map { (CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont }
    let names = fonts.map { CTFontCopyPostScriptName($0) as String }
    print("FONT RUNS: \(names.joined(separator: ", "))")
    try check(names.contains(where: { $0.lowercased().contains("geneva") }), "英文使用 Geneva")
    try check(names.contains(TypeStyle.fusionName), "中文使用 Fusion Pixel")
    try check(fonts.allSatisfy { CTFontGetSize($0) == 14 }, "全部正文使用 14 字号")
    let legacy = Data(#"{"side":"right","width":280,"allSpaces":true,"floatOnTop":true,"collapsed":false}"#.utf8)
    let migrated = try JSONDecoder().decode(Preferences.self, from: legacy)
    try check(migrated.autoHide, "旧设置兼容并默认启用自动隐藏")
    var disabled = migrated; disabled.autoHide = false
    let encoded = try JSONEncoder().encode(disabled)
    let decoded = try JSONDecoder().decode(Preferences.self, from: encoded)
    try check(!decoded.autoHide, "自动隐藏开关保存恢复")
    var edge = EdgeReveal()
    edge.update(inside: true, keepOpen: false, now: 0)
    try check(edge.concealed, "鼠标经过隐藏面板区域不会展开")
    edge.concealed = false
    edge.update(inside: false, keepOpen: false, now: 1)
    edge.update(inside: false, keepOpen: false, now: 1.2)
    try check(!edge.concealed, "展开后仍保留收起延迟")
    edge.update(inside: true, keepOpen: false, now: 1.6)
    edge.update(inside: false, keepOpen: true, now: 5)
    try check(!edge.concealed && edge.outsideSince == nil, "进入面板和编辑期间保持展开")
    edge.update(inside: false, keepOpen: false, now: 6)
    edge.update(inside: false, keepOpen: false, now: 6.7)
    try check(edge.concealed, "离开后自动收起")
    edge.update(inside: true, keepOpen: false, now: 8)
    try check(edge.concealed, "收起过程中鼠标返回也不会重新弹出")
    let controller = AppDelegate(store: store)
    store.book.notes = [Note(text: "窗口自动隐藏测试")]
    controller.panel = EdgePanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 250), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    controller.updateVisibility()
    try check(!controller.panel.isVisible, "启动窗口默认隐藏")
    controller.openFromHandle()
    try check(controller.panel.isVisible && !controller.panel.isKeyWindow, "点击图标展示原生窗口且不抢焦点")
    controller.edgeState.concealed = true
    controller.refresh()
    try check(!controller.panel.isVisible, "同步刷新不唤醒已收起窗口")
    store.book.preferences.autoHide = false
    controller.updateVisibility()
    try check(controller.panel.isVisible, "关闭自动隐藏恢复常驻显示")
    controller.panel.orderOut(nil)
    try runLinkTests()
    try runTransitionTests()
    try runSizingTests()
    try runResizeShortcutTests()
    try runLastLineTests()
    try runDesktopNotesTests()
    try runScreenLayoutTests()
    try runHandleDragTests()
    try runRichTests()
    try runMarkdownTests()
    try runHeadingTests()
    try runSyncSafetyTests()
    try runListIndentTests()
    try runOrderedMarkerTests()
    print("ALL TESTS PASSED")
}
