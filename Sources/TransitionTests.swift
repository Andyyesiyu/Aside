import AppKit
import QuartzCore

func runTransitionTests() throws {
    func check(_ ok: @autoclosure () -> Bool, _ message: String) throws {
        guard ok() else { throw NSError(domain: "TransitionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: \(message)")
    }
    func tick(_ seconds: Double) {
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    let panel = EdgePanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    let host = NSView(frame: panel.frame)
    let content = NSView(frame: host.bounds)
    host.addSubview(content); panel.contentView = host
    let transition = PanelTransition(panel: panel, content: content)
    transition.reduceMotion = { false }
    defer { panel.orderOut(nil) }
    transition.setVisible(false)
    try check(!panel.isVisible, "动画控制器启动时保持隐藏")
    transition.setVisible(true)
    let first = content.layer!.animation(forKey: "edgeVisibility")!
    try check(panel.isVisible && !panel.isKeyWindow && transition.isRunning, "展开动画已启动且不抢焦点")
    transition.setVisible(true)
    let same = content.layer!.animation(forKey: "edgeVisibility")!
    try check((first.value(forKey: "generation") as? Int) == (same.value(forKey: "generation") as? Int), "重复刷新不重启动画")
    tick(0.35)
    try check(panel.isVisible && !transition.isRunning && content.layer!.opacity == 1, "展开完成后稳定显示")
    transition.setVisible(false)
    let closing = content.layer!.animation(forKey: "edgeVisibility")!
    try check(panel.isVisible && transition.isRunning, "收起动画期间窗口仍然可见")
    tick(0.07)
    let current = content.layer!.presentation()?.opacity
    transition.setVisible(true)
    let reversed = content.layer!.animation(forKey: "edgeVisibility") as! CAAnimationGroup
    let fade = reversed.animations![0] as! CABasicAnimation
    if let current = current, let start = fade.fromValue as? Float {
        try check(abs(start - current) < 0.15, "反向展开沿用当前透明度")
    }
    transition.animationDidStop(closing, finished: true)
    try check(panel.isVisible && transition.targetVisible && transition.isRunning, "旧收起回调不关闭重新展开的窗口")
    tick(0.35)
    try check(panel.isVisible && !transition.isRunning, "快速反向后稳定展开")
    transition.setVisible(false)
    tick(0.50)
    try check(!panel.isVisible && !transition.isRunning, "淡出结束后才隐藏窗口")
    transition.reduceMotion = { true }
    transition.setVisible(true)
    let reduced = content.layer!.animation(forKey: "edgeVisibility") as! CAAnimationGroup
    let slide = reduced.animations![1] as! CABasicAnimation
    try check((slide.fromValue as? CGFloat) == 0 && (slide.toValue as? CGFloat) == 0, "减少动态效果时只淡入淡出")
    transition.setVisible(false, animated: false)
    try check(!panel.isVisible && !transition.isRunning && content.layer!.animation(forKey: "edgeVisibility") == nil, "空面板可立即取消动画并隐藏")
}
