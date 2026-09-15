import AppKit

func runHandleDragTests() throws {
    func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
        guard value() else { throw NSError(domain: "HandleDragTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS: \(name)")
    }
    let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 44, height: 48), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let button = EdgeHandleButton(frame: NSRect(x: 0, y: 0, width: 44, height: 48))
    window.contentView = button
    defer { window.orderOut(nil) }
    var clicks = 0, drops = 0
    var delta: CGFloat = 0
    let target = MenuAction { clicks += 1 }
    button.target = target; button.action = #selector(MenuAction.invoke(_:))
    button.onDrag = { delta = $0 }; button.onDrop = { drops += 1 }
    func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    button.mouseDown(with: event(.leftMouseDown, 20, 20))
    button.mouseUp(with: event(.leftMouseUp, 20, 20))
    try check(clicks == 1 && drops == 0, "图标单击仍打开便笺")
    button.mouseDown(with: event(.leftMouseDown, 20, 20))
    button.mouseDragged(with: event(.leftMouseDragged, 21, 22))
    button.mouseUp(with: event(.leftMouseUp, 21, 22))
    try check(clicks == 2 && drops == 0, "轻微手抖仍按单击处理")
    button.mouseDown(with: event(.leftMouseDown, 20, 20))
    button.mouseDragged(with: event(.leftMouseDragged, 20, 100))
    button.mouseUp(with: event(.leftMouseUp, 20, 100))
    try check(clicks == 2 && drops == 1 && delta == 80 && !button.dragging, "拖动图标记录位移且松手不误展开")
    var commandClicks = 0
    button.onCommandClick = { commandClicks += 1 }
    button.mouseDown(with: event(.leftMouseDown, 20, 20, .command))
    button.mouseUp(with: event(.leftMouseUp, 20, 20))
    try check(commandClicks == 1 && clicks == 2, "Cmd 点击单独触发，不执行普通打开")
    button.mouseDown(with: event(.leftMouseDown, 20, 20, .command))
    button.mouseDragged(with: event(.leftMouseDragged, 20, 100, .command))
    button.mouseUp(with: event(.leftMouseUp, 20, 100, .command))
    try check(commandClicks == 1 && drops == 2, "Cmd 拖动不误触发显示切换")
    button.mouseDown(with: event(.leftMouseDown, 20, 20))
    button.mouseUp(with: event(.leftMouseUp, 20, 20))
    try check(clicks == 3 && commandClicks == 1, "Cmd 点击后普通点击正常")
    let screen = NSRect(x: -1920, y: -300, width: 1920, height: 1080)
    try check(HandlePlacement.clampedY(-9999, screen: screen) == screen.minY && HandlePlacement.clampedY(9999, screen: screen) == screen.maxY - 48, "图标无法拖出屏幕上下边界")
    let y = HandlePlacement.y(position: 0.4, screen: screen)
    try check(abs(HandlePlacement.ratio(y: y, screen: screen) - 0.4) < 0.0001, "多屏负坐标位置换算准确")
    var prefs = Preferences(); prefs.handlePositions = ["one": 0.2, "two": 0.8]
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
    try check(restored.handlePositions == prefs.handlePositions, "各屏幕图标位置分别保存恢复")
    let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    try check(legacy.handlePositions.isEmpty && HandlePlacement.y(position: nil, screen: screen) == screen.maxY - screen.height * 0.25 - 24, "旧设置保留原图标默认位置")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("handle-hover-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = AppDelegate(store: try NoteStore(directory: directory)); owner.syncEnabled = false
    owner.store.book.notes = [Note(text: "合成入口测试")]
    owner.panel = EdgePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    owner.edgeHandle = EdgeHandle()
    owner.store.book.preferences.handlePositions[owner.screenID(owner.selectedScreen()!)] = 0.1
    owner.refresh()
    defer { owner.panel.orderOut(nil); owner.edgeHandle?.hide(); owner.extraHandles.values.forEach { $0.hide() } }
    let actualScreen = owner.selectedScreen()!.visibleFrame
    let handlePoint = NSPoint(x: actualScreen.maxX - 22, y: HandlePlacement.y(position: 0.1, screen: actualScreen) + 24)
    owner.openFromHandle()
    try check(!owner.panel.frame.insetBy(dx: -10, dy: -10).contains(handlePoint), "测试图标已移到便笺区域之外")
    owner.checkAutoHide(at: handlePoint, now: 1)
    owner.checkAutoHide(at: handlePoint, now: 3)
    try check(!owner.edgeState.concealed, "点击展开后停在图标原位置不会立即收起")
    let outside = NSPoint(x: -99999, y: -99999)
    owner.checkAutoHide(at: outside, now: 4)
    owner.checkAutoHide(at: outside, now: 4.4)
    try check(!owner.edgeState.concealed, "离开图标后留出移向便笺的时间")
    owner.checkAutoHide(at: outside, now: 4.7)
    try check(owner.edgeState.concealed, "超过新延迟后仍正常自动收起")
    owner.checkAutoHide(at: handlePoint, now: 5)
    try check(owner.edgeState.concealed, "图标区域只保持已展开状态，不恢复悬停误展开")

}
