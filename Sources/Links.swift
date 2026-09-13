import AppKit

enum NoteLinks {
    static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    static func allowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "mailto" {
            let address = url.absoluteString.dropFirst("mailto:".count).split(separator: "?", maxSplits: 1).first ?? ""
            return address.contains("@")
        }
        return ["https", "http"].contains(scheme) && !(url.host ?? "").isEmpty
    }
    static func matches(_ text: String) -> [(range: NSRange, url: URL)] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return (detector?.matches(in: text, range: range) ?? []).compactMap {
            guard let url = $0.url, allowed(url) else { return nil }
            return ($0.range, url)
        }
    }
    static func decorate(_ storage: NSTextStorage) {
        let links = matches(storage.string)
        storage.beginEditing()
        storage.removeAttribute(.link, range: NSRange(location: 0, length: storage.length))
        storage.removeAttribute(.automaticLink, range: NSRange(location: 0, length: storage.length))
        var explicit: [NSRange] = []
        storage.enumerateAttribute(.noteInline, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let style = unpacked(value, as: InlineStyle.self), let link = style.link, let url = URL(string: link) {
                storage.addAttribute(.link, value: url, range: range); explicit.append(range)
            }
        }
        for link in links where !explicit.contains(where: { NSIntersectionRange($0, link.range).length > 0 }) {
            storage.addAttribute(.link, value: link.url, range: link.range)
            storage.addAttribute(.automaticLink, value: true, range: link.range)
        }
        storage.endEditing()
    }
}

extension NoteTextView {
    func refreshLinks() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        NoteLinks.decorate(storage)
        refreshTypingStyle()
    }
    func link(at point: NSPoint) -> URL? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        layout.ensureLayout(for: container)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        return storage.attribute(.link, at: index, effectiveRange: nil) as? URL
    }
    func openLink(_ url: URL) {
        guard NoteLinks.allowed(url) else { return }
        if !openURL(url) { NSSound.beep() }
    }
    func linkMenuItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke(_:)), keyEquivalent: "")
        item.target = target; item.representedObject = target
        return item
    }
}
