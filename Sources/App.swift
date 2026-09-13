import AppKit
import SwiftUI
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store: NoteStore
    let bridge = NotesBridge()
    var panel: EdgePanel!
    var edgeHandle: EdgeHandle?
    var extraHandles: [String: EdgeHandle] = [:]
    var draggingNotes = Set<UUID>()
    var status: NSStatusItem!
    let viewport = NSScrollView()
    let document = FlippedView()
    var cards: [UUID: NoteCard] = [:]
    var desktopPanels: [UUID: EdgePanel] = [:]
    var desktopTransitions: [UUID: PanelTransition] = [:]
    var animateDesktopVisibility = true
    var selectedID: UUID?
    var syncIssues: [UUID: String] = [:]
    var inFlight = Set<UUID>()
    var deferred: [UUID: DispatchWorkItem] = [:]
    var timer: Timer?
    var prefsWindow: NSWindow?
    var hotKey: EventHotKeyRef?
    var hotHandler: EventHandlerRef?
    var hidden = false
    var edgeState = EdgeReveal()
    var edgeTimer: Timer?
    var trackingMenus = 0
    var visibilityTransition: PanelTransition?
    var syncEnabled = true
    var syncQuietInterval: TimeInterval = 1.5

    init(store: NoteStore) { self.store = store; super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        TypeStyle.register()
        if store.book.notes.isEmpty {
            store.book.notes = [Note(text: "旁白\n\n正在做的事，留在眼前。\n\n直接输入，自动保存。\n双击顶边可以折叠。\n拖动顶边，自由贴到桌面。\n\n⌃⌥N 显示 / 隐藏"), Note(text: "随手记\n\n现在做到哪了？\n下一步从哪里继续？", color: "blue", height: 190)]
            store.saveSoon()
        }
        for note in store.book.notes { if let pending = note.pendingSync { syncIssues[note.id] = pending.problem } }
        selectedID = store.book.notes.first(where: { !$0.archived })?.id
        panel = EdgePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "旁白便笺"; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false; panel.isMovable = false; panel.animationBehavior = .none
        viewport.drawsBackground = false; viewport.contentView.drawsBackground = false; viewport.borderType = .noBorder
        viewport.hasVerticalScroller = true; viewport.autohidesScrollers = true; viewport.scrollerStyle = .overlay
        viewport.documentView = document
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 300))
        host.wantsLayer = true
        viewport.frame = host.bounds; viewport.autoresizingMask = [.width, .height]
        host.addSubview(viewport); panel.contentView = host
        visibilityTransition = PanelTransition(panel: panel, content: viewport)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "旁白")
        status.button?.toolTip = "旁白 — ⌃⌥N 显示或隐藏"
        let menu = NSMenu(); menu.delegate = self; status.menu = menu
        edgeHandle = EdgeHandle()
        edgeHandle?.onOpen = { [weak self] in self?.openFromHandle() }
        setupMainMenu(); registerShortcut(); startVisibilityTracking(); refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        startSyncPolling()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(syncAfterWake), name: NSWorkspace.didWakeNotification, object: nil)
        store.onError = { [weak self] message in self?.alert("本地保存出现问题", message) }
        if let message = store.loadMessage { alert("已恢复记录", message) }
        if CommandLine.arguments.contains("--notes-test") { runNotesIntegrationTest(bridge: bridge, directory: store.directory) }
    }
    func applicationWillTerminate(_ notification: Notification) { stopSyncPolling(); stopVisibilityTracking(); cards.values.forEach { $0.commitText() }; store.flushReporting() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func screenChanged() { refresh() }
    func item(_ title: String, key: String = "", _ action: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        let i = NSMenuItem(title: title, action: #selector(MenuAction.invoke(_:)), keyEquivalent: key)
        i.target = target; i.representedObject = target
        return i
    }
    func setupMainMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "旁白")
        appMenu.addItem(item("关于旁白") { [weak self] in self?.alert("旁白 · Aside 0.11.0", "原生旁白便笺\n英文 Geneva · 中文 Fusion Pixel · 14\n本地自动保存，按需连接苹果备忘录。") })
        appMenu.addItem(item("设置…", key: ",") { [weak self] in self?.showSettings() })
        appMenu.addItem(.separator()); appMenu.addItem(item("退出旁白", key: "q") { NSApp.terminate(nil) })
        appItem.submenu = appMenu; root.addItem(appItem)
        let fileItem = NSMenuItem(); let file = NSMenu(title: "文件")
        file.addItem(item("新建便笺", key: "n") { [weak self] in self?.newNote() })
        file.addItem(item("贴上备忘录中选中的笔记") { [weak self] in self?.importSelected() })
        file.addItem(item("导出所有便笺…") { [weak self] in self?.exportNotes() })
        fileItem.submenu = file; root.addItem(fileItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("重做", "redo:", "Z"), ("剪切", "cut:", "x"), ("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = edit; root.addItem(editItem)
        let formatItem = NSMenuItem(); let format = NSMenu(title: "格式")
        format.addItem(NSMenuItem(title: "将 Markdown 转为格式", action: #selector(NoteTextView.renderMarkdown(_:)), keyEquivalent: ""))
        format.addItem(.separator())
        for (label, key, path) in [("加粗", "b", \InlineStyle.bold), ("斜体", "i", \InlineStyle.italic), ("下划线", "u", \InlineStyle.underline)] {
            format.addItem(item(label, key: key) {
                guard let editor = NSApp.keyWindow?.firstResponder as? NoteTextView else { return }; editor.formatInline(path)
            })
        }
        for (label, tag) in [("正文", "div"), ("标题", "h1"), ("二级标题", "h2"), ("三级标题", "h3"), ("四级标题", "h4"), ("五级标题", "h5"), ("六级标题", "h6"), ("项目列表", "ul"), ("编号列表", "ol"), ("引用", "blockquote")] {
            format.addItem(item(label) { [weak self] in
                guard let self = self, let id = self.selectedID else { return }; self.cards[id]?.editor.formatBlock(tag)
            })
        }
        formatItem.submenu = format; root.addItem(formatItem)
        NSApp.mainMenu = root
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("新建便笺", key: "n") { [weak self] in self?.newNote() })
        menu.addItem(item(((visibilityTransition?.targetVisible ?? panel.isVisible) || desktopPanels.values.contains { $0.isVisible }) ? "隐藏便笺    ⌃⌥N" : "显示便笺    ⌃⌥N") { [weak self] in self?.toggleVisible() })
        menu.addItem(item(store.book.preferences.collapsed ? "展开全部" : "折叠全部") { [weak self] in guard let s = self else { return }; s.store.book.preferences.collapsed.toggle(); s.settingsChanged() })
        menu.addItem(.separator())
        for note in store.book.notes.filter({ !$0.archived }) {
            let m = item(note.title) { [weak self] in self?.focus(note.id) }; m.state = selectedID == note.id ? .on : .off; menu.addItem(m)
        }
        let archived = store.book.notes.filter { $0.archived }
        if !archived.isEmpty {
            let m = NSMenuItem(title: "已收走（\(archived.count)）", action: nil, keyEquivalent: "")
            let sub = NSMenu(); archived.forEach { note in sub.addItem(item(note.title) { [weak self] in self?.restore(note.id) }) }; m.submenu = sub; menu.addItem(m)
        }
        menu.addItem(.separator())
        menu.addItem(item("贴上备忘录中选中的笔记") { [weak self] in self?.importSelected() })
        menu.addItem(item("立即同步备忘录") { [weak self] in self?.syncAll(manual: true) })
        menu.addItem(item("导出所有便笺…") { [weak self] in self?.exportNotes() })
        menu.addItem(item("设置…", key: ",") { [weak self] in self?.showSettings() })
        menu.addItem(.separator()); menu.addItem(item("退出旁白", key: "q") { NSApp.terminate(nil) })
    }
    func noteMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu(); guard let note = store.note(id) else { return menu }
        let statusText = note.remoteID == nil ? "本地便笺 · 未关联备忘录" : (note.effectiveReadOnly ? "已关联 · 含暂不支持的内容，只读预览" : "已关联 · 双向同步")
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false; menu.addItem(statusItem); menu.addItem(.separator())
        if note.effectiveReadOnly, let html = note.baseHTML, let reason = RichDocument.notesIssue(html) {
            let reasonItem = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            reasonItem.isEnabled = false; menu.addItem(reasonItem)
        }
        menu.addItem(item(note.isPinned ? "取消钉住" : "钉住便笺") { [weak self] in self?.togglePin(id) })
        menu.addItem(item(note.collapsed ? "展开便笺" : "折叠便笺") { [weak self] in self?.toggleFold(id) })
        menu.addItem(item(note.desktopPosition == nil ? "贴到桌面" : "收回侧边") { [weak self] in
            if note.desktopPosition == nil { self?.detachCard(id) } else { self?.dockCard(id) }
        })
        menu.addItem(item("插入当前时间") { [weak self] in self?.insertTime(id) })
        menu.addItem(sizeMenu(id))
        let colorItem = NSMenuItem(title: "纸张颜色", action: nil, keyEquivalent: ""); let colors = NSMenu()
        for (i, name) in Paper.names.enumerated() {
            let c = item(Paper.labels[i]) { [weak self] in self?.store.update(id) { $0.color = name }; self?.refresh() }
            c.state = note.color == name ? .on : .off; colors.addItem(c)
        }
        colorItem.submenu = colors; menu.addItem(colorItem); menu.addItem(.separator())
        if note.remoteID == nil {
            menu.addItem(item("保存到苹果备忘录并关联") { [weak self] in self?.createRemote(id) })
        } else {
            menu.addItem(item(note.effectiveReadOnly ? "在备忘录中编辑原文" : "在备忘录中打开") { [weak self] in self?.showRemote(id) })
            menu.addItem(item("立即同步") { [weak self] in self?.sync(id, manual: true) })
            if syncIssues[id] != nil { menu.addItem(item("解决同步问题…") { [weak self] in self?.resolveSync(id) }) }
            if note.effectiveReadOnly { menu.addItem(item("复制为可编辑的本地便笺") { [weak self] in self?.duplicate(id) }) }
            menu.addItem(item("取消关联，保留本地内容") { [weak self] in self?.store.update(id) {
                $0.richDocument = $0.effectiveReadOnly ? RichDocument(text: $0.text) : $0.effectiveDocument
                $0.remoteID = nil; $0.baseText = nil; $0.baseHTML = nil; $0.baseRichDocument = nil; $0.pendingSync = nil; $0.readOnly = false
            }; self?.syncIssues[id] = nil; self?.refresh() })
        }
        menu.addItem(.separator()); menu.addItem(item("收走便笺") { [weak self] in self?.archive(id) })
        return menu
    }
    func selectedScreen() -> NSScreen? {
        NSScreen.screens.first { screenID($0) == store.book.preferences.screenID ||
            String(describing: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "main") == store.book.preferences.screenID } ?? NSScreen.screens.first
    }
    func screenID(_ screen: NSScreen) -> String { ScreenLayout.id(screen) }
    func refresh() {
        guard panel != nil, let screen = selectedScreen() else { return }
        let visible = store.book.notes.filter { !$0.archived }
        let ids = Set(visible.map(\.id))
        for id in Array(cards.keys) where !ids.contains(id) { cards[id]?.removeFromSuperview(); cards.removeValue(forKey: id) }
        for id in Array(desktopPanels.keys) where !ids.contains(id) || store.note(id)?.desktopPosition == nil {
            cards[id]?.removeFromSuperview()
            desktopTransitions.removeValue(forKey: id)
            desktopPanels[id]?.orderOut(nil); desktopPanels.removeValue(forKey: id)
        }
        panel.level = store.book.preferences.floatOnTop ? .floating : .normal
        var desktopBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        if store.book.preferences.allSpaces { desktopBehavior.insert(.canJoinAllSpaces) }
        if #available(macOS 13.0, *) { desktopBehavior.insert(.canJoinAllApplications) }
        panel.collectionBehavior = desktopBehavior
        let width = visible.filter { $0.desktopPosition == nil }.map { NoteSizing.width($0, defaultWidth: store.book.preferences.width, screenWidth: screen.visibleFrame.width) }.max() ?? store.book.preferences.width
        var y: CGFloat = 8
        for note in visible {
            let card: NoteCard
            if let existing = cards[note.id] { card = existing } else { card = NoteCard(note: note, owner: self); cards[note.id] = card; document.addSubview(card) }
            card.update(note)
            let h: CGFloat = (note.collapsed || store.book.preferences.collapsed) ? 32 : max(130, min(600, note.height))
            let noteScreenWidth = note.desktopPosition.flatMap { position -> CGFloat? in
                if let anchor = note.screenAnchor, let region = ScreenLayout.current.first(where: { $0.id == anchor.screenID }) { return region.frame.width }
                return ScreenLayout.closest(to: NSRect(x: position.x, y: position.y - h, width: note.width ?? store.book.preferences.width, height: h), screens: ScreenLayout.current)?.frame.width
            } ?? screen.visibleFrame.width
            let noteWidth = NoteSizing.width(note, defaultWidth: store.book.preferences.width, screenWidth: noteScreenWidth)
            if note.desktopPosition != nil {
                updateDesktopCard(card, note: note, size: NSSize(width: noteWidth, height: h))
                continue
            }
            if card.superview !== document { card.removeFromSuperview(); document.addSubview(card) }
            let noteX: CGFloat = store.book.preferences.side == "right" ? 8 + width - noteWidth : 8
            card.frame = NSRect(x: noteX, y: y, width: noteWidth, height: h); y += h + 14
        }
        let totalWidth = width + 16
        let height = min(max(50, y), screen.visibleFrame.height - 24)
        let rect = screen.visibleFrame
        let x = store.book.preferences.side == "left" ? rect.minX + 4 : rect.maxX - totalWidth - 4
        panel.setFrame(NSRect(x: x, y: rect.maxY - height - 8, width: totalWidth, height: height), display: true)
        document.frame = NSRect(x: 0, y: 0, width: totalWidth, height: max(height, y))
        updateVisibility()
    }
    func settingsChanged() { store.saveSoon(); refresh() }
    func select(_ id: UUID) { selectedID = id; cards.values.forEach { $0.needsDisplay = true } }
    func focus(_ id: UUID) {
        edgeState.concealed = false; edgeState.outsideSince = nil
        hidden = false; store.book.preferences.collapsed = false
        store.update(id) { $0.collapsed = false }; select(id); refresh()
        guard let card = cards[id] else { return }
        if store.note(id)?.desktopPosition == nil { document.scrollToVisible(card.frame) }
        card.window?.orderFrontRegardless(); card.window?.makeKey(); card.window?.makeFirstResponder(card.editor)
    }
    func newNote() { let n = Note(); store.book.notes.append(n); store.saveSoon(); focus(n.id) }
    func duplicate(_ id: UUID) {
        guard let n = store.note(id) else { return }
        let doc = n.effectiveReadOnly ? RichDocument(text: n.text) : n.effectiveDocument
        let copy = Note(text: doc.text, color: n.color, richDocument: doc)
        store.book.notes.append(copy); store.saveSoon(); focus(copy.id)
    }
    func archive(_ id: UUID) { cards[id]?.commitText(); store.update(id) { $0.archived = true }; refresh() }
    func restore(_ id: UUID) { store.update(id) { $0.archived = false }; focus(id) }
    func toggleFold(_ id: UUID) { cards[id]?.commitText(); store.update(id) { $0.collapsed.toggle() }; refresh() }
    func moveCard(_ id: UUID, toWindowY y: CGFloat) {
        let point = document.convert(NSPoint(x: 0, y: y), from: nil)
        let visible = store.book.notes.filter { !$0.archived && $0.id != id }
        let next = visible.first { (cards[$0.id]?.frame.midY ?? 0) > point.y }
        guard let old = store.book.notes.firstIndex(where: { $0.id == id }) else { return }
        let note = store.book.notes.remove(at: old)
        let index = next.flatMap { next in store.book.notes.firstIndex { $0.id == next.id } } ?? store.book.notes.count
        store.book.notes.insert(note, at: index); store.saveSoon(); refresh()
    }
    func textChanged(_ id: UUID, text: String) {
        guard let note = store.note(id), note.text != text else { return }
        store.update(id) { $0.text = text; $0.richDocument = nil; $0.modified = Date() }
        scheduleSync(id)
    }
    func richTextChanged(_ id: UUID, document: RichDocument) {
        guard let note = store.note(id), !note.effectiveReadOnly, note.effectiveDocument != document || note.text != document.text else { return }
        store.update(id) { $0.richDocument = document; $0.text = document.text; $0.modified = Date() }
        scheduleSync(id)
    }
    func insertTime(_ id: UUID) {
        guard store.note(id)?.effectiveReadOnly == false else { return }
        focus(id)
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        if let editor = cards[id]?.editor { editor.insertText("\n\(f.string(from: Date())) ", replacementRange: editor.selectedRange()) }
    }
    func openFromHandle() {
        if !store.book.notes.contains(where: { !$0.archived }) { newNote(); return }
        hidden = false; edgeState.concealed = false; edgeState.outsideSince = nil
        refresh()
        syncAll()
    }
    func toggleVisible() {
        let shouldShow = hidden || (!(visibilityTransition?.targetVisible ?? panel.isVisible) && !desktopPanels.values.contains { $0.isVisible })
        hidden = !shouldShow
        edgeState.concealed = !shouldShow; edgeState.outsideSince = nil
        refresh()
        if shouldShow { syncAll() }
    }
    func registerShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer = pointer else { return noErr }
            let app = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { app.toggleVisible() }; return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotHandler)
        let identifier = EventHotKeyID(signature: OSType(0x444E4F54), id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { status.button?.toolTip = "旁白（快捷键被占用，可从此菜单显示或隐藏）" }
    }
    func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = message; a.addButton(withTitle: "好"); a.runModal()
    }
    func exportNotes() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel(); p.nameFieldStringValue = "旁白便笺.md"
        if p.runModal() == .OK, let url = p.url {
            let text = store.book.notes.map { "## \($0.title)\($0.archived ? "（已收走）" : "")\n\n\($0.text)" }.joined(separator: "\n\n---\n\n")
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { alert("导出失败", error.localizedDescription) }
        }
    }
    func showSettings() {
        if prefsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 350), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "旁白设置"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: PreferencesView(owner: self)); w.center(); prefsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true); prefsWindow?.makeKeyAndOrderFront(nil)
    }
}

