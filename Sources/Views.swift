import AppKit

final class EdgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, let direction = NoteSizing.shortcut(event), let content = contentView {
            func cards(in view: NSView) -> [NoteCard] {
                if let card = view as? NoteCard { return [card] }
                return view.subviews.flatMap { cards(in: $0) }
            }
            let candidates = cards(in: content)
            if let card = candidates.first(where: { $0.owner?.selectedID == $0.id }) ?? candidates.first {
                card.owner?.stepCardSize(card.id, direction: direction)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class NoteTextView: NSTextView {
    var selected: (() -> Void)?
    var composeChanged: (() -> Void)?
    var appMenu: (() -> NSMenu)?
    var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var richEditing = false
    var viewportRevealPending = false
    private var resolvingViewportSize = false
    override func setFrameSize(_ newSize: NSSize) {
        guard !resolvingViewportSize, let scroll = enclosingScrollView,
              let manager = layoutManager, let container = textContainer else {
            super.setFrameSize(newSize); return
        }
        resolvingViewportSize = true
        defer { resolvingViewportSize = false }
        // NSTextView resizes itself during every edit. Keep its native resize and
        // our post-layout reveal on the same bottom-padding policy, so NSClipView
        // never clamps to a shorter document and then scrolls back down.
        manager.ensureLayout(for: container)
        let bottom = max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)
        let required = ceil(bottom + textContainerInset.height + max(textContainerInset.height, 24 / scroll.magnification))
        super.setFrameSize(NSSize(width: newSize.width, height: max(newSize.height, required)))
    }
    var lastKeyboardInput: TimeInterval = -.infinity
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "b", richEditing, isEditable {
            formatInline(\InlineStyle.bold); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        lastKeyboardInput = ProcessInfo.processInfo.systemUptime
        super.keyDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        selected?()
        if event.modifierFlags.contains(.command), let url = link(at: convert(event.locationInWindow, from: nil)) {
            openLink(url); return
        }
        super.mouseDown(with: event)
    }
    override func clicked(onLink link: Any, at charIndex: Int) {
        if let url = link as? URL { openLink(url) }
        else if let value = link as? String, let url = URL(string: value) { openLink(url) }
    }
    func superInsert(_ content: NSAttributedString, range: NSRange) {
        breakUndoCoalescing()
        super.insertText(content, replacementRange: range)
        breakUndoCoalescing()
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let composing = hasMarkedText()
        super.insertText(insertString, replacementRange: replacementRange)
        let input = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        if !composing, let input = input, input.count == 1 { applyMarkdownShortcut(after: input) }
    }
    override func paste(_ sender: Any?) {
        if richEditing, let html = NSPasteboard.general.string(forType: .html), case .success(let doc) = RichDocument.parse(html) {
            insertText(doc.attributed(), replacementRange: selectedRange())
        } else if richEditing, let source = NSPasteboard.general.string(forType: .string),
                  let doc = Markdown.shared.formattedDocument(source) {
            insertText(doc.attributed(), replacementRange: selectedRange())
        } else { pasteAsPlainText(sender) }
    }
    override func didChangeText() { super.didChangeText(); refreshLinks(); composeChanged?(); revealInsertionAfterLayout() }
    override func unmarkText() { super.unmarkText(); refreshLinks(); composeChanged?() }
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if richEditing, isEditable, !hasMarkedText(), selection.length == 0 {
            let paragraph = (string as NSString).paragraphRange(for: selection)
            let block = selection.location < (textStorage?.length ?? 0)
                ? unpacked(textStorage?.attribute(.noteBlock, at: selection.location, effectiveRange: nil), as: BlockStyle.self)
                : unpacked(typingAttributes[.noteBlock], as: BlockStyle.self)
            if selection.location == paragraph.location, let tag = block?.tag,
               tag.hasPrefix("h"), let level = Int(tag.dropFirst()), (1...6).contains(level) {
                breakUndoCoalescing()
                formatBlock("div")
                breakUndoCoalescing()
                return
            }
        }
        super.deleteBackward(sender)
    }
    override func insertTab(_ sender: Any?) {
        if !changeListDepth(increase: true) { super.insertTab(sender) }
    }
    override func insertBacktab(_ sender: Any?) {
        if !changeListDepth(increase: false) { super.insertBacktab(sender) }
    }
    override func insertNewline(_ sender: Any?) {
        guard richEditing, !hasMarkedText() else { super.insertNewline(sender); return }
        let ns = string as NSString
        let paragraph = ns.substring(with: ns.paragraphRange(for: selectedRange())).trimmingCharacters(in: .newlines)
        var block = unpacked(typingAttributes[.noteBlock], as: BlockStyle.self) ?? BlockStyle()
        let inline = unpacked(typingAttributes[.noteInline], as: InlineStyle.self) ?? InlineStyle()
        // The user may have removed the marker while the paragraph still has
        // inherited list attributes. Enter must respect the visible paragraph.
        if let list = block.lists.last {
            let pattern = list.tag == "ol" ? #"^[0-9]+\. "# : "^• "
            if paragraph.range(of: pattern, options: .regularExpression) == nil {
                block.lists = []; block.tag = "div"
                typingAttributes = RichDocument.attributes(inline: inline, block: block)
            }
        }
        if let list = block.lists.last {
            let pattern = list.tag == "ol" ? #"^[0-9]+\. "# : "^• "
            let body = paragraph.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            if body.isEmpty { formatBlock("div"); return }
            super.insertNewline(sender)
            let number = Int(paragraph.prefix(while: { $0.isNumber })) ?? list.start
            let marker = list.tag == "ol" ? "\(number + 1). " : "• "
            var attrs = RichDocument.attributes(inline: inline, block: block); attrs[.noteMarker] = true
            insertText(NSAttributedString(string: marker, attributes: attrs), replacementRange: selectedRange())
            typingAttributes = RichDocument.attributes(inline: inline, block: block)
        } else {
            super.insertNewline(sender)
            if block.tag.hasPrefix("h") && Int(block.tag.dropFirst()) != nil {
                block.tag = "div"
                var body = inline; body.bold = false; body.css.removeValue(forKey: "font-size")
                typingAttributes = RichDocument.attributes(inline: body, block: block)
                return
            }
            typingAttributes = RichDocument.attributes(inline: inline, block: block)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if richEditing && isEditable {
            let format = NSMenuItem(title: "格式", action: nil, keyEquivalent: "")
            format.submenu = richMenu(); menu.insertItem(format, at: 0)
        }
        if let url = link(at: convert(event.locationInWindow, from: nil)) {
            menu.insertItem(linkMenuItem("打开链接") { [weak self] in self?.openLink(url) }, at: 0)
            menu.insertItem(linkMenuItem("复制链接地址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }, at: 1)
            menu.insertItem(.separator(), at: 2)
        }
        if let extra = appMenu?() {
            menu.addItem(.separator())
            for item in extra.items { extra.removeItem(item); menu.addItem(item) }
        }
        return menu
    }
}

final class HeaderView: NSView {
    weak var card: NoteCard?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // The caption is part of the drag surface; actual buttons retain their own hits.
        if let hit = hit, let label = card?.foldLabel, hit === label || hit.isDescendant(of: label) { return self }
        return hit
    }
    override func mouseDown(with event: NSEvent) {
        guard let card = card else { return }
        card.activate()
        if event.clickCount == 2 { card.owner?.toggleFold(card.id); return }
        guard let source = window else { return }
        let start = NSEvent.mouseLocation
        let rect = source.convertToScreen(card.convert(card.bounds, to: nil))
        var dragged = false
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { break }
            let point = NSEvent.mouseLocation
            if !dragged && hypot(point.x - start.x, point.y - start.y) < 5 { continue }
            dragged = true
            card.owner?.dragCard(card.id, topLeft: NSPoint(x: rect.minX + point.x - start.x, y: rect.maxY + point.y - start.y))
        }
        if dragged { card.owner?.finishDesktopDrag(card.id) }

    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func rightMouseDown(with event: NSEvent) {
        guard let card = card, let menu = card.owner?.noteMenu(card.id) else { return }
        card.activate(); NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class ResizeGrip: NSView {
    weak var card: NoteCard?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let card = card else { return }
        let right = card.resizeSide == "right"
        let x: CGFloat = right ? 0 : bounds.maxX
        let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: 0)); p.line(to: NSPoint(x: x, y: bounds.maxY)); p.line(to: NSPoint(x: right ? bounds.maxX : 0, y: bounds.maxY)); p.close()
        card.border.withAlphaComponent(0.7).setFill(); p.fill()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        guard let card = card else { return }
        card.activate()
        let start = NSEvent.mouseLocation
        let initial = card.frame.size
        let side = card.resizeSide
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { card.owner?.store.saveSoon(); break }
            let size = NoteSizing.dragged(initial: initial, start: start, current: NSEvent.mouseLocation, side: side)
            card.owner?.resizeCard(card.id, size: size)
        }
    }
}

