import AppKit

struct ScreenRegion {
    var id: String
    var frame: NSRect
}

struct ScreenAnchor: Codable, Equatable {
    var screenID: String
    var left: Double
    var top: Double
}

enum ScreenLayout {
    static func id(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return screen.localizedName }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number.stringValue
    }
    static var current: [ScreenRegion] { NSScreen.screens.map { ScreenRegion(id: id($0), frame: $0.visibleFrame) } }
    static func anchor(frame: NSRect, screens: [ScreenRegion]) -> ScreenAnchor? {
        guard let region = closest(to: frame, screens: screens) else { return nil }
        return ScreenAnchor(screenID: region.id, left: frame.minX - region.frame.minX, top: region.frame.maxY - frame.maxY)
    }
    static func closest(to rect: NSRect, screens: [ScreenRegion]) -> ScreenRegion? {
        screens.min { a, b in
            func score(_ frame: NSRect) -> (CGFloat, CGFloat) {
                let intersection = frame.intersection(rect)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                let dx = max(frame.minX - rect.midX, 0, rect.midX - frame.maxX)
                let dy = max(frame.minY - rect.midY, 0, rect.midY - frame.maxY)
                return (-area, dx * dx + dy * dy)
            }
            let x = score(a.frame), y = score(b.frame)
            return x.0 == y.0 ? x.1 < y.1 : x.0 < y.0
        }
    }
    static func restored(position: DesktopPosition, anchor: ScreenAnchor?, size: NSSize, screens: [ScreenRegion]) -> NSRect {
        var point = position
        if let anchor = anchor, let region = screens.first(where: { $0.id == anchor.screenID }) {
            point = DesktopPosition(x: region.frame.minX + anchor.left, y: region.frame.maxY - anchor.top)
        }
        let proposed = NSRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height)
        guard let screen = closest(to: proposed, screens: screens) else { return proposed }
        return DesktopPlacement.frame(position: point, size: NSSize(width: min(size.width, screen.frame.width), height: min(size.height, screen.frame.height)), screens: [screen.frame])
    }
}
