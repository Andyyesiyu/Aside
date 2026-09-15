import AppKit
import CoreText

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var color = "yellow"
    var collapsed = false
    var height: Double = 250
    var width: Double?
    var zoom: Double?
    var effectiveZoom: Double { min(2, max(0.8, zoom ?? 1)) }
    var archived = false
    var modified = Date()
    var remoteID: String?
    var baseHTML: String?
    var baseText: String?
    var readOnly = false
    var richDocument: RichDocument?
    var baseRichDocument: RichDocument?
    var pendingSync: PendingSync?
    var desktopPosition: DesktopPosition?
    var screenAnchor: ScreenAnchor?
    var pinned: Bool?
    var isPinned: Bool { pinned == true }
    var effectiveReadOnly: Bool {
        guard remoteID != nil, let html = baseHTML else { return readOnly }
        return RichDocument.notesIssue(html) != nil
    }
    var baselineDocument: RichDocument {
        if let doc = baseRichDocument { return doc.canonical }
        if let html = baseHTML, case .success(let doc) = RichDocument.parseNotes(html) { return doc.canonical }
        return RichDocument(text: baseText ?? text).canonical
    }
    var effectiveDocument: RichDocument {
        if let doc = richDocument { return doc.canonical }
        if remoteID != nil && text == baseText { return baselineDocument }
        var doc = RichDocument(text: text)
        if let html = baseHTML, let size = plainNoteFormat(html)?.fontSize {
            for i in doc.blocks.indices { for j in doc.blocks[i].runs.indices { doc.blocks[i].runs[j].style.css["font-size"] = size } }
        }
        return doc.canonical
    }
    var title: String { text.split(separator: "\n").first.map(String.init).flatMap { $0.isEmpty ? nil : $0 } ?? "新便笺" }
}

struct Preferences: Codable {
    var side = "right"
    var width: Double = 280
    var screenID: String?
    var allSpaces = true
    var floatOnTop = true
    var collapsed = false
    var autoHide = true
    var fixedMode = false
    var shouldAutoHide: Bool { autoHide && !fixedMode }
    var handlePositions: [String: Double] = [:]
}

extension Preferences {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        side = try c.decodeIfPresent(String.self, forKey: .side) ?? "right"
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 280
        screenID = try c.decodeIfPresent(String.self, forKey: .screenID)
        allSpaces = try c.decodeIfPresent(Bool.self, forKey: .allSpaces) ?? true
        floatOnTop = try c.decodeIfPresent(Bool.self, forKey: .floatOnTop) ?? true
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? true
        fixedMode = try c.decodeIfPresent(Bool.self, forKey: .fixedMode) ?? false
        handlePositions = try c.decodeIfPresent([String: Double].self, forKey: .handlePositions) ?? [:]
    }
}

struct Notebook: Codable {
    var version = 1
    var notes: [Note] = []
    var preferences = Preferences()
}

enum SyncDecision: Equatable { case unchanged, pull, push, conflict, readOnly }
func decideSync(local: String, baseline: String, remoteHTML: String, baselineHTML: String, readOnly: Bool) -> SyncDecision {
    let dirty = local != baseline
    let changed = remoteHTML != baselineHTML
    if readOnly { return changed ? .pull : .readOnly }
    if dirty && changed { return .conflict }
    if dirty { return .push }
    if changed { return .pull }
    return .unchanged
}

func normalized(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
}
func noteHTML(_ text: String, fontSize: String? = nil) -> String {
    text.components(separatedBy: "\n").map { line in
        let escaped = line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        let content = escaped.isEmpty ? "<br>" : escaped
        if let size = fontSize { return "<div><span style=\"font-size: \(size)\">\(content)</span></div>" }
        return "<div>\(content)</div>"
    }.joined()
}

// Notes serializes plain text with uniform font-size spans; preserve that size on writes.
struct PlainNoteFormat { var fontSize: String? }
func plainNoteFormat(_ html: String) -> PlainNoteFormat? {
    guard let tags = try? NSRegularExpression(pattern: "<[^>]+>"),
          let span = try? NSRegularExpression(pattern: #"^<span\s+style=["']font-size:\s*([0-9]+(?:\.[0-9]+)?(?:px|pt));?["']>$"#, options: .caseInsensitive) else { return nil }
    let ns = html as NSString
    var sizes = Set<String>(), stack: [String] = []
    var previous = 0, unstyledText = false
    for match in tags.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
        let text = ns.substring(with: NSRange(location: previous, length: match.range.location - previous))
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !stack.contains(where: { !$0.isEmpty }) { unstyledText = true }
        let tag = ns.substring(with: match.range).lowercased()
        if tag == "<span>" { stack.append("") }
        else if tag == "</span>" { guard !stack.isEmpty else { return nil }; stack.removeLast() }
        else if let style = span.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) {
            let size = (tag as NSString).substring(with: style.range(at: 1)); sizes.insert(size); stack.append(size)
        } else if !["<div>", "</div>", "<p>", "</p>", "<br>", "<br/>", "<br />", "<html>", "</html>", "<body>", "</body>"].contains(tag) { return nil }
        previous = NSMaxRange(match.range)
    }
    if previous < ns.length && !ns.substring(from: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { unstyledText = true }
    guard stack.isEmpty, sizes.count <= 1, sizes.isEmpty || !unstyledText else { return nil }
    return PlainNoteFormat(fontSize: sizes.first)
}
func simpleHTML(_ html: String) -> Bool { plainNoteFormat(html) != nil }

