import AppKit
import CLibXML2

struct InlineStyle: Codable, Equatable {
    var bold = false, italic = false, underline = false, strike = false, code = false
    var link: String?
    var css: [String: String] = [:]
}
struct ListContext: Codable, Equatable {
    var id: Int
    var tag: String
    var start: Int = 1
}
struct BlockStyle: Codable, Equatable {
    var tag = "div"
    var lists: [ListContext] = []
    var css: [String: String] = [:]
}
struct RichRun: Codable, Equatable { var text: String; var style = InlineStyle() }
struct RichBlock: Codable, Equatable { var style = BlockStyle(); var runs: [RichRun] = [] }
struct RichDocument: Codable, Equatable {
    var blocks: [RichBlock]
    init(text: String) { blocks = text.components(separatedBy: "\n").map { RichBlock(runs: [RichRun(text: $0)]) } }
    init(blocks: [RichBlock]) { self.blocks = blocks }
    static func parse(_ html: String) -> Result<RichDocument, Error> { Result { try RichHTMLParser().parse(html) } }
    static func supported(_ html: String) -> Bool { if case .success = parse(html) { return true }; return false }
    func html() -> String {
        var output = "", stack: [ListContext] = []
        func close(to depth: Int) {
            while stack.count > depth { let last = stack.removeLast(); output += "</li></\(last.tag)>" }
        }
        for block in blocks {
            let path = block.style.lists
            var common = 0
            while common < min(stack.count, path.count), stack[common] == path[common] { common += 1 }
            close(to: common)
            if path.isEmpty {
                let tag = block.style.tag == "li" ? "div" : block.style.tag
                output += "<\(tag)\(cssAttribute(block.style.css))>\(inlineHTML(block.runs))</\(tag)>"
            } else {
                if stack.count == path.count { output += "</li><li\(cssAttribute(block.style.css))>" }
                else {
                    for level in path.dropFirst(common) {
                        let start = level.tag == "ol" && level.start != 1 ? " start=\"\(level.start)\"" : ""
                        output += "<\(level.tag)\(start)><li\(cssAttribute(block.style.css))>"; stack.append(level)
                    }
                }
                output += inlineHTML(block.runs)
            }
        }
        close(to: 0)
        return output.isEmpty ? "<div><br></div>" : output
    }
    private func inlineHTML(_ runs: [RichRun]) -> String {
        var value = ""
        for run in runs {
            guard !run.text.isEmpty else { continue }
            var text = htmlEscape(run.text).replacingOccurrences(of: "\u{2028}", with: "<br>")
            let s = run.style
            if !s.css.isEmpty { text = "<span\(cssAttribute(s.css))>\(text)</span>" }
            if s.code { text = "<code>\(text)</code>" }
            if s.strike { text = "<s>\(text)</s>" }
            if s.underline { text = "<u>\(text)</u>" }
            if s.italic { text = "<i>\(text)</i>" }
            if s.bold { text = "<b>\(text)</b>" }
            if let link = s.link { text = "<a href=\"\(htmlEscape(link))\">\(text)</a>" }
            value += text
        }
        return value.isEmpty ? "<br>" : value
    }
}
func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}
private func cssAttribute(_ css: [String: String]) -> String {
    guard !css.isEmpty else { return "" }
    return " style=\"" + htmlEscape(css.keys.sorted().map { "\($0): \(css[$0]!)" }.joined(separator: "; ")) + "\""
}

