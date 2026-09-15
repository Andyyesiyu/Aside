import AppKit

extension NSAttributedString.Key {
    static let noteInline = NSAttributedString.Key("DeskNotes.inline")
    static let noteBlock = NSAttributedString.Key("DeskNotes.block")
    static let noteMarker = NSAttributedString.Key("DeskNotes.marker")
    static let automaticLink = NSAttributedString.Key("DeskNotes.autoLink")
}
func packed<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return String(data: try! encoder.encode(value), encoding: .utf8)!
}
func unpacked<T: Decodable>(_ value: Any?, as type: T.Type) -> T? {
    guard let text = value as? String, let data = text.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}
extension RichDocument {
    static func attributes(inline: InlineStyle, block: BlockStyle) -> [NSAttributedString.Key: Any] {
        var attrs = TypeStyle.attributes
        attrs[.noteInline] = packed(inline); attrs[.noteBlock] = packed(block)
        let heading = block.tag.hasPrefix("h") && Int(block.tag.dropFirst()) != nil
        if heading, let level = Int(block.tag.dropFirst()), (1...6).contains(level) {
            attrs[.font] = TypeStyle.font(size: [24.0, 21, 18, 16, 15, 14][level - 1])
        }
        if inline.bold || heading { attrs[.strokeWidth] = -2.5 }
        if inline.italic { attrs[.obliqueness] = 0.16 }
        if inline.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if inline.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if inline.code { attrs[.backgroundColor] = NSColor.black.withAlphaComponent(0.06) }
        if let color = inline.css["color"], color.hasPrefix("#"), color.count == 7 { attrs[.foregroundColor] = Paper.color(String(color.dropFirst())) }
        if let link = inline.link, let url = URL(string: link) { attrs[.link] = url }
        let paragraph = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
        paragraph.headIndent = CGFloat(block.lists.count) * 14
        paragraph.firstLineHeadIndent = max(0, paragraph.headIndent - (block.lists.isEmpty ? 0 : 14))
        if block.tag == "blockquote" { paragraph.headIndent += 14; paragraph.firstLineHeadIndent += 14 }
        switch block.css["text-align"] {
        case "center": paragraph.alignment = .center
        case "right": paragraph.alignment = .right
        case "justify": paragraph.alignment = .justified
        default: break
        }
        if block.css["direction"] == "rtl" { paragraph.baseWritingDirection = .rightToLeft }
        attrs[.paragraphStyle] = paragraph
        return attrs
    }
    func attributed() -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        var counters: [Int: Int] = [:]
        for (index, block) in blocks.enumerated() {
            let first = block.runs.first?.style ?? InlineStyle()
            if let list = block.style.lists.last {
                let count = counters[list.id] ?? list.start; counters[list.id] = count + 1
                let marker = list.tag == "ol" ? "\(count). " : "• "
                var attrs = Self.attributes(inline: first, block: block.style); attrs[.noteMarker] = true
                attrs.removeValue(forKey: .link)
                output.append(NSAttributedString(string: marker, attributes: attrs))
            }
            for run in block.runs { output.append(NSAttributedString(string: run.text, attributes: Self.attributes(inline: run.style, block: block.style))) }
            if index < blocks.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: Self.attributes(inline: block.runs.last?.style ?? first, block: block.style)))
            }
        }
        return output
    }
    static func from(_ text: NSAttributedString, emptyBlock: BlockStyle = BlockStyle()) -> RichDocument {
        let ns = text.string as NSString
        var blocks: [RichBlock] = [], location = 0
        // Edited marker text is authoritative. Split numbering runs when the user
        // changes a number, rather than silently regenerating the old sequence.
        var nextListID = 0
        text.enumerateAttribute(.noteBlock, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            nextListID = max(nextListID, unpacked(value, as: BlockStyle.self)?.lists.map(\.id).max() ?? 0)
        }
        var mappedLists: [Int: ListContext] = [:], counters: [Int: Int] = [:]
        let lines = text.string.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            let length = (line as NSString).length
            let attrs = location < text.length ? text.attributes(at: location, effectiveRange: nil) : (lineIndex == lines.count - 1 && length == 0 ? [.noteBlock: packed(emptyBlock)] : [:])
            var style = unpacked(attrs[.noteBlock], as: BlockStyle.self) ?? emptyBlock
            var start = location
            if let original = style.lists.last {
                let pattern = original.tag == "ol" ? #"^[0-9]+\. "# : "^• "
                let range = (line as NSString).range(of: pattern, options: .regularExpression)
                if range.location == 0 {
                    style.lists = style.lists.map { mappedLists[$0.id] ?? $0 }
                    if original.tag == "ol" {
                        let digits = String(line.prefix(while: { $0.isNumber }))
                        var list = style.lists.last!
                        let expected = counters[list.id] ?? list.start
                        // Unsupported/unfinished numeric text stays literal, never disappears.
                        if let number = Int(digits), number < Int.max, String(number) == digits {
                            if number != expected {
                                nextListID += 1
                                list = ListContext(id: nextListID, tag: "ol", start: number)
                                mappedLists[original.id] = list
                                style.lists[style.lists.count - 1] = list
                            }
                            counters[list.id] = number + 1
                            start += range.length
                        } else { style.lists = []; style.tag = "div" }
                    } else { start += range.length }
                } else {
                    // Deleting the whole marker leaves inherited paragraph metadata
                    // on the body. Do not resurrect the marker on the next refresh.
                    style.lists = []; style.tag = "div"
                }
            }
            var runs: [RichRun] = []
            text.enumerateAttributes(in: NSRange(location: start, length: location + length - start)) { attrs, range, _ in
                let inline = unpacked(attrs[.noteInline], as: InlineStyle.self) ?? InlineStyle()
                let value = ns.substring(with: range)
                if runs.last?.style == inline { runs[runs.count - 1].text += value }
                else { runs.append(RichRun(text: value, style: inline)) }
            }
            if runs.isEmpty { runs = [RichRun(text: "", style: unpacked(attrs[.noteInline], as: InlineStyle.self) ?? InlineStyle())] }
            blocks.append(RichBlock(style: style, runs: runs)); location += length + 1
        }
        return RichDocument(blocks: blocks)
    }
    var text: String { attributed().string }
    var canonical: RichDocument { Self.from(attributed()) }
}

