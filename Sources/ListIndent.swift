import AppKit

extension NoteTextView {
    /// Returns true for a list selection, even when a structural or depth boundary prevents a move.
    @discardableResult func changeListDepth(increase: Bool) -> Bool {
        guard isEditable, richEditing, !hasMarkedText(), let storage = textStorage else { return false }
        let selection = selectedRange()
        var doc = RichDocument.from(storage, emptyBlock: unpacked(typingAttributes[.noteBlock], as: BlockStyle.self) ?? BlockStyle())
        let ns = string as NSString
        let first = ns.substring(to: selection.location).filter { $0 == "\n" }.count
        let lastPosition = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
        let last = ns.substring(to: lastPosition).filter { $0 == "\n" }.count
        guard first < doc.blocks.count, !doc.blocks[first].style.lists.isEmpty else { return false }
        let path = doc.blocks[first].style.lists, depth = path.count
        guard (first...min(last, doc.blocks.count - 1)).allSatisfy({ doc.blocks[$0].style.lists.starts(with: path) }) else { return true }
        var end = min(last + 1, doc.blocks.count)
        while end < doc.blocks.count && doc.blocks[end].style.lists.count > depth && doc.blocks[end].style.lists.starts(with: path) { end += 1 }
        let replacement: [ListContext]
        if increase {
            guard first > 0, doc.blocks[first - 1].style.lists.starts(with: path),
                  (first..<end).allSatisfy({ doc.blocks[$0].style.lists.count < 5 }) else { return true }
            let previous = doc.blocks[first - 1].style.lists
            let child: ListContext
            if previous.count > depth && previous[depth].tag == path.last!.tag { child = previous[depth] }
            else {
                let nextID = (doc.blocks.flatMap { $0.style.lists }.map(\.id).max() ?? 0) + 1
                child = ListContext(id: nextID, tag: path.last!.tag)
            }
            replacement = path + [child]
        } else {
            guard depth > 1 else { return true }
            replacement = Array(path.dropLast())
        }
        let old = NSAttributedString(attributedString: storage), oldTyping = typingAttributes
        // Preserve selection by paragraph and body offset because ordered markers can change width.
        func anchor(_ location: Int, document: RichDocument) -> (Int, Int) {
            let before = (document.text as NSString).substring(to: min(location, document.text.utf16.count))
            let line = before.filter { $0 == "\n" }.count
            let column = before.components(separatedBy: "\n").last!.utf16.count
            let rendered = document.text.components(separatedBy: "\n")[line]
            let body = document.blocks[line].runs.map(\.text).joined()
            return (line, max(0, column - (rendered.utf16.count - body.utf16.count)))
        }
        let a = anchor(selection.location, document: doc), b = anchor(NSMaxRange(selection), document: doc)
        for index in first..<end {
            doc.blocks[index].style.lists = replacement + doc.blocks[index].style.lists.dropFirst(depth)
        }
        func position(_ anchor: (Int, Int)) -> Int {
            let lines = doc.text.components(separatedBy: "\n")
            let preceding = lines.prefix(anchor.0).reduce(0) { $0 + $1.utf16.count + 1 }
            let body = doc.blocks[anchor.0].runs.map(\.text).joined()
            let marker = lines[anchor.0].utf16.count - body.utf16.count
            return preceding + marker + min(anchor.1, body.utf16.count)
        }
        breakUndoCoalescing()
        undoManager?.registerUndo(withTarget: self) { $0.restoreListEdit(old, selection: selection, typing: oldTyping) }
        storage.setAttributedString(doc.attributed())
        let start = position(a), finish = position(b)
        setSelectedRange(NSRange(location: start, length: max(0, finish - start)))
        let style = unpacked(oldTyping[.noteInline], as: InlineStyle.self) ?? InlineStyle()
        typingAttributes = RichDocument.attributes(inline: style, block: doc.blocks[first].style)
        didChangeText(); breakUndoCoalescing()
        return true
    }
    private func restoreListEdit(_ content: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any]) {
        let old = NSAttributedString(attributedString: attributedString()), oldSelection = selectedRange(), oldTyping = typingAttributes
        undoManager?.registerUndo(withTarget: self) { $0.restoreListEdit(old, selection: oldSelection, typing: oldTyping) }
        textStorage?.setAttributedString(content); setSelectedRange(selection); typingAttributes = typing
        didChangeText()
    }
}
