import AppKit
import JavaScriptCore

/// The bundled CommonMark parser has no network or filesystem bindings.
final class Markdown {
    static let shared = Markdown()
    private let context = JSContext()!
    private init() {
        let decodeBase64: @convention(block) (String) -> String? = { input in
            guard let data = Data(base64Encoded: input) else { return nil }
            return String(data: data, encoding: .isoLatin1)
        }
        context.setObject(decodeBase64, forKeyedSubscript: "atob" as NSString)
        guard let url = Bundle.main.url(forResource: "markdown-it-15.0.2.min", withExtension: "js", subdirectory: "Markdown"),
              let source = try? String(contentsOf: url) else { return }
        context.evaluateScript(source)
        context.evaluateScript("var deskMarkdown = markdownit({html:false, linkify:false, typographer:false}); function renderNoteMarkdown(s) { return deskMarkdown.render(s); }")
    }
    func document(_ source: String) -> Result<RichDocument, Error> {
        guard source.utf8.count <= 1_000_000,
              let result = context.objectForKeyedSubscript("renderNoteMarkdown")?.call(withArguments: [source]),
              !result.isUndefined, let html = result.toString() else {
            return .failure(NSError(domain: "Markdown", code: 1, userInfo: [NSLocalizedDescriptionKey: "Markdown 解析未完成，原文已保留。 "]))
        }
        return RichDocument.parse(html).map { $0.canonical }
    }
    func formattedDocument(_ source: String) -> RichDocument? {
        guard case .success(let doc) = document(source) else { return nil }
        let styled = doc.blocks.contains { block in
            !["div", "p"].contains(block.style.tag) || !block.style.lists.isEmpty || block.runs.contains {
                let s = $0.style
                return s.bold || s.italic || s.strike || s.code || s.link != nil
            }
        }
        return styled ? doc : nil
    }
}

extension NoteTextView {
    @objc func renderMarkdown(_ sender: Any?) {
        guard isEditable, !hasMarkedText() else { return }
        let selection = selectedRange()
        let range = selection.length > 0 ? selection : NSRange(location: 0, length: (string as NSString).length)
        let source = (string as NSString).substring(with: range)
        switch Markdown.shared.document(source) {
        case .success(let doc): insertText(doc.attributed(), replacementRange: range)
        case .failure(let error):
            let alert = NSAlert(); alert.messageText = "原文已保留"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    func applyMarkdownShortcut(after inserted: String) {
        guard richEditing, isEditable, !hasMarkedText(), undoManager?.isUndoing != true, undoManager?.isRedoing != true, selectedRange().length == 0,
              inserted == " " || inserted == "*" || inserted == "_" || inserted == "`" || inserted == "~" || inserted == ")" else { return }
        let ns = string as NSString, cursor = selectedRange().location
        var start = 0, contentEnd = 0
        ns.getParagraphStart(&start, end: nil, contentsEnd: &contentEnd, for: NSRange(location: cursor, length: 0))
        guard cursor <= contentEnd else { return }
        let range = NSRange(location: start, length: contentEnd - start)
        let prefixRange = NSRange(location: start, length: cursor - start)
        let prefix = ns.substring(with: prefixRange)
        let source = ns.substring(with: range)
        let block = unpacked(typingAttributes[.noteBlock], as: BlockStyle.self) ?? BlockStyle()
        guard block.tag != "pre" else { return }
        if inserted == " " {
            let prefixes = ["# ": "h1", "## ": "h2", "### ": "h3", "#### ": "h4", "##### ": "h5", "###### ": "h6", "- ": "ul", "* ": "ul", "1. ": "ol", "> ": "blockquote"]
            // A continued list already has a marker. Do not leave a second literal '* ' after it.
            if let list = block.lists.last, start < (textStorage?.length ?? 0),
               textStorage?.attribute(.noteMarker, at: start, effectiveRange: nil) as? Bool == true {
                let pattern = list.tag == "ol" ? #"^[0-9]+\. "# : "^• "
                let marker = (prefix as NSString).range(of: pattern, options: .regularExpression)
                if marker.location == 0 {
                    let suffix = (prefix as NSString).substring(from: marker.length)
                    if prefixes[suffix] == list.tag {
                        superInsert(NSAttributedString(string: ""), range: NSRange(location: start + marker.length, length: (suffix as NSString).length))
                        typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: block)
                        return
                    }
                }
            }
            if let tag = prefixes[prefix] {
                // One undo restores the literal prefix; AppKit owns text input and IME.
                if tag == "ul" || tag == "ol" {
                    let previous = start > 0 ? unpacked(textStorage?.attribute(.noteBlock, at: start - 1, effectiveRange: nil), as: BlockStyle.self) : nil
                    let inherited = block.lists.last?.tag == tag ? block.lists : (previous?.lists.last?.tag == tag ? previous!.lists : [])
                    let list = BlockStyle(tag: "li", lists: inherited.isEmpty ? [ListContext(id: Int.random(in: 1...1_000_000_000), tag: tag)] : inherited)
                    var attrs = RichDocument.attributes(inline: InlineStyle(), block: list); attrs[.noteMarker] = true
                    superInsert(NSAttributedString(string: tag == "ul" ? "• " : "1. ", attributes: attrs), range: prefixRange)
                    typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: list)
                } else {
                    superInsert(NSAttributedString(string: "", attributes: typingAttributes), range: prefixRange)
                    // Apply the heading to existing text as well as subsequent typing.
                    formatBlock(tag)
                    typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: BlockStyle(tag: tag))
                }
                return
            }
        }
        guard cursor == contentEnd, block.lists.isEmpty else { return }
        if ["*", "_", "~"].contains(inserted), source.contains(inserted + inserted),
           source.reversed().prefix(while: { String($0) == inserted }).count < 2 { return }
        guard let doc = Markdown.shared.formattedDocument(source), doc.blocks.count == 1,
              doc.blocks[0].style.lists.isEmpty, doc.blocks[0].style.tag == "p",
              doc.text != source else { return }
        // Do not reinterpret an already styled paragraph and discard its metadata.
        let current = RichDocument.from(attributedSubstring(from: range))
        guard current.blocks.flatMap(\.runs).allSatisfy({ $0.style == InlineStyle() }) else { return }
        superInsert(doc.attributed(), range: range)
        typingAttributes = RichDocument.attributes(inline: InlineStyle(), block: block)
    }
    func attributedSubstring(from range: NSRange) -> NSAttributedString { attributedString().attributedSubstring(from: range) }
}