struct PreferencesView: View {
    let owner: AppDelegate
    @State private var side: String
    @State private var width: Double
    @State private var spaces: Bool
    @State private var floating: Bool
    @State private var autoHide: Bool
    @State private var screen: String
    init(owner: AppDelegate) {
        self.owner = owner
        let p = owner.store.book.preferences
        _side = State(initialValue: p.side); _width = State(initialValue: p.width)
        _spaces = State(initialValue: p.allSpaces); _floating = State(initialValue: p.floatOnTop)
        _autoHide = State(initialValue: p.autoHide)
        _screen = State(initialValue: p.screenID ?? "auto")
    }
    var body: some View {
        Form {
            Picker("停靠位置", selection: $side) { Text("左侧").tag("left"); Text("右侧").tag("right") }.pickerStyle(.segmented)
            HStack { Text("默认宽度"); Slider(value: $width, in: 220...420, step: 10); Text("\(Int(width))").monospacedDigit().frame(width: 36) }
            Picker("侧边栏显示器", selection: $screen) {
                Text("主显示器").tag("auto")
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { entry in Text("\(entry.offset + 1) · \(entry.element.localizedName)").tag(owner.screenID(entry.element)) }
            }
            Toggle("移出后自动收起", isOn: $autoHide)
            Text("点击边缘图标展开，移出后延迟收起；触边不会展开。").font(.caption).foregroundStyle(.secondary)
            Toggle("显示在所有桌面", isOn: $spaces)
            Toggle("保持在其他窗口上方", isOn: $floating)
            Divider()
            Text("英文 Geneva ＋ 中文 Fusion Pixel · 14").font(.callout)
            Text("⌃⌥N 显示或隐藏便笺。\n双击便笺顶边折叠，右键打开便笺菜单。\n内容自动保存在这台 Mac 上。").font(.callout).foregroundStyle(.secondary)
        }.padding(24).frame(width: 420)
        .onChange(of: side) { owner.store.book.preferences.side = $0; owner.settingsChanged() }
        .onChange(of: width) { owner.store.book.preferences.width = $0; owner.settingsChanged() }
        .onChange(of: spaces) { owner.store.book.preferences.allSpaces = $0; owner.settingsChanged() }
        .onChange(of: autoHide) { owner.autoHideChanged($0) }
        .onChange(of: floating) { owner.store.book.preferences.floatOnTop = $0; owner.settingsChanged() }
        .onChange(of: screen) { owner.store.book.preferences.screenID = $0 == "auto" ? nil : $0; owner.settingsChanged() }
    }
}
