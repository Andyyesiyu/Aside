import AppKit

// Runs only against the synthetic note created by NotesIntegrationTest.
func runLiveSyncDirections(remote: RemoteNote, directory: URL, bridge: NotesBridge, completion: @escaping (Result<RemoteNote, Error>) -> Void) {
    func fail(_ stage: String) { completion(.failure(NSError(domain: "LiveSyncTest", code: 1, userInfo: [NSLocalizedDescriptionKey: stage]))) }
    do {
        let store = try NoteStore(directory: directory.appendingPathComponent("sync-controller-test"))
        let controller = AppDelegate(store: store); controller.syncQuietInterval = 0
        let local = Note(text: normalized(remote.text), remoteID: remote.id, baseHTML: remote.html, baseText: normalized(remote.text), readOnly: !simpleHTML(remote.html))
        store.book.notes = [local]
        func syncThen(_ next: @escaping () -> Void) {
            let deadline = Date().addingTimeInterval(45)
            controller.sync(local.id)
            func poll() {
                if !controller.inFlight.contains(local.id) { next(); return }
                if Date() > deadline { fail("controller sync timed out"); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
            poll()
        }
        let pushed = remote.name + "\n桌边 → 备忘录：已验证"
        store.update(local.id) { $0.text = pushed; $0.richDocument = RichDocument(text: pushed) }
        syncThen {
            guard controller.syncIssues[local.id] == nil, store.note(local.id)?.baseText == pushed, store.note(local.id)?.readOnly == false else { fail("local to Notes sync: \(controller.syncIssues[local.id] ?? "content or flag mismatch")"); return }
            bridge.fetch(remote.id) { response in
                guard case .success(let reply) = response, let updated = reply.note, normalized(updated.text) == pushed else { fail("verify local to Notes"); return }
                let pulled = remote.name + "\n备忘录 → 桌边：已验证"
                controller.startSyncPolling(interval: 0.2)
                bridge.write(remote.id, expectedHTML: updated.html, text: pulled) { response in
                    guard case .success(let reply) = response, let changed = reply.note else { fail("prepare remote edit"); return }
                    let pullDeadline = Date().addingTimeInterval(45)
                    func awaitAutomaticPull() {
                        if store.note(local.id)?.text != pulled || controller.inFlight.contains(local.id) {
                            if Date() > pullDeadline { controller.stopSyncPolling(); fail("automatic remote pull timed out"); return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: awaitAutomaticPull)
                            return
                        }
                        controller.stopSyncPolling()
                        guard controller.syncIssues[local.id] == nil, store.note(local.id)?.text == pulled else { fail("Notes to local sync"); return }
                        let localConflict = remote.name + "\n本地冲突版本"
                        let remoteConflict = remote.name + "\n双向同步及冲突保护验证完成。这篇测试笔记可自行删除。"
                        store.update(local.id) { $0.text = localConflict; $0.richDocument = RichDocument(text: localConflict) }
                        bridge.write(remote.id, expectedHTML: changed.html, text: remoteConflict) { response in
                            guard case .success(let reply) = response, reply.note != nil else { fail("prepare conflict"); return }
                            syncThen {
                                guard controller.syncIssues[local.id] != nil, store.note(local.id)?.text == localConflict else { fail("local conflict preserved"); return }
                                bridge.fetch(remote.id) { response in
                                    guard case .success(let reply) = response, let last = reply.note, normalized(last.text) == remoteConflict else { fail("remote conflict preserved"); return }
                                    try? store.flush()
                                    completion(.success(last))
                                }
                            }
                        }
                    }
                    awaitAutomaticPull()
                }
            }
        }
    } catch { completion(.failure(error)) }
}
