import AppKit

func runFixedModeTests() throws {
    func check(_ condition: Bool, _ label: String) throws {
        guard condition else { throw NSError(domain: "FixedModeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
        print("PASS: \(label)")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aside-fixed-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try NoteStore(directory: directory), owner = AppDelegate(store: try NoteStore(directory: directory.appendingPathComponent("owner")))
    owner.syncEnabled = false
    var note = Note(text: "固定模式测试"); note.collapsed = true
    owner.store.book.notes = [note]; owner.store.book.preferences.collapsed = true
    owner.panel = EdgePanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 250), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    owner.edgeHandle = EdgeHandle()
    defer {
        owner.panel.orderOut(nil); owner.edgeHandle?.hide()
        owner.extraHandles.values.forEach { $0.hide() }
        owner.desktopPanels.values.forEach { $0.orderOut(nil) }
    }
    owner.setFixedMode(true)
    try check(owner.panel.isVisible && !owner.store.book.notes[0].collapsed && !owner.store.book.preferences.collapsed, "固定模式展开全部便笺")
    owner.checkAutoHide(at: NSPoint(x: -99999, y: -99999), now: 1)
    owner.checkAutoHide(at: NSPoint(x: -99999, y: -99999), now: 100)
    try check(!owner.edgeState.concealed && owner.panel.isVisible, "固定模式移出后不隐藏")
    try check(owner.edgeHandle!.makeContextMenu().items[0].state == .on, "图标右键菜单显示固定模式勾选")
    try owner.store.flush()
    let loaded = try NoteStore(directory: owner.store.directory)
    try check(loaded.book.preferences.fixedMode && !loaded.book.preferences.shouldAutoHide, "固定模式重启后保留")
    owner.setFixedMode(false)
    try check(owner.store.book.preferences.autoHide && owner.store.book.preferences.shouldAutoHide, "退出固定模式恢复原自动隐藏设置")
    try check(owner.edgeHandle!.makeContextMenu().items[0].state == .off, "退出后菜单取消勾选")
    owner.store.book.preferences.autoHide = false
    owner.setFixedMode(true); owner.setFixedMode(false)
    try check(!owner.store.book.preferences.autoHide, "原本关闭自动隐藏的偏好不被覆盖")
    owner.toggleFixedPresentation()
    try check(owner.store.book.preferences.fixedMode && owner.panel.isVisible, "Cmd 点击固定展开全部")
    owner.toggleFixedPresentation()
    try check(owner.hidden && !owner.panel.isVisible && !owner.store.book.preferences.fixedMode, "再次 Cmd 点击隐藏全部并退出固定模式")
    owner.toggleFixedPresentation()
    try check(!owner.hidden && owner.panel.isVisible && owner.store.book.preferences.fixedMode, "隐藏后 Cmd 点击可再次展开")
    let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    try check(!legacy.fixedMode && legacy.shouldAutoHide, "旧版数据默认不开启固定模式")
    _ = store
}
