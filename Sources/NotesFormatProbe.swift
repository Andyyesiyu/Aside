import AppKit

func runNotesFormatProbe(bridge: NotesBridge, directory: URL, completion: @escaping () -> Void) {
    let file = directory.appendingPathComponent("rich-test-fixture.json")
    guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(RemoteNote.self, from: data), saved.name.hasPrefix("桌边格式测试 ") else { completion(); return }
    let title = htmlEscape(saved.name)
    let variants = [
        "<div>\(title)</div><ul><li>待办：战斗</li><li> </li></ul><div><br></div><div><br></div><div>下一段</div>",
        "<div>\(title)</div><ul><li>待办：战斗</li><li><br></li></ul><div><br></div><div><br></div><div>下一段</div>",
        "<div>\(title)</div><div>正文</div><div><br></div><div><br></div><div>下一段</div>"
    ]
    var outputs: [[String: String]] = []
    func step(_ index: Int, _ remote: RemoteNote) {
        guard index < variants.count else {
            if let encoded = try? JSONSerialization.data(withJSONObject: outputs, options: [.prettyPrinted, .sortedKeys]) { try? encoded.write(to: directory.appendingPathComponent("format-probe.json"), options: .atomic) }
            if let encoded = try? JSONEncoder().encode(remote) { try? encoded.write(to: file, options: .atomic) }
            completion(); return
        }
        bridge.writeHTML(remote.id, expectedHTML: remote.html, html: variants[index]) { response in
            guard case .success(let reply) = response, let updated = reply.note else { completion(); return }
            outputs.append(["input": variants[index], "output": updated.html])
            step(index + 1, updated)
        }
    }
    bridge.fetch(saved.id) { response in
        guard case .success(let reply) = response, let current = reply.note, current.name == saved.name else { completion(); return }
        step(0, current)
    }
}
