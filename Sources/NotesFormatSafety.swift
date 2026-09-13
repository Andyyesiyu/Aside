import Foundation

// Notes' scripting HTML omits alias-link destinations and normalizes some blocks.
// Local rich text supports more formats than this deliberately narrower write boundary.
extension RichDocument {
    static func parseNotes(_ html: String) -> Result<RichDocument, Error> {
        parse(html).map { original in
            var doc = original
            for i in doc.blocks.indices {
                if let last = doc.blocks[i].runs.indices.last, doc.blocks[i].runs[last].text.hasSuffix("\u{2028}") {
                    doc.blocks[i].runs[last].text.removeLast()
                }
            }
            return doc
        }
    }
    static func notesIssue(_ html: String) -> String? {
        switch parseNotes(html) {
        case .failure(let error): return error.localizedDescription
        case .success(let document): return document.notesWriteIssue
        }
    }
    var notesWriteIssue: String? {
        var previous: [ListContext] = []
        for block in blocks {
            if ["h3", "h4", "h5", "h6"].contains(block.style.tag) {
                return "三级至六级标题已保存在旁白；这些层级尚未通过备忘录回写验证，暂不自动回写。可改为一级或二级标题后同步。"
            }
            if !["div", "p", "li", "h1", "h2"].contains(block.style.tag) {
                return "此段落样式暂不能可靠回写，请在备忘录中编辑。"
            }
            if !block.style.css.isEmpty { return "此段落布局暂不能可靠回写，请在备忘录中编辑。" }
            let visible = block.runs.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let sizes = Set(visible.compactMap { $0.style.css["font-size"] })
            let heading = ((block.style.tag == "h1" && (sizes.isEmpty || sizes == ["16px"])) || (block.style.tag == "h2" && (sizes.isEmpty || sizes == ["12px"]))) || (!visible.isEmpty && visible.allSatisfy { $0.style.bold } && (sizes == ["16px"] || sizes == ["12px"]))
            if sizes.contains(where: { $0 != "9px" }) && !heading {
                return "此混合字号不能可靠回写，已保护原文。"
            }
            let path = block.style.lists
            if path.contains(where: { $0.start != 1 }) { return "自定义编号起点暂不能可靠回写。" }
            if !previous.isEmpty && !path.isEmpty {
                for index in 0..<min(previous.count, path.count) where (previous[index].tag != path[index].tag || (path[index].tag == "ol" && previous[index].id != path[index].id)) {
                    return "相邻或嵌套的不同类型列表会被备忘录合并，已停止回写。"
                }
            }
            previous = path
            for run in block.runs {
                if run.style.link != nil || run.style.underline {
                    return "备忘录接口可能漏掉下划线文字背后的链接地址，已保护原文；请在备忘录中编辑。"
                }
                if run.style.code || run.style.css.keys.contains(where: { !["font-size", "font-family"].contains($0) }) {
                    return "此文字样式尚未通过回写验证，请在备忘录中编辑。"
                }
            }
        }
        return nil
    }
    func notesHTML() -> String {
        var document = self
        for i in document.blocks.indices {
            let visible = document.blocks[i].runs.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let sizes = Set(visible.compactMap { $0.style.css["font-size"] })
            if document.blocks[i].style.lists.isEmpty && !visible.isEmpty && visible.allSatisfy({ $0.style.bold }) {
                if sizes == ["16px"] { document.blocks[i].style.tag = "h1" }
                if sizes == ["12px"] { document.blocks[i].style.tag = "h2" }
            }
            // Notes ignores CSS sizes on import. Semantic headings restore its exported typography.
            for j in document.blocks[i].runs.indices { document.blocks[i].runs[j].style.css.removeValue(forKey: "font-size") }
        }
        return document.html()
    }
    // Compare per-character meaning, independent of Notes' span splitting and font substitution.
    // Its terminal BR is paragraph padding; internal soft breaks still participate.
    var notesSignature: [String] {
        var counters: [Int: Int] = [:]
        return blocks.map { block in
            let runs = block.runs
            var number = ""
            if let list = block.style.lists.last, list.tag == "ol" {
                let value = counters[list.id] ?? list.start; counters[list.id] = value + 1
                number = "#\(value)"
            }
            let prefix = block.style.lists.map { "\($0.tag):\($0.start)" }.joined(separator: "/")
            let text = runs.flatMap { run -> [String] in
                let heading = block.style.tag == "h1" ? "16px" : block.style.tag == "h2" ? "12px" : nil
                let size = run.style.css["font-size"] ?? heading ?? "9px"
                return run.text.map { "\($0)|\(run.style.bold || heading != nil)|\(run.style.italic)|\(run.style.strike)|\(size)" }
            }.joined(separator: "\u{001f}")
            return prefix + number + ":" + text
        }
    }
}
