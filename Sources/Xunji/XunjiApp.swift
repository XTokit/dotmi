import SwiftUI
import Carbon
import SearchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var hotKeyObserver: NSObjectProtocol?
    private var registeredHotKeyChoice = ""
    private func registerPreferredHotKey() {
        let choice = GlobalHotKeyChoice(rawValue: UserDefaults.standard.string(forKey: "globalHotKeyChoice") ?? "") ?? .commandShift
        guard registeredHotKeyChoice != choice.rawValue else { return }
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        registeredHotKeyChoice = choice.rawValue
        let modifiers: UInt32
        switch choice {
        case .commandShift: modifiers = UInt32(cmdKey | shiftKey)
        case .controlOption: modifiers = UInt32(controlKey | optionKey)
        case .commandOption: modifiers = UInt32(cmdKey | optionKey)
        }
        let id = EventHotKeyID(signature: 0x584A5343, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_Space), modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        SearchModel.shared.hotKeyStatus = result == noErr ? "已启用 " + choice.title : choice.title + " 注册失败，可能已被占用；请换一个组合或从菜单栏打开。"
    }
    private var keyMonitor: Any?
    private var verificationTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = self
        if ProcessInfo.processInfo.arguments.contains("--verify-interaction"),
           let directory = ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] {
            let model = SearchModel.shared
            let clipboard = NSPasteboard.withUniqueName()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let path = directory + "/方案-é-👩🏽‍💻.txt"
                try! "fixture".write(toFile: path, atomically: true, encoding: .utf8)
                model.files = [FileRecord(path: path, name: "方案-é-👩🏽‍💻.txt", kind: .document)]
                model.selected = path
                model.copyPath(to: clipboard)
                if clipboard.string(forType: .string) != path || model.notice?.message != "路径已复制" {
                    print("Interaction diagnostic: clipboardMatches=\(clipboard.string(forType: .string) == path), notice=\(model.notice?.message ?? "nil"), issue=\(model.issue ?? "nil")")
                    fflush(stdout)
                }
                precondition(clipboard.string(forType: .string) == path && model.notice?.message == "路径已复制")
                precondition(String(filenameWithMatches("方案-é-👩🏽‍💻.txt", query: "方案 e 👩🏽‍💻", selected: false).characters) == "方案-é-👩🏽‍💻.txt")
                model.addFavorite(directory)
                precondition(model.notice?.message == "已加入常用文件夹")
                model.removeFavorite(directory)
                precondition(model.notice?.message == "已移出常用文件夹")
                model.showNotice("旧提示", duration: 0.04)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    model.showNotice("新提示", duration: 0.3)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    precondition(model.notice?.message == "新提示")
                    model.issue = "测试错误"
                    precondition(model.notice == nil)
                    model.showNotice("不覆盖错误")
                    precondition(model.notice == nil)
                    model.issue = nil
                    model.showNotice("自动结束", duration: 0.04)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        precondition(model.notice == nil)
                        clipboard.releaseGlobally()
                        print("PASS: isolated clipboard, favorite feedback, Unicode highlighting, latest notice survives old expiry, error priority and automatic dismissal")
                        fflush(stdout); NSApp.terminate(nil)
                    }
                }
            }
            return
        }
        if ProcessInfo.processInfo.environment["XUNJI_DEMO"] == "1", ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] != nil {
            if let output = ProcessInfo.processInfo.environment["XUNJI_DEMO_SCREENSHOT"] {
                verificationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                    guard !SearchModel.shared.searching,
                          let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
                          let view = window.contentView?.superview,
                          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    // Export only our synthetic demo view, never the user's desktop.
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    do {
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG export failed") }
                        try png.write(to: URL(fileURLWithPath: output))
                    } catch { fatalError("Demo export failed: \(error)") }
                    timer.invalidate(); self?.verificationTimer = nil
                    print("Exported synthetic demo screenshot")
                    fflush(stdout); NSApp.terminate(nil)
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-locations"),
           let fixture = ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] {
            let model = SearchModel.shared
            let root = canonicalPath(fixture), child = root + "/子目录"
            let count = model.indexCount, originalScope = model.scope
            precondition(model.coveringLocation(child) == root)
            let roots = model.roots
            model.addFavorite(child)
            precondition(model.favoriteFolders == [child] && model.scope == originalScope && !model.indexing)
            precondition(model.roots == roots)
            precondition(model.indexCount == count)
            model.addFavorite(child)
            precondition(model.favoriteFolders == [child])
            model.removeFavorite(child)
            precondition(model.favoriteFolders.isEmpty && model.roots == roots && model.indexCount == count)
            model.addSearchLocation(child)
            precondition(model.issue != nil && model.roots == roots && !model.indexing)
            model.issue = nil
            model.selectFolder(child)
            precondition(model.scope == child && !model.indexing)
            model.addFavorite(root + "/不存在")
            precondition(model.issue != nil && model.roots == roots)
            print("PASS: favorites add/remove/duplicates without scanning, unchanged scope and index, redundant index rejected, cached folder search, missing-folder feedback")
            fflush(stdout); NSApp.terminate(nil); return
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-search-feedback"),
           ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] != nil {
            let model = SearchModel.shared
            model.query = "文稿"
            for n in 0..<30 { model.showSystemFiles = n.isMultiple(of: 2) }
            model.showSystemFiles = false
            precondition(model.searching)
            var step = 0
            let started = Date()
            verificationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard !model.searching else {
                    if Date().timeIntervalSince(started) > 10 { fatalError("Search never settled") }
                    return
                }
                precondition(model.searchFailure == nil && model.issue == nil)
                switch step {
                case 0:
                    precondition(model.files.count == 1 && model.files[0].name == "文稿.txt")
                    model.showSystemFiles = true
                case 1:
                    precondition(model.files.count == 2)
                    model.query = "__missing_search_fixture__"
                case 2:
                    precondition(model.files.isEmpty && model.emptyFeedback == .noMatch)
                    model.kind = .image
                case 3:
                    precondition(model.emptyFeedback == .filtered)
                    model.clearResultFilters()
                default:
                    precondition(model.kind == nil && model.recursive && model.showSystemFiles)
                    precondition(model.emptyFeedback == .noMatch)
                    timer.invalidate(); self?.verificationTimer = nil
                    print("PASS: 30 rapid visibility toggles, latest asynchronous result, hidden-file inclusion, no-match feedback and clearing type filters")
                    fflush(stdout); NSApp.terminate(nil)
                }
                step += 1
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-preview"),
           let directory = ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] {
            let first = URL(fileURLWithPath: directory).appendingPathComponent("preview.txt")
            let second = URL(fileURLWithPath: directory).appendingPathComponent(".program.log")
            try! "Document preview".write(to: first, atomically: true, encoding: .utf8)
            try! "Program preview".write(to: second, atomically: true, encoding: .utf8)
            let host = PreviewContainer(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            var step = 0
            verificationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
                step += 1
                if step % 3 == 0 { host.clear() }
                if step % 5 == 0 { window.close() }
                if step % 5 == 1 { window.orderFront(nil) }
                let url = step.isMultiple(of: 2) ? first : second
                host.show(url); host.show(url)
                precondition(host.currentURL == url)
                if step == 30 {
                    host.clear(); window.close(); timer.invalidate(); self?.verificationTimer = nil
                    print("PASS: 30 preview transitions, repeated URLs, clear/reuse, window close/reopen without a closed Quick Look view being reused")
                    fflush(stdout); NSApp.terminate(nil)
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-scope"),
           let fixture = ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] {
            let model = SearchModel.shared
            let originalRoots = model.roots
            let folder = canonicalPath(fixture + "/文稿")
            model.selectFolder(folder)
            precondition(model.scope == folder && model.scopeTitle == "文稿")
            precondition(!model.indexing && model.roots == originalRoots)
            model.scope = nil
            precondition(model.scope == nil)
            model.selectFolder(fixture + "/文稿/../文稿")
            precondition(model.scope == folder && !model.scopeNotice.isEmpty)
            model.selectFolder(folder)
            precondition(model.scope == folder && !model.indexing)
            print("PASS: scope selection, canonical path, visible feedback, repeated selection, cached-index reuse")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let model = SearchModel.shared
            if event.window?.identifier?.rawValue == "file-preview",
               event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
                switch event.keyCode {
                case 49, 53:
                    model.preview = nil
                    NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
                    NotificationCenter.default.post(name: .init("XunjiFocusResults"), object: nil)
                    return nil
                case 125, 126: model.moveSelection(event.keyCode == 125 ? 1 : -1); return nil
                default: return event
                }
            }
            guard event.window?.identifier?.rawValue == "main", event.window?.attachedSheet == nil, !model.transientPanelActive,
                  event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return event }
            // 组词和候选选择优先交还输入法；其他编辑控件不参与结果导航。
            if let editor = event.window?.firstResponder as? NSTextView {
                if editor.hasMarkedText() || !model.searchFieldActive { return event }
            }
            guard model.searchFieldActive || model.resultsActive else { return event }
            if event.keyCode == 125 || event.keyCode == 126 {
                guard !model.searching, !model.files.isEmpty else { return event }
                if !model.searchFieldActive || model.selected == nil { model.moveSelection(event.keyCode == 125 ? 1 : -1) }
                NotificationCenter.default.post(name: .init("XunjiFocusResults"), object: nil)
                return nil
            }
            if event.keyCode == 36 { model.reveal(); return nil }
            if event.keyCode == 49 && model.resultsActive { model.togglePreview(); return nil }
            return event
        }
        var handler: EventHandlerRef?
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { SearchModel.shared.showWindow() }; return noErr
        }, 1, &type, nil, &handler)
        registerPreferredHotKey()
        hotKeyObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.registerPreferredHotKey() }
        SearchModel.shared.start()
        if ProcessInfo.processInfo.arguments.contains("--verify-index-run"),
           let reportPath = ProcessInfo.processInfo.environment["XUNJI_RUN_REPORT"],
           ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] != nil {
            NSApp.setActivationPolicy(.accessory)
            let started = Date()
            verificationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
                NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.orderOut(nil) }
                let model = SearchModel.shared
                if model.verificationIdle && Date().timeIntervalSince(started) > (Double(ProcessInfo.processInfo.environment["XUNJI_SETTLE_SECONDS"] ?? "1") ?? 1) {
                    let payload: [String: Any] = [
                        "accelerated": model.searchIndexReady,
                        "count": model.indexCount,
                        "coverage": model.coverage.map { ["path": $0.path, "state": $0.state.rawValue, "lastScan": $0.lastScanned?.timeIntervalSince1970 ?? 0, "excluded": $0.excluded] as [String: Any] }
                    ]
                    do { try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys).write(to: URL(fileURLWithPath: reportPath), options: .atomic) }
                    catch { print(error); fflush(stdout); exit(1) }
                    print("Index run settled: \(model.indexCount) files, accelerated=\(model.searchIndexReady)")
                    fflush(stdout); timer.invalidate(); self?.verificationTimer = nil; NSApp.terminate(nil)
                } else if Date().timeIntervalSince(started) > 45 {
                    print("Timed out: \(model.status)"); fflush(stdout); exit(1)
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { SearchModel.shared.showWindow(); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let path = filenames.first { SearchModel.shared.selectFolder(path); SearchModel.shared.showWindow() }
        sender.reply(toOpenOrPrint: .success)
    }
    @objc func searchFolder(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let legacy = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] ?? []
        guard let path = urls.first?.path ?? legacy.first else { return }
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        guard exists else { return }
        let folder = directory.boolValue ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path
        SearchModel.shared.selectFolder(folder); SearchModel.shared.showWindow()
    }
}

