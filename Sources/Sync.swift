import AppKit

extension AppDelegate {
    func startSyncPolling(interval: TimeInterval = 5) {
        timer?.invalidate()
        guard syncEnabled else { timer = nil; return }
        let poll = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.syncAll() }
        timer = poll
        // Keep remote reads running while a menu or another tracking loop is active.
        RunLoop.main.add(poll, forMode: .common)
        syncAll()
    }
    func stopSyncPolling() {
        timer?.invalidate(); timer = nil
        deferred.values.forEach { $0.cancel() }; deferred.removeAll()
    }
    @objc func syncAfterWake() { syncAll() }

    func scheduleSync(_ id: UUID) {
        deferred[id]?.cancel()
        guard syncEnabled, let n = store.note(id), n.remoteID != nil, n.pendingSync == nil, !n.effectiveReadOnly else { return }
        let work = DispatchWorkItem { [weak self] in self?.sync(id) }
        deferred[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
    func syncAll(manual: Bool = false) {
        guard syncEnabled else { return }
        for n in store.book.notes where n.remoteID != nil { sync(n.id, manual: manual) }
    }
    func sync(_ id: UUID, manual: Bool = false) {
        guard syncEnabled, !inFlight.contains(id), let before = store.note(id), let remoteID = before.remoteID,
              cards[id]?.editor.hasMarkedText() != true else { return }
        if let pending = before.pendingSync, !manual {
            syncIssues[id] = pending.problem; return
        }
        if !manual && Date().timeIntervalSince(before.modified) < syncQuietInterval { scheduleSync(id); return }
        inFlight.insert(id)
        bridge.fetch(remoteID) { [weak self] result in
            guard let self = self else { return }
            guard self.store.note(id)?.remoteID == remoteID else { self.inFlight.remove(id); return }
            switch result {
            case .failure(let error): self.finishSync(id, issue: error.localizedDescription, manual: manual)
            case .success(let reply):
                guard let remote = reply.note, let current = self.store.note(id) else { self.inFlight.remove(id); return }
                if let pending = current.pendingSync {
                    if let received = try? RichDocument.parseNotes(remote.html).get(), (received.notesSignature == pending.sent.notesSignature || received.notesSignature == current.effectiveDocument.notesSignature) {
                        let unchanged = current.effectiveDocument.notesSignature == received.notesSignature && self.cards[id]?.editor.hasMarkedText() != true
                        self.applyRemote(id, remote: remote, replaceText: unchanged)
                        self.finishSync(id)
                        if !unchanged { self.scheduleSync(id) }
                    } else {
                        self.holdSync(id, returned: remote, message: syncDifferenceMessage(sent: pending.sent, returnedHTML: remote.html))
                        self.finishSync(id, issue: self.store.note(id)?.pendingSync?.problem, manual: manual)
                    }
                    return
                }
                let decision = decideSync(local: packed(current.effectiveDocument), baseline: packed(before.baselineDocument),
                                          remoteHTML: remote.html, baselineHTML: before.baseHTML ?? "", readOnly: before.effectiveReadOnly)
                switch decision {
                case .unchanged, .readOnly:
                    if current.richDocument == nil && !current.effectiveReadOnly {
                        self.applyRemote(id, remote: remote, replaceText: true)
                    } else { self.store.update(id) { $0.readOnly = RichDocument.notesIssue(remote.html) != nil } }
                    self.finishSync(id)
                case .conflict:
                    self.holdSync(id, returned: remote, message: "本地和备忘录都已修改，已暂停自动回写。两份内容均已保留，请选择如何处理。")
                    self.finishSync(id, issue: self.store.note(id)?.pendingSync?.problem, manual: manual)
                case .pull:
                    guard self.cards[id]?.editor.hasMarkedText() != true else { self.inFlight.remove(id); return }
                    self.applyRemote(id, remote: remote, replaceText: true)
                    self.finishSync(id)
                case .push:
                    guard self.cards[id]?.editor.hasMarkedText() != true else { self.inFlight.remove(id); return }
                    if !manual && Date().timeIntervalSince(current.modified) < self.syncQuietInterval {
                        self.inFlight.remove(id); self.scheduleSync(id); return
                    }
                    let sent = current.effectiveDocument
                    if let issue = RichDocument.notesIssue(remote.html) ?? sent.notesWriteIssue {
                        self.finishSync(id, issue: issue, manual: manual); return
                    }
                    do {
                        // Keep both the exact source HTML and the local rich version before mutation.
                        let archive = self.store.directory.appendingPathComponent("sync-backups", isDirectory: true)
                        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
                        let backup = SyncFormatBackup(remote: remote, local: current)
                        try JSONEncoder().encode(backup).write(to: archive.appendingPathComponent("\(id)-\(UUID()).json"), options: .atomic)
                        self.store.update(id) { $0.pendingSync = PendingSync(sent: sent) }
                        try self.store.flush()
                    } catch { self.finishSync(id, issue: "同步前备份失败，已停止回写。", manual: manual); return }
                    self.bridge.writeHTML(remoteID, expectedHTML: remote.html, html: sent.notesHTML()) { result in
                        guard self.store.note(id)?.remoteID == remoteID else { self.inFlight.remove(id); return }
                        switch result {
                        case .failure(let error):
                            self.holdSync(id, returned: nil, message: "写入结果未能确认，已暂停自动回写。" + error.localizedDescription)
                            self.finishSync(id, issue: self.store.note(id)?.pendingSync?.problem, manual: manual)
                        case .success(let written):
                            guard !((written.conflict) ?? false), let updated = written.note else {
                                self.holdSync(id, returned: written.note, message: "备忘录在保存前再次变化，已暂停自动回写。两份内容均已保留。")
                                self.finishSync(id, issue: self.store.note(id)?.pendingSync?.problem, manual: manual); return
                            }
                            guard let received = try? RichDocument.parseNotes(updated.html).get(), received.notesSignature == sent.notesSignature else {
                                self.holdSync(id, returned: updated, message: syncDifferenceMessage(sent: sent, returnedHTML: updated.html))
                                self.finishSync(id, issue: self.store.note(id)?.pendingSync?.problem, manual: manual); return
                            }
                            let unchanged = self.store.note(id)?.effectiveDocument == sent && self.cards[id]?.editor.hasMarkedText() != true
                            self.applyRemote(id, remote: updated, replaceText: unchanged)
                            self.finishSync(id)
                            if !unchanged { self.scheduleSync(id) }
                        }
                    }
                }
            }
        }
    }
    func applyRemote(_ id: UUID, remote: RemoteNote, replaceText: Bool) {
        let doc = try? RichDocument.parseNotes(remote.html).get().canonical
        store.update(id) {
            $0.pendingSync = nil
            $0.remoteID = remote.id; $0.baseHTML = remote.html
            $0.baseRichDocument = doc; $0.baseText = doc?.text ?? normalized(remote.text)
            $0.readOnly = RichDocument.notesIssue(remote.html) != nil
            if replaceText { $0.text = doc?.text ?? normalized(remote.text); $0.richDocument = doc }
        }
    }
    func holdSync(_ id: UUID, returned: RemoteNote?, message: String) {
        store.update(id) {
            if $0.pendingSync == nil { $0.pendingSync = PendingSync(sent: $0.effectiveDocument) }
            $0.pendingSync?.problem = message
            $0.pendingSync?.returnedHTML = returned?.html
            $0.pendingSync?.returnedText = returned?.text
        }
        store.flushReporting()
    }
    func finishSync(_ id: UUID, issue: String? = nil, manual: Bool = false) {
        inFlight.remove(id); syncIssues[id] = issue ?? store.note(id)?.pendingSync?.problem; store.flushReporting(); refresh()
        if manual, let issue = issue { alert("同步需要处理", issue) }
    }
    func importSelected() {
        bridge.selected { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error): self.alert("无法贴上备忘录", error.localizedDescription)
            case .success(let reply):
                guard let remote = reply.note else { return }
                if let existing = self.store.book.notes.first(where: { $0.remoteID == remote.id }) { self.restore(existing.id); return }
                let note = Note(text: normalized(remote.text))
                self.store.book.notes.append(note)
                self.applyRemote(note.id, remote: remote, replaceText: true)
                self.store.saveSoon(); self.focus(note.id)
            }
        }
    }
    func createRemote(_ id: UUID) {
        cards[id]?.commitText()
        guard !inFlight.contains(id), let before = store.note(id) else { return }
        inFlight.insert(id)
        let sent = before.effectiveDocument
        if let issue = sent.notesWriteIssue { finishSync(id, issue: issue, manual: true); return }
        bridge.create(text: before.text, html: before.text.isEmpty ? nil : sent.notesHTML()) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error): self.finishSync(id, issue: error.localizedDescription, manual: true)
            case .success(let reply):
                guard let remote = reply.note else { self.inFlight.remove(id); return }
                guard before.text.isEmpty || (try? RichDocument.parseNotes(remote.html).get().notesSignature) == sent.notesSignature else {
                    self.finishSync(id, issue: "新备忘录的格式未完整返回，本地原文已保留，未建立关联。", manual: true); return
                }
                let unchanged = self.store.note(id)?.effectiveDocument == sent && self.cards[id]?.editor.hasMarkedText() != true
                self.applyRemote(id, remote: remote, replaceText: unchanged); self.finishSync(id)
                if !unchanged { self.scheduleSync(id) }
            }
        }
    }
    func showRemote(_ id: UUID) {
        guard let remoteID = store.note(id)?.remoteID else { return }
        bridge.show(remoteID) { [weak self] result in
            if case .failure(let error) = result { self?.alert("无法打开备忘录", error.localizedDescription) }
        }
    }
    func resolveSync(_ id: UUID) {
        guard let note = store.note(id), let issue = syncIssues[id] ?? note.pendingSync?.problem else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "核对两份记录"
        alert.informativeText = issue + "\n\n右侧是上次读取的副本。采用它之前会再次核对远端是否变化，并备份左侧当前内容。"
        let compare = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 290))
        let right = note.pendingSync?.returnedHTML.flatMap { try? RichDocument.parseNotes($0).get() }
            ?? RichDocument(text: note.pendingSync?.returnedText ?? "尚无回读副本，请先重新核对。")
        for (index, value) in [("旁白当前版本", note.effectiveDocument), ("备忘录回读副本", right)].enumerated() {
            let x = CGFloat(index) * 316
            let label = NSTextField(labelWithString: value.0); label.font = .systemFont(ofSize: 12, weight: .medium)
            label.frame = NSRect(x: x, y: 268, width: 304, height: 20); compare.addSubview(label)
            let scroll = NSScrollView(frame: NSRect(x: x, y: 0, width: 304, height: 260))
            scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 284, height: 260))
            text.isEditable = false; text.isSelectable = true; text.isVerticallyResizable = true
            text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width: 8, height: 8)
            text.textStorage?.setAttributedString(value.1.attributed())
            scroll.documentView = text; compare.addSubview(scroll)
        }
        alert.accessoryView = compare
        alert.addButton(withTitle: "保留左侧，另存并关联")
        alert.addButton(withTitle: "采用右侧版本")
        alert.addButton(withTitle: "重新核对")
        alert.addButton(withTitle: "取消")
        alert.buttons[1].isEnabled = note.pendingSync?.returnedHTML != nil
        switch alert.runModal() {
        case .alertFirstButtonReturn: createRemote(id)
        case .alertSecondButtonReturn: adoptReviewedRemote(id, expectedHTML: note.pendingSync!.returnedHTML!)
        case .alertThirdButtonReturn: sync(id, manual: true)
        default: break
        }
    }
    func adoptReviewedRemote(_ id: UUID, expectedHTML: String) {
        guard let remoteID = store.note(id)?.remoteID, !inFlight.contains(id) else { return }
        inFlight.insert(id)
        bridge.fetch(remoteID) { [weak self] response in
            guard let self = self else { return }
            guard let current = self.store.note(id), current.remoteID == remoteID else { self.inFlight.remove(id); return }
            guard case .success(let reply) = response, let remote = reply.note else {
                self.finishSync(id, issue: "未能核对备忘录，未替换本地内容。", manual: true); return
            }
            guard remote.html == expectedHTML else {
                self.holdSync(id, returned: remote, message: "备忘录在核对期间又有修改，未替换本地内容。请重新查看两份记录。")
                self.finishSync(id, issue: self.store.note(id)?.pendingSync?.problem, manual: true); return
            }
            guard self.cards[id]?.editor.hasMarkedText() != true else { self.inFlight.remove(id); return }
            do {
                let archive = self.store.directory.appendingPathComponent("sync-backups", isDirectory: true)
                try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
                try JSONEncoder().encode(SyncFormatBackup(remote: remote, local: current)).write(to: archive.appendingPathComponent("recovery-\(UUID()).json"), options: .atomic)
                self.applyRemote(id, remote: remote, replaceText: true)
                self.finishSync(id)
            } catch { self.finishSync(id, issue: "备份失败，未替换本地内容。", manual: true) }
        }
    }

}

private struct SyncFormatBackup: Codable { var remote: RemoteNote; var local: Note }