extension NoteTextView {
    func refreshTypingStyle() {
        guard richEditing else { typingAttributes = TypeStyle.attributes; return }
        var inline = unpacked(typingAttributes[.noteInline], as: InlineStyle.self) ?? InlineStyle()
        let block = unpacked(typingAttributes[.noteBlock], as: BlockStyle.self) ?? BlockStyle()
        // A newly typed URL is detected separately; it must not turn following text into a link.
        if typingAttributes[.automaticLink] != nil { inline.link = nil }
        typingAttributes = RichDocument.attributes(inline: inline, block: block)
    }
    func restoreFormatting(_ content: NSAttributedString, selection: NSRange) {
        let previous = NSAttributedString(attributedString: textStorage!)
        let previousSelection = selectedRange()
        undoManager?.registerUndo(withTarget: self) { $0.restoreFormatting(previous, selection: previousSelection) }
        textStorage?.setAttributedString(content)
        setSelectedRange(selection); didChangeText()
    }
    func formatInline(_ key: WritableKeyPath<InlineStyle, Bool>) {
        guard isEditable, !hasMarkedText(), let storage = textStorage else { return }
        let selection = selectedRange()
        if selection.length == 0 {
            var style = unpacked(typingAttributes[.noteInline], as: InlineStyle.self) ?? InlineStyle()
            style[keyPath: key].toggle()
            typingAttributes = RichDocument.attributes(inline: style, block: unpacked(typingAttributes[.noteBlock], as: BlockStyle.self) ?? BlockStyle())
            return
        }
        let previous = NSAttributedString(attributedString: storage)
        var spans: [(NSRange, InlineStyle, BlockStyle)] = []
        storage.enumerateAttributes(in: selection) { attrs, range, _ in
            spans.append((range, unpacked(attrs[.noteInline], as: InlineStyle.self) ?? InlineStyle(), unpacked(attrs[.noteBlock], as: BlockStyle.self) ?? BlockStyle()))
        }
        let enabled = !spans.allSatisfy { $0.1[keyPath: key] }
        undoManager?.registerUndo(withTarget: self) { $0.restoreFormatting(previous, selection: selection) }
        storage.beginEditing()
        for (range, oldStyle, block) in spans {
            var style = oldStyle; style[keyPath: key] = enabled
            var attrs = RichDocument.attributes(inline: style, block: block)
            if storage.attribute(.noteMarker, at: range.location, effectiveRange: nil) as? Bool == true { attrs[.noteMarker] = true }
            storage.setAttributes(attrs, range: range)
        }
        storage.endEditing(); didChangeText()
    }
    func formatBlock(_ tag: String) {
        guard isEditable, !hasMarkedText(), let storage = textStorage else { return }
        let selection = selectedRange()
        let whole = (string as NSString).paragraphRange(for: selection)
        let previous = NSAttributedString(attributedString: storage)
        var document = RichDocument.from(storage)
        let listID = (document.blocks.flatMap { $0.style.lists }.map(\.id).max() ?? 0) + 1
        var position = 0
        for index in document.blocks.indices {
            let rendered = RichDocument(blocks: [document.blocks[index]]).text
            let length = (rendered as NSString).length + 1
            if NSIntersectionRange(NSRange(location: position, length: length), whole).length > 0 || (whole.length == 0 && position == whole.location) {
                document.blocks[index].style.tag = ["ul", "ol"].contains(tag) ? "li" : tag
                for run in document.blocks[index].runs.indices {
                    document.blocks[index].runs[run].style.css["font-size"] = tag == "h1" ? "16px" : tag == "h2" ? "12px" : "9px"
                    if tag == "h1" || tag == "h2" { document.blocks[index].runs[run].style.bold = true }
                }
                document.blocks[index].style.lists = ["ul", "ol"].contains(tag) ? [ListContext(id: listID, tag: tag)] : []
            }
            position += length
        }
        undoManager?.registerUndo(withTarget: self) { $0.restoreFormatting(previous, selection: selection) }
        storage.setAttributedString(document.attributed())
        setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        if let last = document.blocks.last, selectedRange().location == storage.length {
            typingAttributes = RichDocument.attributes(inline: last.runs.last?.style ?? InlineStyle(), block: last.style)
        }
        refreshTypingStyle(); didChangeText()
    }
    func richMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(linkMenuItem("将 Markdown 转为格式") { [weak self] in self?.renderMarkdown(nil) })
        menu.addItem(.separator())
        for (name, key) in [("加粗", \InlineStyle.bold), ("斜体", \InlineStyle.italic), ("下划线", \InlineStyle.underline), ("删除线", \InlineStyle.strike)] {
            menu.addItem(linkMenuItem(name) { [weak self] in self?.formatInline(key) })
        }
        menu.addItem(.separator())
        menu.addItem(linkMenuItem("增加列表层级  ⇥") { [weak self] in self?.changeListDepth(increase: true) })
        menu.addItem(linkMenuItem("减少列表层级  ⇧⇥") { [weak self] in self?.changeListDepth(increase: false) })
        for (name, tag) in [("正文", "div"), ("标题", "h1"), ("二级标题", "h2"), ("三级标题", "h3"), ("四级标题", "h4"), ("五级标题", "h5"), ("六级标题", "h6"), ("项目列表", "ul"), ("编号列表", "ol"), ("引用", "blockquote")] {
            menu.addItem(linkMenuItem(name) { [weak self] in self?.formatBlock(tag) })
        }
        return menu
    }
}
