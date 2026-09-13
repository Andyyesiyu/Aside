import Foundation

func syncDifferenceMessage(sent: RichDocument, returnedHTML: String) -> String {
    guard let received = try? RichDocument.parseNotes(returnedHTML).get() else {
        return "备忘录返回了无法可靠读取的格式。已暂停自动回写，并保存提交内容、回读副本及原文备份。"
    }
    let a = sent.blocks.flatMap(\.runs).map(\.text).joined(), b = received.blocks.flatMap(\.runs).map(\.text).joined()
    let detail: String
    if a.filter({ !$0.isWhitespace }) != b.filter({ !$0.isWhitespace }) {
        detail = "正文字符发生变化"
    } else if sent.blocks.count != received.blocks.count {
        detail = "段落或空行数量发生变化（\(sent.blocks.count) → \(received.blocks.count)）"
    } else if a != b {
        detail = "空格或换行发生变化"
    } else { detail = "文字样式或列表结构发生变化" }
    return "回读核对发现：\(detail)。已暂停自动回写，重开应用后仍保持暂停。提交内容、回读副本及原文备份均已保留；点“立即同步”只重新核对，不强行覆盖。"
}
