import AppKit

// Read-only, opt-in diagnosis of the most recent backed-up write; never exports note bodies.
func diagnoseLatestSync(directory: URL, output: URL, completion: @escaping () -> Void) {
    struct Backup: Decodable { var remote: RemoteNote; var local: Note }
    func finish(_ message: String) { try? message.write(to: output, atomically: true, encoding: .utf8); completion() }
    do {
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("sync-backups"), includingPropertiesForKeys: [.contentModificationDateKey])
        guard let latest = try files.filter({ $0.pathExtension == "json" }).sorted(by: { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate! > $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate! }).first else { finish("No backup"); return }
        let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: latest))
        let book = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: directory.appendingPathComponent("notebook.json")))
        guard let current = book.notes.first(where: { $0.id == backup.local.id }), current.remoteID == backup.remote.id else { finish("Latest backup no longer linked"); return }
        let bridge = NotesBridge()
        bridge.fetch(backup.remote.id) { [bridge] reply in
            _ = bridge
            guard case .success(let response) = reply, let remote = response.note,
                  let actual = try? RichDocument.parseNotes(remote.html).get() else { finish("Fetch or parse failed"); return }
            let expected = backup.local.effectiveDocument
            var rows = ["Current matches submitted: \(current.effectiveDocument == expected)", "Remote matches prior HTML: \(remote.html == backup.remote.html)", "Signature equal: \(expected.notesSignature == actual.notesSignature)", "Blocks: \(expected.blocks.count) -> \(actual.blocks.count)"]
            let xAll = expected.blocks.flatMap(\.runs).map(\.text).joined(), yAll = actual.blocks.flatMap(\.runs).map(\.text).joined()
            rows.append("All text equal ignoring whitespace: \(xAll.filter { !$0.isWhitespace } == yAll.filter { !$0.isWhitespace })")
            let delta = Array(yAll).difference(from: Array(xAll))
            for change in delta {
                switch change {
                case .remove(_, let c, _): rows.append("Removed scalar: " + c.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ","))
                case .insert(_, let c, _): rows.append("Inserted scalar: " + c.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ","))
                }
            }
            for i in 0..<min(expected.blocks.count, actual.blocks.count) where expected.notesSignature[i] != actual.notesSignature[i] {
                let a = expected.blocks[i], b = actual.blocks[i]
                let x = a.runs.map(\.text).joined(), y = b.runs.map(\.text).joined()
                func normalizeSpaces(_ s: String) -> String { s.replacingOccurrences(of: "\u{00a0}", with: " ") }
                func styles(_ block: RichBlock) -> [String] {
                    Array(Set(block.runs.filter { !$0.text.isEmpty }.map { "bold=\($0.style.bold), italic=\($0.style.italic), strike=\($0.style.strike), size=\($0.style.css["font-size"] ?? "default")" })).sorted()
                }
                rows.append("Block \(i): chars \(x.count)->\(y.count); textEqual=\(x == y); NBSP-only=\(normalizeSpaces(x) == normalizeSpaces(y)); whitespaceOnly=\(x.filter { !$0.isWhitespace } == y.filter { !$0.isWhitespace }); tag \(a.style.tag)->\(b.style.tag); depth \(a.style.lists.count)->\(b.style.lists.count); styles \(styles(a))->\(styles(b))")
            }
            finish(rows.joined(separator: "\n"))
        }
    } catch { finish("Local diagnosis failed") }
}

// Only inspect the latest linked note. Output state flags, never titles or text.
func diagnoseCurrentSync(directory: URL, output: URL, completion: @escaping () -> Void) {
    func finish(_ value: String) { try? value.write(to: output, atomically: true, encoding: .utf8); completion() }
    do {
        let book = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: directory.appendingPathComponent("notebook.json")))
        guard let note = book.notes.filter({ $0.remoteID != nil }).sorted(by: { $0.modified > $1.modified }).first else { finish("No linked note"); return }
        let bridge = NotesBridge()
        bridge.fetch(note.remoteID!) { [bridge] reply in
            _ = bridge
            guard case .success(let response) = reply, let remote = response.note else { finish("Remote fetch failed"); return }
            let parsed = try? RichDocument.parseNotes(remote.html).get().canonical
            finish([
                "Paused: \(note.pendingSync != nil)",
                "Read only: \(note.effectiveReadOnly)",
                "Local equals baseline: \(note.effectiveDocument == note.baselineDocument)",
                "Local signature equals baseline: \(note.effectiveDocument.notesSignature == note.baselineDocument.notesSignature)",
                "Remote HTML equals baseline: \(remote.html == note.baseHTML)",
                "Remote signature equals baseline: \(parsed?.notesSignature == note.baselineDocument.notesSignature)",
                "Remote signature equals local: \(parsed?.notesSignature == note.effectiveDocument.notesSignature)",
                "Remote parses: \(parsed != nil)",
                "Quiet interval elapsed: \(Date().timeIntervalSince(note.modified) > 1.5)"
            ].joined(separator: "\n"))
        }
    } catch { finish("Local read failed") }
}