final class NoteCard: NSView, NSTextViewDelegate {
    let id: UUID
    weak var owner: AppDelegate?
    var border = NSColor.yellow
    var background = NSColor.yellow
    let header = HeaderView()
    let closeButton = CloseNoteButton()
    let foldLabel = NSTextField(labelWithString: "")
    let linkButton = NSButton()
    let pinButton = NSButton()
    let scroll = NSScrollView()
    let editor = NoteTextView()
    let grip = ResizeGrip()
    var resizeSide: String { owner?.store.note(id)?.desktopPosition == nil ? (owner?.store.book.preferences.side ?? "right") : "left" }
    var folded = false
    var applying = false
    var appliedDocument: RichDocument?
    override var isFlipped: Bool { true }

    init(note: Note, owner: AppDelegate) {
        self.id = note.id; self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 1; layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.15; layer?.shadowRadius = 5; layer?.shadowOffset = CGSize(width: 0, height: -2)
        header.card = self
        header.toolTip = "拖动顶栏，自由贴到桌面；右键可收回侧边"; addSubview(header)
        closeButton.isBordered = false; closeButton.title = ""
        closeButton.target = self; closeButton.action = #selector(archive); closeButton.toolTip = "收走便笺（可从菜单栏恢复）"; closeButton.setAccessibilityLabel("收走 \(note.title)")
        header.addSubview(closeButton)
        foldLabel.font = TypeStyle.font(); foldLabel.textColor = .black; foldLabel.lineBreakMode = .byTruncatingTail
        header.addSubview(foldLabel)
        linkButton.isBordered = false; linkButton.font = .systemFont(ofSize: 10); linkButton.contentTintColor = .black
        linkButton.target = self; linkButton.action = #selector(showLink); header.addSubview(linkButton)
        pinButton.isBordered = false; pinButton.imagePosition = .imageOnly
        pinButton.target = self; pinButton.action = #selector(togglePinned)
        pinButton.setButtonType(.pushOnPushOff); header.addSubview(pinButton)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder; scroll.contentView.drawsBackground = false
        scroll.minMagnification = 0.8; scroll.maxMagnification = 2
        scroll.allowsMagnification = false
        editor.isRichText = true; editor.richEditing = true; editor.usesFontPanel = false
        editor.importsGraphics = false; editor.drawsBackground = false
        editor.isHorizontallyResizable = false; editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true; editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.lineFragmentPadding = 0; editor.textContainerInset = NSSize(width: 9, height: 5)
        editor.minSize = .zero; editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.allowsUndo = true; editor.delegate = self
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false; editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.linkTextAttributes = [.foregroundColor: NSColor(srgbRed: 0.10, green: 0.25, blue: 0.60, alpha: 1), .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        editor.toolTip = "⌘点击链接打开；右键可打开或复制链接地址。"
        editor.font = TypeStyle.font(); editor.textColor = .black; editor.insertionPointColor = .black
        editor.typingAttributes = TypeStyle.attributes
        editor.selected = { [weak self] in self?.activate() }
        editor.appMenu = { [weak self] in guard let s = self else { return NSMenu() }; return s.owner?.noteMenu(s.id) ?? NSMenu() }
        editor.composeChanged = { [weak self] in self?.commitText() }
        scroll.documentView = editor; addSubview(scroll)
        grip.card = self; addSubview(grip)
        grip.toolTip = "拖动调整这张便笺的宽度和高度"
        grip.setAccessibilityLabel("调整便笺宽度和高度")
        update(note)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func activate() { owner?.select(id); window?.makeKey() }
    @objc func togglePinned() { owner?.togglePin(id) }
    @objc func archive() { owner?.archive(id) }
    @objc func showLink() {
        if owner?.syncIssues[id] != nil { owner?.resolveSync(id) } else { owner?.showRemote(id) }
    }
    func commitText() {
        guard !applying, !editor.hasMarkedText(), editor.isEditable else { return }
        let doc = RichDocument.from(editor.attributedString(), emptyBlock: unpacked(editor.typingAttributes[.noteBlock], as: BlockStyle.self) ?? BlockStyle()).canonical
        appliedDocument = doc
        owner?.richTextChanged(id, document: doc)
    }
    func textDidChange(_ notification: Notification) { commitText() }
    func textDidEndEditing(_ notification: Notification) { commitText() }
    func update(_ note: Note) {
        (background, border) = Paper.colors(note.color)
        layer?.backgroundColor = background.cgColor; layer?.borderColor = border.cgColor
        closeButton.paperBorder = border
        let oldFold = folded
        folded = note.collapsed || (owner?.store.book.preferences.collapsed ?? false)
        foldLabel.stringValue = note.title
        foldLabel.isHidden = !folded
        scroll.isHidden = folded; grip.isHidden = folded
        if abs(scroll.magnification - note.effectiveZoom) > 0.0001 { scroll.magnification = note.effectiveZoom }
        let readOnly = note.effectiveReadOnly
        editor.isEditable = !readOnly; editor.isSelectable = true
        editor.setAccessibilityLabel(note.title + (readOnly ? "，备忘录预览，只读" : "，便笺正文"))
        let doc = readOnly ? RichDocument(text: note.text) : note.effectiveDocument
        if (appliedDocument != doc || editor.string != doc.text) && !editor.hasMarkedText() {
            applying = true
            let selection = editor.selectedRange()
            let textChanged = editor.string != doc.text
            editor.textStorage?.setAttributedString(doc.attributed())
            editor.typingAttributes = RichDocument.attributes(inline: doc.blocks.first?.runs.first?.style ?? InlineStyle(), block: doc.blocks.first?.style ?? BlockStyle())
            editor.refreshLinks()
            editor.setSelectedRange(NSRange(location: min(selection.location, editor.textStorage?.length ?? 0), length: 0))
            if textChanged { editor.undoManager?.removeAllActions() }
            appliedDocument = doc
            applying = false
        }
        pinButton.image = NSImage(systemSymbolName: note.isPinned ? "pin.fill" : "pin", accessibilityDescription: note.isPinned ? "取消钉住" : "钉住便笺")
        pinButton.contentTintColor = note.isPinned ? NSColor(srgbRed: 0.65, green: 0.16, blue: 0.12, alpha: 1) : .darkGray
        pinButton.state = note.isPinned ? .on : .off
        pinButton.toolTip = note.isPinned ? "已钉住：移开鼠标也保持显示" : "钉住：让这张便笺保持显示"
        pinButton.setAccessibilityLabel(note.isPinned ? "取消钉住便笺" : "钉住便笺")
        linkButton.isHidden = note.remoteID == nil
        let issue = owner?.syncIssues[id]
        linkButton.title = issue == nil ? "↗" : "!"
        linkButton.toolTip = issue ?? (readOnly ? "在备忘录中编辑（保留原始格式）" : "在备忘录中打开")
        if !folded && readOnly { foldLabel.isHidden = false; foldLabel.stringValue = "只读 · 请在备忘录中编辑"; foldLabel.font = .systemFont(ofSize: 10) }
        else { foldLabel.font = TypeStyle.font() }
        linkButton.setAccessibilityLabel(issue == nil ? "在备忘录中打开" : "查看同步问题")
        if oldFold != folded { needsLayout = true }
        needsDisplay = true; needsLayout = true; grip.needsDisplay = true
    }
    override func layout() {
        super.layout()
        let followInsertion = editor.window?.firstResponder === editor &&
            (editor.insertionLineRect()?.intersects(editor.visibleRect) == true)
        let h: CGFloat = folded ? 30 : 24
        header.frame = NSRect(x: 1, y: 1, width: bounds.width - 2, height: h)
        closeButton.frame = NSRect(x: 1, y: (h - 24) / 2, width: 24, height: 24)
        foldLabel.frame = NSRect(x: 30, y: 4, width: max(10, bounds.width - 86), height: 24)
        pinButton.frame = NSRect(x: bounds.width - 54, y: (h - 24) / 2, width: 24, height: 24)
        linkButton.frame = NSRect(x: bounds.width - 28, y: 0, width: 24, height: h)
        scroll.frame = NSRect(x: 1, y: h + 1, width: bounds.width - 2, height: max(0, bounds.height - h - 2))
        // Clip bounds are expressed in magnified document coordinates. Reflow to the
        // visible width so zoomed text remains editable without horizontal clipping.
        let visibleSize = scroll.contentView.bounds.size
        editor.minSize = .zero
        editor.frame.size.width = visibleSize.width
        editor.textContainer?.containerSize.width = max(1, visibleSize.width - 18)
        editor.minSize.height = visibleSize.height
        if followInsertion { editor.revealInsertionAfterLayout() }
        let right = resizeSide == "right"
        grip.frame = NSRect(x: right ? 1 : bounds.width - 19, y: bounds.height - 19, width: 18, height: 18)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !folded && owner?.selectedID == id {
            border.setStroke(); let p = NSBezierPath(); p.move(to: NSPoint(x: 1, y: 25)); p.line(to: NSPoint(x: bounds.width - 1, y: 25)); p.lineWidth = 1; p.stroke()
        }
        closeButton.alphaValue = 1
    }
    override func rightMouseDown(with event: NSEvent) {
        activate(); if let menu = owner?.noteMenu(id) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke(_ sender: Any?) { handler() }
}
