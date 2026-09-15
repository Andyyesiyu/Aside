import AppKit

struct EdgeReveal {
    var concealed = true
    var outsideSince: TimeInterval?

    mutating func update(inside: Bool, keepOpen: Bool, now: TimeInterval) {
        // Pointer motion may dismiss a panel, but never reveals it.
        guard !concealed else { return }
        if inside || keepOpen { outsideSince = nil; return }
        if let since = outsideSince {
            if now - since >= 0.65 { concealed = true; outsideSince = nil }
        } else { outsideSince = now }
    }
}

extension AppDelegate {
    func startVisibilityTracking() {
        edgeState.concealed = store.book.preferences.shouldAutoHide
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.checkAutoHide() }
        edgeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
    }
    func stopVisibilityTracking() { edgeTimer?.invalidate(); edgeTimer = nil }
    @objc func menuBegan() { trackingMenus += 1 }
    @objc func menuEnded() { trackingMenus = max(0, trackingMenus - 1) }
    func checkAutoHide(at point: NSPoint = NSEvent.mouseLocation, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard store.book.preferences.shouldAutoHide, let panel = panel, !edgeState.concealed else { return }
        let windows: [NSWindow] = [panel] + desktopPanels.compactMap { id, window in
            store.note(id)?.isPinned == false ? window : nil
        }
        let overHandle = edgeHandle?.containsPointer(point) == true || extraHandles.values.contains { $0.containsPointer(point) }
        let inside = overHandle || windows.contains { $0.isVisible && $0.frame.insetBy(dx: -72, dy: -72).contains(point) }
        let editing = windows.contains { window in
            guard window.isKeyWindow, let editor = window.firstResponder as? NoteTextView else { return false }
            return editor.hasMarkedText() || ProcessInfo.processInfo.systemUptime - editor.lastKeyboardInput < 0.35
        }
        let keepOpen = editing || trackingMenus > 0 || NSEvent.pressedMouseButtons != 0 || NSApp.modalWindow != nil
        let previous = edgeState.concealed
        edgeState.update(inside: inside, keepOpen: keepOpen, now: now)
        if previous != edgeState.concealed { updateVisibility() }
    }
    func updateVisibility() {
        for (id, transition) in desktopTransitions {
            guard let note = store.note(id) else { continue }
            let visible = !hidden && !note.archived && (note.isPinned || !store.book.preferences.shouldAutoHide || !edgeState.concealed)
            transition.setVisible(visible, animated: animateDesktopVisibility)
        }
        let empty = !store.book.notes.contains { !$0.archived && $0.desktopPosition == nil }
        let concealed = hidden || empty || (store.book.preferences.shouldAutoHide && edgeState.concealed)
        let screens = NSScreen.screens
        let ids = Set(screens.map { screenID($0) })
        for id in Array(extraHandles.keys) where !ids.contains(id) { extraHandles[id]?.hide(); extraHandles.removeValue(forKey: id) }
        for (index, screen) in screens.enumerated() where edgeHandle != nil {
            let id = screenID(screen)
            let handle: EdgeHandle
            if index == 0, let primary = edgeHandle { handle = primary }
            else {
                if extraHandles[id] == nil { extraHandles[id] = EdgeHandle() }
                handle = extraHandles[id]!
            }
            // A screen that becomes primary no longer needs its previous extra handle.
            if index == 0 { extraHandles[id]?.hide(); extraHandles.removeValue(forKey: id) }
            handle.onOpen = { [weak self] in
                guard let self = self else { return }
                self.store.book.preferences.screenID = id; self.store.saveSoon(); self.openFromHandle()
            }
            handle.onCommandClick = { [weak self] in
                guard let self = self else { return }
                self.store.book.preferences.screenID = id
                self.toggleFixedPresentation()
            }
            handle.isFixedMode = store.book.preferences.fixedMode
            handle.onToggleFixedMode = { [weak self] in
                guard let self = self else { return }
                self.setFixedMode(!self.store.book.preferences.fixedMode)
            }
            handle.onPositionChanged = { [weak self] position in
                self?.store.book.preferences.handlePositions[id] = position
                self?.store.saveSoon()
            }
            handle.update(screen: screen, side: store.book.preferences.side, behavior: panel.collectionBehavior,
                          visible: store.book.preferences.fixedMode || concealed || selectedScreen().map { screenID($0) != id } == true, position: store.book.preferences.handlePositions[id])
        }
        if let transition = visibilityTransition {
            transition.side = store.book.preferences.side
            transition.setVisible(!concealed, animated: !empty)
        } else if concealed {
            panel.orderOut(nil)
        } else if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func toggleFixedPresentation() {
        if store.book.preferences.fixedMode && !hidden {
            store.book.preferences.fixedMode = false
            hidden = true
            edgeState = EdgeReveal(concealed: true)
            settingsChanged()
        } else {
            setFixedMode(true)
        }
    }
    func setFixedMode(_ enabled: Bool) {
        store.book.preferences.fixedMode = enabled
        if enabled {
            hidden = false
            store.book.preferences.collapsed = false
            for index in store.book.notes.indices where !store.book.notes[index].archived {
                store.book.notes[index].collapsed = false
            }
        }
        edgeState = EdgeReveal(concealed: false)
        settingsChanged()
    }
    func autoHideChanged(_ enabled: Bool) {
        store.book.preferences.autoHide = enabled
        edgeState = EdgeReveal(concealed: enabled)
        hidden = false
        settingsChanged()
    }
}
