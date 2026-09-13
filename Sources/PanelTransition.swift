import AppKit
import QuartzCore

/// Animate the composited content, keeping the window frame and text layout stable.
final class PanelTransition: NSObject, CAAnimationDelegate {
    weak var panel: NSPanel?
    weak var content: NSView?
    private(set) var targetVisible = false
    private(set) var isRunning = false
    private var generation = 0
    var side = "right"
    var slideDistance: CGFloat = 28
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(panel: NSPanel, content: NSView) {
        self.panel = panel; self.content = content
        super.init()
        content.wantsLayer = true
        content.layer?.opacity = 0
    }
    func setVisible(_ visible: Bool, animated: Bool = true) {
        guard let panel = panel, let layer = content?.layer else { return }
        guard visible != targetVisible || (!visible && !animated) else { return }
        targetVisible = visible
        generation += 1
        let reduce = reduceMotion()
        let offset: CGFloat = reduce ? 0 : (side == "left" ? -slideDistance : slideDistance)
        let presentation = layer.presentation()
        let fromOpacity = panel.isVisible ? (presentation?.opacity ?? layer.opacity) : 0
        let fromX = panel.isVisible ? (presentation?.transform.m41 ?? layer.transform.m41) : offset
        let toOpacity: Float = visible ? 1 : 0
        let toX: CGFloat = visible ? 0 : offset
        layer.removeAnimation(forKey: "edgeVisibility")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = toOpacity
        layer.transform = CATransform3DMakeTranslation(toX, 0, 0)
        CATransaction.commit()
        guard animated && (panel.isVisible || visible) else {
            isRunning = false
            if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity; fade.toValue = toOpacity
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = fromX; slide.toValue = toX
        let group = CAAnimationGroup()
        group.animations = [fade, slide]
        // Shorten a reversal according to the remaining distance, without a sudden snap.
        let remaining = Double(abs(toOpacity - fromOpacity))
        group.duration = reduce ? 0.12 : max(0.10, (visible ? 0.24 : 0.20) * remaining)
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.75, 0.25, 1)
        group.delegate = self
        group.setValue(generation, forKey: "generation")
        isRunning = true
        layer.add(group, forKey: "edgeVisibility")
        if visible && !panel.isVisible { panel.orderFrontRegardless() }
    }
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag, (anim.value(forKey: "generation") as? Int) == generation else { return }
        isRunning = false
        if !targetVisible { panel?.orderOut(nil) }
    }
}
