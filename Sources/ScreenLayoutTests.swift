import AppKit

func runScreenLayoutTests() throws {
    func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
        guard value() else { throw NSError(domain: "ScreenLayoutTests", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS: \(name)")
    }
    let main = ScreenRegion(id: "laptop", frame: NSRect(x: 0, y: 0, width: 1440, height: 875))
    let left = ScreenRegion(id: "external", frame: NSRect(x: -1920, y: -200, width: 1920, height: 1080))
    let top = ScreenRegion(id: "portrait", frame: NSRect(x: 100, y: 900, width: 1080, height: 1920))
    let screens = [main, left, top]
    let size = NSSize(width: 280, height: 250)
    let frame = NSRect(x: -1700, y: 300, width: size.width, height: size.height)
    let anchor = ScreenLayout.anchor(frame: frame, screens: screens)!
    let position = DesktopPosition(x: frame.minX, y: frame.maxY)
    try check(anchor.screenID == "external" && anchor.left == 220 && anchor.top == 330, "负坐标显示器保存屏幕身份和屏内位置")
    try check(ScreenLayout.restored(position: position, anchor: anchor, size: size, screens: screens) == frame, "多屏保存位置准确恢复")
    let moved = ScreenRegion(id: "external", frame: NSRect(x: 1440, y: 100, width: 1920, height: 1080))
    let reordered = ScreenLayout.restored(position: position, anchor: anchor, size: size, screens: [moved, main])
    try check(reordered.minX == 1660 && reordered.maxY == 850, "屏幕由左改右及主屏顺序变化后仍按身份定位")
    let disconnected = ScreenLayout.restored(position: position, anchor: anchor, size: size, screens: [main])
    try check(main.frame.contains(disconnected), "拔掉外接屏时便笺回到可见范围")
    try check(ScreenLayout.restored(position: position, anchor: anchor, size: size, screens: screens) == frame, "重新接屏可恢复原位置且不被临时回退覆盖")
    let above = NSRect(x: 200, y: 1800, width: 400, height: 500)
    let upperAnchor = ScreenLayout.anchor(frame: above, screens: screens)!
    try check(upperAnchor.screenID == "portrait" && ScreenLayout.restored(position: DesktopPosition(x: 200, y: 2300), anchor: upperAnchor, size: above.size, screens: screens) == above, "支持上下排列与竖屏")
    let tiny = ScreenRegion(id: "external", frame: NSRect(x: 1440, y: 0, width: 800, height: 500))
    let resized = ScreenLayout.restored(position: position, anchor: anchor, size: NSSize(width: 640, height: 600), screens: [main, tiny])
    try check(tiny.frame.contains(resized), "缩放或分辨率降低后整张便笺仍可操作")
    let boundary = NSRect(x: -100, y: 300, width: 280, height: 250)
    try check(ScreenLayout.anchor(frame: boundary, screens: [main, left])?.screenID == "laptop", "松手时按主要覆盖面积选择显示器")
    try check(ScreenLayout.closest(to: NSRect(x: 1500, y: 10, width: 280, height: 250), screens: [left, main])?.id == "laptop", "完全离屏时按距离找最近屏幕而非枚举顺序")
    let reloaded = try JSONDecoder().decode(ScreenAnchor.self, from: JSONEncoder().encode(anchor))
    try check(reloaded == anchor, "屏幕锚点可持久保存")
    let oldNote = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(Note(text: "旧便笺")))
    try check(oldNote.screenAnchor == nil, "旧数据无屏幕锚点仍兼容")
}
