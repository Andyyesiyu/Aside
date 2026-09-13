import AppKit

func runRichLiveTests(bridge: NotesBridge, directory: URL, completion: @escaping () -> Void) {
    let resultFile = directory.appendingPathComponent("rich-test-result.txt")
    let fixtureFile = directory.appendingPathComponent("rich-test-fixture.json")
    func report(_ value: String) { try? value.write(to: resultFile, atomically: true, encoding: .utf8); completion() }
    try? "RUNNING".write(to: resultFile, atomically: true, encoding: .utf8)
    let saved = (try? Data(contentsOf: fixtureFile)).flatMap { try? JSONDecoder().decode(RemoteNote.self, from: $0) }
    let title = saved?.name ?? "桌边格式测试 \(UUID().uuidString.prefix(8))"
    let fixtureHTML = "<h1>\(title)</h1><div><b>粗体内容</b> <i>斜体内容</i> <s>删除线内容</s></div><h2>小标题</h2><ul><li>事项一<ul><li>嵌套事项<ul><li>三级事项<ul><li>四级事项<ul><li>五级事项</li></ul></li></ul></li></ul></li></ul></li><li>事项二</li></ul><div>编号步骤</div><ol><li>步骤一</li><li>步骤二</li></ol><div>https://example.com/path?a=1&amp;b=2</div>"
    func save(_ remote: RemoteNote) { if let data = try? JSONEncoder().encode(remote) { try? data.write(to: fixtureFile, options: .atomic) } }
    func features(_ doc: RichDocument) -> Bool {
        let runs = doc.blocks.flatMap(\.runs)
        return runs.contains { $0.style.bold && $0.style.css["font-size"] == "16px" }
            && runs.contains { $0.style.bold && $0.style.css["font-size"] == "12px" }
            && doc.blocks.contains { $0.style.lists.count == 2 }
            && doc.blocks.contains { $0.style.lists.count == 5 }
            && doc.blocks.contains { $0.style.lists.last?.tag == "ol" && $0.style.lists.last?.start == 1 }
            && runs.contains { $0.style.bold } && runs.contains { $0.style.italic }
            && runs.contains { $0.style.strike }
            && doc.text.contains("https://example.com/path?a=1&b=2")
    }
    let exercise: (Result<BridgeReply, Error>) -> Void = { response in
        guard case .success(let reply) = response, let remote = reply.note else { report("FAIL: create or reset test note: \(response)"); return }
        guard remote.name == title && title.hasPrefix("桌边格式测试 ") else { report("FAIL: test identity"); return }
        save(remote)
        guard case .success(let doc) = RichDocument.parseNotes(remote.html) else {
            report("FAIL: parse returned Notes HTML: \(RichDocument.parseNotes(remote.html))"); return
        }
        guard features(doc) else { report("FAIL: Notes normalized initial format unexpectedly"); return }
        do {
            let store = try NoteStore(directory: directory.appendingPathComponent("rich-controller-test"))
            let controller = AppDelegate(store: store); controller.syncQuietInterval = 0; controller.syncEnabled = false
            let note = Note(text: remote.text); store.book.notes = [note]
            controller.applyRemote(note.id, remote: remote, replaceText: true)
            let card = NoteCard(note: store.note(note.id)!, owner: controller)
            card.frame = NSRect(x: 0, y: 0, width: 400, height: 550); card.layoutSubtreeIfNeeded()
            controller.cards[note.id] = card
            if CommandLine.arguments.contains("--desktop-test") {
                controller.panel = EdgePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                let screen = NSScreen.screens[0].visibleFrame
                controller.dragCard(note.id, topLeft: NSPoint(x: screen.midX, y: screen.maxY - 80))
                card.layoutSubtreeIfNeeded()
            }
            guard card.editor.isEditable else { report("FAIL: imported rich note still read-only"); return }
            func syncThen(_ next: @escaping () -> Void) {
                controller.syncEnabled = true; controller.sync(note.id)
                let deadline = Date().addingTimeInterval(45)
                func poll() {
                    if !controller.inFlight.contains(note.id) { controller.syncEnabled = false; next(); return }
                    if Date() > deadline { report("FAIL: sync timeout"); return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
                }
                poll()
            }
            let selection = (card.editor.string as NSString).range(of: "粗体内容")
            card.editor.setSelectedRange(selection)
            card.editor.typingAttributes = card.editor.textStorage!.attributes(at: selection.location, effectiveRange: nil)
            card.editor.insertText("编辑后的粗体内容", replacementRange: selection)
            syncThen {
                guard controller.syncIssues[note.id] == nil else {
                    bridge.fetch(remote.id) { response in
                        if case .success(let reply) = response, let returned = reply.note {
                            let expected = store.note(note.id)!.effectiveDocument.notesSignature
                            let actual = (try? RichDocument.parseNotes(returned.html).get().notesSignature) ?? []
                            let debug = ["expected": expected, "actual": actual, "html": [returned.html]]
                            if let data = try? JSONEncoder().encode(debug) { try? data.write(to: directory.appendingPathComponent("signature-debug.json")) }
                        }
                        report("FAIL: rich text push issue: \(controller.syncIssues[note.id] ?? "unknown")")
                    }
                    return
                }
                bridge.fetch(remote.id) { response in
                    guard case .success(let reply) = response, let pushed = reply.note,
                          case .success(let updated) = RichDocument.parseNotes(pushed.html), features(updated),
                          updated.blocks.flatMap(\.runs).contains(where: { $0.text.contains("编辑后的粗体内容") && $0.style.bold }) else { report("FAIL: rich push did not preserve formatting"); return }
                    save(pushed)
                    card.update(store.note(note.id)!)
                    let range = (card.editor.string as NSString).range(of: "斜体内容")
                    card.editor.setSelectedRange(range); card.editor.formatInline(\.bold)
                    syncThen {
                        guard controller.syncIssues[note.id] == nil else { report("FAIL: format-only push issue"); return }
                        bridge.fetch(remote.id) { response in
                            guard case .success(let reply) = response, let formatted = reply.note,
                                  case .success(var remoteDoc) = RichDocument.parseNotes(formatted.html),
                                  remoteDoc.blocks.flatMap(\.runs).contains(where: { $0.text.contains("斜体内容") && $0.style.bold && $0.style.italic }) else { report("FAIL: format-only edit not synced"); return }
                            for i in remoteDoc.blocks.indices { for j in remoteDoc.blocks[i].runs.indices {
                                remoteDoc.blocks[i].runs[j].text = remoteDoc.blocks[i].runs[j].text.replacingOccurrences(of: "嵌套事项", with: "远端更新的嵌套事项")
                            } }
                            bridge.writeHTML(remote.id, expectedHTML: formatted.html, html: remoteDoc.notesHTML()) { response in
                                guard case .success(let reply) = response, let changed = reply.note else { report("FAIL: remote edit"); return }
                                syncThen {
                                    guard controller.syncIssues[note.id] == nil, let current = store.note(note.id), current.text.contains("远端更新的嵌套事项"), features(current.effectiveDocument) else { report("FAIL: rich remote pull"); return }
                                    var localConflict = current.effectiveDocument
                                    localConflict.blocks[0].runs[0].style.underline.toggle()
                                    controller.richTextChanged(note.id, document: localConflict)
                                    var external = remoteDoc
                                    external.blocks[0].runs[0].style.strike.toggle()
                                    bridge.writeHTML(remote.id, expectedHTML: changed.html, html: external.notesHTML()) { response in
                                        guard case .success(let reply) = response, let conflictRemote = reply.note else { report("FAIL: prepare format conflict"); return }
                                        syncThen {
                                            guard controller.syncIssues[note.id] != nil, store.note(note.id)?.effectiveDocument == localConflict.canonical else { report("FAIL: format conflict lost local version"); return }
                                            bridge.fetch(remote.id) { response in
                                                guard case .success(let reply) = response, let last = reply.note, last.html == conflictRemote.html else { report("FAIL: format conflict overwrote remote version"); return }
                                                save(last); try? store.flush()
                                                report("PASS: heading typography, bold, italic, strikethrough, five-level nested bullets, separated numbered list and visible URL.\nPASS: native text edit -> Notes, format-only edit -> Notes, Notes -> rich local document, format-only conflict preserves both versions.\nTest title: \(title)")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch { report("FAIL: \(error.localizedDescription)") }
    }
    if let saved = saved {
        bridge.fetch(saved.id) { response in
            guard case .success(let reply) = response, let current = reply.note, current.name == title else { report("FAIL: existing test identity"); return }
            bridge.writeHTML(current.id, expectedHTML: current.html, html: fixtureHTML, completion: exercise)
        }
    } else { bridge.create(text: title, html: fixtureHTML, completion: exercise) }
}