private final class RichHTMLParser {
    typealias Node = UnsafeMutablePointer<xmlNode>
    var blocks: [RichBlock] = []
    var current: RichBlock?
    var listSerial = 0
    func unsupported(_ detail: String) -> Error {
        NSError(domain: "RichNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "暂不支持编辑此内容（\(detail)），请在备忘录中编辑原文。"])
    }
    func parse(_ html: String) throws -> RichDocument {
        let options = Int32(HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue)
        // Notes emits legacy semicolon-less &amp references in text nodes.
        // libxml2's HTML4 parser does not decode these like Notes/HTML5 do.
        let legacy = try NSRegularExpression(pattern: ">([^<]*)")
        let input = NSMutableString(string: html)
        for match in legacy.matches(in: html, range: NSRange(location: 0, length: input.length)).reversed() {
            let range = match.range(at: 1)
            let text = input.substring(with: range).replacingOccurrences(of: "&amp(?!;)", with: "&amp;", options: .regularExpression)
            input.replaceCharacters(in: range, with: text)
        }
        let sanitized = input as String
        guard let doc = sanitized.withCString({ htmlReadMemory($0, Int32(sanitized.utf8.count), nil, "UTF-8", options) }) else { throw unsupported("无法识别的格式") }
        defer { xmlFreeDoc(doc) }
        guard let root = xmlDocGetRootElement(doc) else { return RichDocument(text: "") }
        try visit(root, inline: InlineStyle(), block: BlockStyle())
        flush()
        return RichDocument(blocks: blocks.isEmpty ? [RichBlock()] : blocks)
    }
    func flush() {
        guard var block = current else { return }
        // A sole BR is the Notes representation of an empty paragraph.
        if block.runs.count == 1 && block.runs[0].text == "\u{2028}" { block.runs[0].text = "" }
        blocks.append(block); current = nil
    }
    func append(_ text: String, inline: InlineStyle, block: BlockStyle) {
        guard !text.isEmpty else { return }
        if current == nil {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            current = RichBlock(style: block)
        }
        if current!.runs.last?.style == inline { current!.runs[current!.runs.count - 1].text += text }
        else { current!.runs.append(RichRun(text: text, style: inline)) }
    }
    func children(_ node: Node, inline: InlineStyle, block: BlockStyle) throws {
        var child = node.pointee.children
        while let next = child { try visit(next, inline: inline, block: block); child = next.pointee.next }
    }
    func attributes(_ node: Node) -> [String: String] {
        var output: [String: String] = [:], prop = node.pointee.properties
        while let p = prop {
            let name = String(cString: p.pointee.name)
            if let value = xmlNodeListGetString(node.pointee.doc, p.pointee.children, 1) { output[name.lowercased()] = String(cString: value); xmlFree(value) }
            prop = p.pointee.next
        }
        return output
    }
    func visit(_ node: Node, inline inherited: InlineStyle, block inheritedBlock: BlockStyle) throws {
        if node.pointee.type == XML_COMMENT_NODE { return }
        if node.pointee.type == XML_TEXT_NODE || node.pointee.type == XML_CDATA_SECTION_NODE {
            guard let content = node.pointee.content else { return }
            var text = String(cString: content)
            if inheritedBlock.tag != "pre" && !(inherited.css["white-space"] ?? "").hasPrefix("pre") {
                text = text.replacingOccurrences(of: "[\\t\\r\\n ]+", with: " ", options: .regularExpression)
            } else { text = text.replacingOccurrences(of: "\n", with: "\u{2028}") }
            append(text, inline: inherited, block: inheritedBlock); return
        }
        guard node.pointee.type == XML_ELEMENT_NODE else { return }
        let tag = String(cString: node.pointee.name).lowercased()
        if tag == "head" { return }
        let allowed = ["html", "body", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "ul", "ol", "li", "span", "b", "strong", "i", "em", "u", "s", "strike", "del", "code", "a", "br", "font"]
        guard allowed.contains(tag) else { throw unsupported(["img":"图片", "object":"附件", "table":"表格", "input":"勾选清单"][tag] ?? "\(tag) 格式") }
        let attrs = attributes(node)
        for key in attrs.keys where !["style", "href", "title", "start", "type", "face", "color", "size", "dir", "class"].contains(key) {
            throw unsupported("附加格式 \(key)")
        }
        if let cls = attrs["class"], !["Apple-converted-space", "Apple-interchange-newline"].contains(cls) { throw unsupported("特殊列表或段落") }
        var style = inherited, block = inheritedBlock
        for declaration in (attrs["style"] ?? "").split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { throw unsupported("样式声明") }
            let key = parts[0].lowercased(), value = parts[1], lower = value.lowercased()
            guard !lower.contains("url("), !lower.contains("expression(") else { throw unsupported("外部样式") }
            switch key {
            case "font-weight": style.bold = lower == "bold" || (Int(lower) ?? 0) >= 600
            case "font-style": style.italic = lower == "italic" || lower == "oblique"
            case "text-decoration", "text-decoration-line": style.underline = lower.contains("underline"); style.strike = lower.contains("line-through")
            case "font-family", "font-size", "color", "background-color", "white-space": style.css[key] = value
            case "text-align", "direction", "margin-left", "margin-right", "margin-top", "margin-bottom", "padding-left", "text-indent", "line-height": block.css[key] = value
            default: throw unsupported("样式 \(key)")
            }
        }
        if let dir = attrs["dir"] { block.css["direction"] = dir }
        if ["b", "strong"].contains(tag) { style.bold = true }
        if ["i", "em"].contains(tag) { style.italic = true }
        if tag == "u" { style.underline = true }
        if ["s", "strike", "del"].contains(tag) { style.strike = true }
        if tag == "code" { style.code = true }
        if tag == "font" {
            if attrs["size"] != nil { throw unsupported("旧版字体尺寸") }
            if let face = attrs["face"] { style.css["font-family"] = face }
            if let color = attrs["color"] { style.css["color"] = color }
        }
        if tag == "a" {
            guard let href = attrs["href"], let url = URL(string: href), NoteLinks.allowed(url) else { throw unsupported("特殊链接") }
            style.link = href
        }
        if tag == "br" { append("\u{2028}", inline: style, block: block); return }
        if tag == "ul" || tag == "ol" {
            if let type = attrs["type"], !["1", "disc"].contains(type) { throw unsupported("特殊编号列表") }
            flush(); listSerial += 1
            block.lists.append(ListContext(id: listSerial, tag: tag, start: Int(attrs["start"] ?? "1") ?? 1))
            try children(node, inline: style, block: block); flush(); return
        }
        let isBlock = ["div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "li"].contains(tag)
        if isBlock {
            // Flatten paragraph wrappers inside one list item into soft breaks.
            if !block.lists.isEmpty && tag != "li" {
                if current != nil && !(current?.runs.isEmpty ?? true) { append("\u{2028}", inline: style, block: block) }
                try children(node, inline: style, block: block); return
            }
            if inheritedBlock.tag == "blockquote" && ["p", "div"].contains(tag) { block.tag = "blockquote" }
            if tag == "li" {
                var child = node.pointee.children, passedList = false
                while let c = child {
                    let childTag = String(cString: c.pointee.name).lowercased()
                    if childTag == "ul" || childTag == "ol" { passedList = true }
                    else if passedList, let content = xmlNodeGetContent(c) {
                        defer { xmlFree(content) }
                        if !String(cString: content).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw unsupported("列表子项后的续写段落") }
                    }
                    child = c.pointee.next
                }
            }
            if current?.runs.isEmpty == true { current = nil }
            flush(); block.tag = inheritedBlock.tag == "blockquote" && ["p", "div"].contains(tag) ? "blockquote" : tag
            current = RichBlock(style: block)
            try children(node, inline: style, block: block)
            flush(); return
        }
        try children(node, inline: style, block: block)
    }
}