final class NoteStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("notebook.json") }
    var backup: URL { directory.appendingPathComponent("notebook.backup.json") }
    var book = Notebook()
    var loadMessage: String?
    private var saving: DispatchWorkItem?
    var onError: ((String) -> Void)?

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            do { book = try Self.decode(Data(contentsOf: file)) }
            catch {
                let originalError = error
                if (error as NSError).domain == "DeskNotes" { throw error }
                if let data = try? Data(contentsOf: backup), let recovered = try? Self.decode(data) {
                    book = recovered
                    loadMessage = "已从上一次备份恢复便笺。"
                } else { throw originalError }
                let preserved = directory.appendingPathComponent("notebook-recovery-\(Int(Date().timeIntervalSince1970)).json")
                try FileManager.default.copyItem(at: file, to: preserved)
                // Keep the valid backup intact; don't rotate the damaged primary over it.
                try encoded().write(to: file, options: .atomic)
            }
        }
    }
    static func decode(_ data: Data) throws -> Notebook {
        let book = try JSONDecoder().decode(Notebook.self, from: data)
        guard book.version == 1 else { throw NSError(domain: "DeskNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "此数据由更新版本创建，请先更新旁白。"] ) }
        return book
    }
    private func encoded() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return try e.encode(book) }
    func saveSoon() {
        saving?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flushReporting() }
        saving = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
    func flushReporting() { do { try flush() } catch { onError?("保存失败：\(error.localizedDescription)") } }
    func flush() throws {
        saving?.cancel(); saving = nil
        let data = try encoded()
        if let previous = try? Data(contentsOf: file), (try? Self.decode(previous)) != nil { try previous.write(to: backup, options: .atomic) }
        try data.write(to: file, options: .atomic)
    }
    func note(_ id: UUID) -> Note? { book.notes.first { $0.id == id } }
    func update(_ id: UUID, _ change: (inout Note) -> Void) {
        guard let i = book.notes.firstIndex(where: { $0.id == id }) else { return }
        change(&book.notes[i]); saveSoon()
    }
}

enum Paper {
    static let names = ["yellow", "blue", "green", "pink", "purple", "orange"]
    static let labels = ["黄色", "蓝色", "绿色", "粉色", "紫色", "橙色"]
    static let backgrounds = ["FFFFA5", "D4EDFC", "D4F5D4", "FFD4E5", "E8D4F5", "FFE4C4"]
    static let borders = ["E6E650", "8EC8E8", "8ED88E", "FF8EB8", "C88EE8", "FFB870"]
    static func color(_ hex: String) -> NSColor {
        let n = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
    static func colors(_ name: String) -> (NSColor, NSColor) {
        let i = names.firstIndex(of: name) ?? 0
        return (color(backgrounds[i]), color(borders[i]))
    }
}

enum TypeStyle {
    static var fusionName = ""
    static func register() {
        guard let url = Bundle.main.url(forResource: "FusionPixelSC", withExtension: "otf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = descriptors.first {
            fusionName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String ?? ""
        }
    }
    static func font(size: CGFloat = 14) -> NSFont {
        let base = NSFont(name: "Geneva", size: size) ?? NSFont.systemFont(ofSize: size)
        guard !fusionName.isEmpty else { return base }
        let fallback = NSFontDescriptor(fontAttributes: [.name: fusionName, .size: size])
        let desc = base.fontDescriptor.addingAttributes([.cascadeList: [fallback]])
        return NSFont(descriptor: desc, size: size) ?? base
    }
    static var attributes: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle(); p.lineSpacing = 4
        return [.font: font(), .foregroundColor: NSColor.black, .paragraphStyle: p]
    }
}

// Persist before a remote mutation so a crash or failed verification cannot trigger blind retries.
struct PendingSync: Codable, Equatable {
    var sent: RichDocument
    var returnedHTML: String?
    var returnedText: String?
    var problem: String = "上次同步尚未确认。请点“立即同步”重新核对。"
}
