import Foundation

// Opt-in integration test. Creates only its own synthetic note, never enumerates personal notes.
func runNotesIntegrationTest(bridge: NotesBridge, directory: URL, completion: @escaping () -> Void = {}) {
    let file = directory.appendingPathComponent("notes-test-result.txt")
    func result(_ text: String) {
        try? text.write(to: file, atomically: true, encoding: .utf8)
        if text != "RUNNING" { completion() }
    }
    result("RUNNING")
    let fixture = directory.appendingPathComponent("notes-test-fixture.json")
    let existing = (try? Data(contentsOf: fixture)).flatMap { try? JSONDecoder().decode(RemoteNote.self, from: $0) }
    let title = existing?.name ?? "桌边连接测试 \(UUID().uuidString.prefix(8))"
    let verify: (Result<BridgeReply, Error>) -> Void = { created in
        guard case .success(let reply) = created, let note = reply.note else { result("FAIL create: \(created)"); return }
        guard note.name == title && title.hasPrefix("桌边连接测试 ") else { result("FAIL test note identity"); return }
        if let data = try? JSONEncoder().encode(note) { try? data.write(to: fixture, options: .atomic) }
        bridge.fetch(note.id) { fetched in
            guard case .success(let reply) = fetched, let current = reply.note,
                  normalized(current.text).contains(title) else { result("FAIL fetch"); return }
            let text = title + "\n英文 Geneva + 中文 Fusion Pixel\n同步测试：<>&\"\n这篇测试笔记可以自行删除。"
            bridge.write(note.id, expectedHTML: current.html, text: text) { written in
                guard case .success(let reply) = written, let updated = reply.note,
                      normalized(updated.text) == text else { result("FAIL write or round-trip"); return }
                bridge.write(note.id, expectedHTML: "stale-baseline", text: "SHOULD NOT OVERWRITE") { stale in
                    // Reusing a fixture can produce identical HTML; an intentionally stale baseline still must be rejected.
                    guard case .success(let reply) = stale, reply.conflict == true else { result("FAIL conflict protection"); return }
                    bridge.fetch(note.id) { verified in
                        guard case .success(let reply) = verified, let last = reply.note,
                              normalized(last.text) == text else { result("FAIL preserved content"); return }
                        runLiveSyncDirections(remote: last, directory: directory, bridge: bridge) { checked in
                            switch checked {
                            case .failure(let error): result("FAIL: \(error.localizedDescription)")
                            case .success(let verified):
                                if let data = try? JSONEncoder().encode(verified) { try? data.write(to: fixture, options: .atomic) }
                                result("PASS: create, fetch, write, Chinese and special characters, stale-write rejection.\nPASS: AppDelegate local-to-Notes, Notes-to-local, concurrent conflict preserves both copies.\nPlain text editable: \(simpleHTML(verified.html))\nTest title: \(title)")
                            }
                        }
                    }
                }
            }
        }
    }
    if let existing = existing { bridge.fetch(existing.id, completion: verify) }
    else { bridge.create(text: title + "\n这是自动生成的测试笔记。", completion: verify) }
}
