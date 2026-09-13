import AppKit

extension NoteTextView {
    func insertionLineRect() -> NSRect? {
        guard let manager = layoutManager, let container = textContainer else { return nil }
        manager.ensureLayout(for: container)
        let index = min(selectedRange().location, string.utf16.count)
        var rect: NSRect
        if index == string.utf16.count && manager.extraLineFragmentTextContainer === container {
            rect = manager.extraLineFragmentRect
        } else if manager.numberOfGlyphs > 0 {
            let character = min(index, max(0, string.utf16.count - 1))
            rect = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: character), effectiveRange: nil)
        } else { return nil }
        rect.origin.x += textContainerOrigin.x; rect.origin.y += textContainerOrigin.y
        return rect
    }
    func revealInsertionAfterLayout() {
        guard window?.firstResponder === self, !viewportRevealPending else { return }
        viewportRevealPending = true
        // NSTextView and the magnified clip view settle their sizes after the edit/layout callback.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.viewportRevealPending = false
            guard self.window?.firstResponder === self, self.selectedRange().length == 0,
                  let manager = self.layoutManager, let container = self.textContainer,
                  let scroll = self.enclosingScrollView else { return }
            manager.ensureLayout(for: container)
            let bottom = max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)
            let bottomPadding = max(self.textContainerInset.height, 24 / scroll.magnification)
            let height = max(scroll.contentView.bounds.height, ceil(bottom + self.textContainerInset.height + bottomPadding))
            if abs(self.frame.height - height) > 0.5 { self.setFrameSize(NSSize(width: self.frame.width, height: height)) }
            guard var line = self.insertionLineRect() else { return }
            // Use the laid-out line, including the empty final paragraph, rather than a cached screen caret rect.
            line.origin.x = scroll.contentView.bounds.minX
            line.size.width = min(1, scroll.contentView.bounds.width)
            line.origin.y = max(0, line.minY - self.textContainerInset.height)
            line.size.height += self.textContainerInset.height + bottomPadding
            self.scrollToVisible(line)
        }
    }
}
