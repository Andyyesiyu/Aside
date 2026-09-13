import Foundation
import Carbon

struct RemoteNote: Codable {
    var id: String
    var text: String
    var html: String
    var name: String
}
struct BridgeReply: Decodable {
    var ok: Bool
    var note: RemoteNote?
    var error: String?
    var conflict: Bool?
}

final class NotesBridge {
    static func permissionStatus() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
    }
    func health(completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        execute("app.version(); return JSON.stringify({ok:true});", completion: completion)
    }
    private let queue = DispatchQueue(label: "local.desknotes.notes-bridge", qos: .userInitiated)
    static func literal(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
    private static let prelude = """
    var app = Application('Notes');
    function snapshot(n) {
      if (n.passwordProtected()) throw new Error('这篇备忘录已锁定，请在备忘录中查看。');
      return {id:n.id(),name:n.name(),text:n.plaintext(),html:n.body()};
    }
    function byID(id) {
      var n=app.notes.byId(id);
      if (!n.exists()) throw new Error('找不到关联的备忘录。它可能已被删除或移到其他账户，本地记录仍然保留。');
      return n;
    }
    """
    func execute(_ body: String, completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        let source = Self.prelude + "\nfunction run(){try{\n" + body + "\n}catch(e){return JSON.stringify({ok:false,error:String(e)});}}"
        queue.async {
            let result: Result<BridgeReply, Error> = Result {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-l", "JavaScript", "-"]
                let input = Pipe(), output = Pipe(), errors = Pipe()
                process.standardInput = input; process.standardOutput = output; process.standardError = errors
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 35, execute: timeout)
                input.fileHandleForWriting.write(source.data(using: .utf8)!)
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit(); timeout.cancel()
                guard process.terminationStatus == 0, !data.isEmpty else {
                    // Do not expose note bodies or raw script sources in logs/errors.
                    throw NSError(domain: "DeskNotes.Notes", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "备忘录连接未完成。请确认已允许旁白控制备忘录，然后重试；本地便笺已保存。"])
                }
                let reply = try JSONDecoder().decode(BridgeReply.self, from: data)
                if !reply.ok && reply.conflict != true {
                    let raw = reply.error ?? "无法访问备忘录。"
                    let message = raw.contains("1743") || raw.lowercased().contains("not authorized") ? "尚未获得备忘录访问权限。请在系统设置 → 隐私与安全性 → 自动化中允许旁白访问备忘录。" : raw
                    throw NSError(domain: "DeskNotes.Notes", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
                }
                return reply
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func selected(completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        execute("var selected=app.selection(); if(!selected.length) throw new Error('请先在苹果备忘录中单击选中一篇笔记，再使用此命令。'); return JSON.stringify({ok:true,note:snapshot(selected[0])});", completion: completion)
    }
    func fetch(_ id: String, completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        execute("return JSON.stringify({ok:true,note:snapshot(byID(\(Self.literal(id))))});", completion: completion)
    }
    func write(_ id: String, expectedHTML: String, text: String, completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        writeHTML(id, expectedHTML: expectedHTML, html: noteHTML(text, fontSize: plainNoteFormat(expectedHTML)?.fontSize), completion: completion)
    }
    func writeHTML(_ id: String, expectedHTML: String, html: String, completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        execute("""
        var n=byID(\(Self.literal(id)));
        if(n.body()!==\(Self.literal(expectedHTML))) return JSON.stringify({ok:false,conflict:true});
        n.body=\(Self.literal(html));
        return JSON.stringify({ok:true,note:snapshot(n)});
        """, completion: completion)
    }
    func create(text: String, html: String? = nil, completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        execute("""
        var account=app.defaultAccount();
        var folder=account.folders.whose({name:'桌边'});
        if(!folder.length){account.folders.push(app.Folder({name:'桌边'}));folder=account.folders.whose({name:'桌边'});}
        var n=app.Note({body:\(Self.literal(html ?? noteHTML(text.isEmpty ? "新便笺" : text)))});
        folder[0].notes.push(n);
        return JSON.stringify({ok:true,note:snapshot(n)});
        """, completion: completion)
    }
    func show(_ id: String, completion: @escaping (Result<BridgeReply, Error>) -> Void) {
        execute("var n=byID(\(Self.literal(id)));app.show(n);app.activate();return JSON.stringify({ok:true});", completion: completion)
    }
}