@main
struct XunjiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = SearchModel.shared
    @AppStorage("visualStyle") private var style = "spotlight"
    @AppStorage("globalHotKeyChoice") private var hotKeyChoice = GlobalHotKeyChoice.commandShift.rawValue
    init() {
        if ProcessInfo.processInfo.arguments.contains("--verify-interaction"),
           ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] != nil {
            // 只覆盖测试进程的启动域，避免断言失败后的系统窗口恢复询问；不写用户偏好。
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["ApplePersistenceIgnoreState"] = true
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
    }
    private static var menuBarIcon: NSImage {
        let image = Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "点觅")!
        image.size = NSSize(width: 18, height: 18); image.isTemplate = true
        return image
    }
    var body: some Scene {
        Window(ProcessInfo.processInfo.environment["XUNJI_DEMO"] == "1" ? "点觅 · 演示" : "点觅", id: "main") {
            ContentView(model: model)
                .preferredColorScheme(style == "dark" ? .dark : nil)
                .frame(minWidth: style == "spotlight" ? 640 : 1060, minHeight: style == "spotlight" ? 520 : 660)
                .onAppear { model.resizeWindow(style: style) }
                .onChange(of: style) { newStyle in model.resizeWindow(style: newStyle) }
        }
        .defaultSize(width: 780, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("选择搜索文件夹…") { model.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("搜索框") { model.showWindow() }.keyboardShortcut("f")
            }
            CommandMenu("文件操作") {
                Button("在 Finder 中显示") { model.reveal() }.keyboardShortcut("r").disabled(model.selection == nil)
                Button("打开文件") { model.openSelection() }.keyboardShortcut(.return, modifiers: .command).disabled(model.selection == nil)
                Button("快速预览") { model.togglePreview() }.keyboardShortcut("y").disabled(model.selection == nil)
                Button("复制路径") { model.copyPath() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(model.selection == nil)
            }
        }
        Settings { SettingsView(model: model).frame(width: 560, height: 480) }
        MenuBarExtra {
            Button("打开点觅    " + (GlobalHotKeyChoice(rawValue: hotKeyChoice) ?? .commandShift).title) { model.showWindow() }
            Button("搜索文件夹…") { model.chooseFolder(); model.showWindow() }
            Divider()
            Text("已索引 \(model.indexCount.formatted()) 项")
            Button("退出点觅") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
    }
}
