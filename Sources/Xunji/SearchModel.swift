import AppKit
import Combine
import CoreServices
import SearchCore

final class Cancellation {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

enum FolderSelectionPurpose { case search, favorite, index }

final class SearchModel: ObservableObject {
    static let shared = SearchModel()
    @Published var query = "" { didSet { if query != oldValue { selected = nil; search() } } }
    @Published var scope: String? { didSet {
        selected = nil
        if ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] == nil && ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] == nil {
            UserDefaults.standard.set(scope ?? "", forKey: "selectedScope")
        }
        search()
    } }
    @Published var scopeNotice = ""
    @Published var recursive = true { didSet { search() } }
    @Published var showSystemFiles = false { didSet {
        selected = nil
        if ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] == nil && ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] == nil {
            UserDefaults.standard.set(showSystemFiles, forKey: "showSystemFiles")
        }
        search()
    } }
    @Published var includePath = false { didSet { search() } }
    @Published var kind: FileKind? { didSet { if kind != oldValue { selected = nil; search() } } }
    @Published var newest = false { didSet { search() } }
    @Published var grouped = true
    @Published var files: [FileRecord] = []
    @Published var counts: [FileKind: Int] = [:]
    @Published var total = 0
    @Published var searching = false
    @Published var searchFailure: String?
    @Published var milliseconds = 0.0
    @Published var indexCount = 0
    @Published var indexing = false
    @Published var status = "选择搜索范围，建立一次索引"
    @Published var roots: [String] = UserDefaults.standard.stringArray(forKey: "indexRoots") ?? []
    @Published var denied: [String] = []
    @Published var coverage: [RootCoverage] = []
    @Published var favoriteFolders: [String] = []
    var indexCoverage: [RootCoverage] { coverage.filter { coveringLocation($0.path) == nil } }
    @Published var searchIndexReady = false
    @Published var upgradingSearch = false
    @Published var issue: String?
    @Published var selected: String?
    @Published var preview: FileRecord?
    private let writer = DispatchQueue(label: "xunji.index", qos: .utility)
    private let reader = DispatchQueue(label: "xunji.search", qos: .userInitiated)
    private var readStore: IndexStore?
    private var writeStore: IndexStore?
    private var request = 0
    private var pending: DispatchWorkItem?
    private var cancellation = Cancellation()
    private var stream: FSEventStreamRef?
    private var changed: Set<String> = []
    private var recursiveChanges: Set<String> = []
    @Published var monitoring = false
    private var pendingEventID: UInt64 = 0
    private var baselineEventID: UInt64 = 0
    private var applyingChanges = false
    private var historyCaughtUp = false
    private var catalog = IndexCatalog()
    private let catalogURL: URL
    private var refresh: DispatchWorkItem?
    private var launchRefreshScheduled = false
    private var pendingComputer = false
    private var pendingFolder: String?
    var selection: FileRecord? { files.first { $0.path == selected } }
    var scopeTitle: String { scope.map { URL(fileURLWithPath: $0).lastPathComponent.isEmpty ? "整台 Mac" : URL(fileURLWithPath: $0).lastPathComponent } ?? (roots.contains("/") ? "整台 Mac" : "全部已索引位置") }
    let databaseURL: URL
    var exclusions: [String] { Array(Set(coverage.flatMap(\.excluded))).sorted() }
    var coverageSummary: String {
        let ready = coverage.filter { $0.state == .ready }.count
        let offline = coverage.filter { $0.state == .offline }.count
        let incomplete = coverage.filter { [.pending,.scanning,.interrupted].contains($0.state) }.count
        var parts = ["\(ready) 个范围已完成"]
        if incomplete > 0 { parts.append("\(incomplete) 个范围待完成") }
        if !denied.isEmpty { parts.append("\(denied.count) 处无法访问") }
        if offline > 0 { parts.append("\(offline) 个位置离线") }
        if !exclusions.isEmpty { parts.append("\(exclusions.count) 处已排除") }
        return coverage.isEmpty ? "尚未建立范围索引" : parts.joined(separator: " · ")
    }

    var emptyFeedback: SearchFeedback {
        SearchFeedback.resolve(searching: searching, failed: searchFailure != nil, indexing: indexing,
                               scope: scope, coverage: coverage,
                               filtered: kind != nil || !recursive)
    }
    func clearResultFilters() { kind = nil; recursive = true }

    init() {
        let testRoot = ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"]
        let support = testRoot.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Xunji")
        databaseURL = support.appendingPathComponent("files.sqlite")
        catalogURL = support.appendingPathComponent("index-state.json")
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            readStore = try IndexStore(path: databaseURL.path)
            writeStore = try IndexStore(path: databaseURL.path)
            indexCount = try readStore!.count()
            searchIndexReady = readStore!.searchIndexReady
            catalog = try IndexCatalog.load(catalogURL)
            if !roots.isEmpty { status = "索引已载入 · 后台核对文件变化" }
        } catch { issue = error.localizedDescription; status = "索引无法打开" }
        if let fixture = ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] {
            roots = [fixture]
        } else if ProcessInfo.processInfo.environment["XUNJI_DEMO"] == "1", testRoot != nil {
            roots = []
        }
        roots = roots.map(canonicalPath)
        if testRoot == nil && ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] == nil {
            favoriteFolders = UserDefaults.standard.stringArray(forKey: "favoriteFolders") ?? roots.filter { $0 != "/" }
            UserDefaults.standard.set(favoriteFolders, forKey: "favoriteFolders")
        }
        refreshCoverage()
        if testRoot == nil && ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] == nil,
           let savedScope = UserDefaults.standard.string(forKey: "selectedScope"), !savedScope.isEmpty {
            scope = canonicalPath(savedScope)
        }
        if testRoot == nil && ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] == nil {
            showSystemFiles = UserDefaults.standard.bool(forKey: "showSystemFiles")
        }
        if ProcessInfo.processInfo.environment["XUNJI_DEMO"] == "1", testRoot != nil {
            configureDemo()
        }
        search()
    }
    private func configureDemo() {
        roots = ["/Users/demo/Documents"]
        favoriteFolders = ["/Users/demo/Documents/设计方案", "/Users/demo/Documents/项目资料"]
        scope = nil; query = "方案"
        let names: [(String, FileKind)] = [
            ("设计方案/品牌视觉方案.pdf", .document), ("设计方案/产品首页方案.pdf", .document),
            ("项目资料/季度活动方案.md", .document), ("设计方案/首页方案预览.png", .image),
            ("项目资料/方案讲解.mp4", .video), ("项目资料/设计方案归档.zip", .archive)
        ]
        do {
            let files = names.enumerated().map { offset, entry in
                FileRecord(path: "/Users/demo/Documents/" + entry.0, name: URL(fileURLWithPath: entry.0).lastPathComponent,
                           kind: entry.1, size: Int64((offset + 1) * 245_760), modified: 1_760_000_000)
            }
            try writeStore?.upsert(files, generation: "demo")
            try writeStore?.prepareSearchIndex()
            indexCount = files.count; searchIndexReady = true
            var root = RootCoverage(path: roots[0]); root.state = .ready; root.scanned = files.count
            catalog.roots = [root.path: root]; refreshCoverage()
            status = "演示模式 · 合成文件，不扫描真实目录"
        } catch { issue = error.localizedDescription }
    }
    func start() {
        if ProcessInfo.processInfo.environment["XUNJI_DEMO"] == "1", ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] != nil { return }
        guard !launchRefreshScheduled else { return }; launchRefreshScheduled = true
        baselineEventID = FSEventsGetCurrentEventId()
        if let checkpoint = catalog.checkpoint, checkpoint > baselineEventID { catalog.checkpoint = nil }
        watch()
        if searchIndexReady { resumeIndexing(); return }
        guard let store = writeStore else { return }
        upgradingSearch = true; indexing = true; cancellation = Cancellation()
        let cancel = cancellation
        status = "正在升级文件名检索索引，现有搜索仍可使用…"
        writer.async { [weak self] in
            guard let self else { return }
            do {
                let ready = try store.prepareSearchIndex(cancelled: { cancel.isCancelled }, progress: { count in
                    DispatchQueue.main.async { self.status = "正在升级检索索引 · \(count.formatted()) / \(self.indexCount.formatted()) 项" }
                })
                DispatchQueue.main.async {
                    self.upgradingSearch = false; self.indexing = false; self.searchIndexReady = ready; self.search()
                    if ready { self.resumeIndexing() }
                    else { self.status = "检索升级已暂停 · 当前使用兼容搜索，可重试升级"; self.continuePendingScan() }
                }
            } catch { DispatchQueue.main.async { self.upgradingSearch = false; self.indexing = false; self.issue = error.localizedDescription; self.status = "检索升级未完成 · 现有索引保留" } }
        }
    }
    private func refreshCoverage() {
        let next = roots.map { catalog.roots[$0] ?? RootCoverage(path: $0) }
        if coverage != next { coverage = next }
        let nextDenied = Array(Set(next.flatMap(\.denied))).sorted()
        if denied != nextDenied { denied = nextDenied }
    }
    private func saveCatalog(refresh: Bool = true) {
        do { try catalog.save(catalogURL) }
        catch { status = "无法保存增量进度，下次启动会重新核对"; issue = error.localizedDescription }
        if refresh { refreshCoverage() }
    }
    private func resumeIndexing() {
        guard !roots.isEmpty else { status = "选择搜索范围，建立一次索引"; return }
        var needed: [String] = []
        for path in roots {
            let identity = IndexCatalog.identity(path)
            if identity == nil {
                var value = catalog.roots[path] ?? RootCoverage(path: path)
                do { _ = try FileManager.default.attributesOfItem(atPath: path); value.state = .partial; value.denied = [path] }
                catch { value.state = isMissingFile(error) ? .offline : .partial; if value.state == .partial { value.denied = [path] } }
                catalog.roots[path] = value
            } else if catalog.needsBaseline(path, identity: identity) { needed.append(path) }
        }
        refreshCoverage()
        if !needed.isEmpty { rebuild(paths: needed) }
        else {
            if catalog.checkpoint == nil { catalog.checkpoint = baselineEventID }
            saveCatalog()
            status = !monitoring ? "自动更新未启动，请重试离线位置或手动核对" : historyCaughtUp ? "搜索已就绪 · 文件变化时自动更新" : "索引已载入 · 正在补充关闭期间的文件变化"
            if !roots.isEmpty { scheduleChanges() }
            continuePendingScan()
        }
    }
    func retrySearchUpgrade() { guard !indexing else { return }; launchRefreshScheduled = false; start() }
    var verificationIdle: Bool { !indexing && !applyingChanges && historyCaughtUp && changed.isEmpty && pendingEventID == 0 && searchIndexReady }
    func retryDenied() {
        guard !indexing else { return }
        let paths = minimalPaths(denied.filter { FileManager.default.fileExists(atPath: $0) })
        if !paths.isEmpty { rebuild(paths: paths) }
    }
    private func minimalPaths(_ paths: [String]) -> [String] {
        var result: [String] = []
        for path in Set(paths).sorted(by: { $0.count < $1.count }) where !result.contains(where: { $0 == "/" || path == $0 || path.hasPrefix($0 + "/") }) { result.append(path) }
        return result
    }
    func search() {
        request += 1; let token = request
        searching = true; searchFailure = nil
        pending?.cancel()
        let query = query, scope = scope, recursive = recursive, includePath = includePath, kind = kind, newest = newest, showSystemFiles = showSystemFiles
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let store = self.readStore else {
                DispatchQueue.main.async {
                    guard token == self.request else { return }
                    self.searching = false; self.searchFailure = "索引无法打开，请检查数据目录。"
                }
                return
            }
            do {
                let result = try store.search(query, scope: scope, recursive: recursive, includePath: includePath, kind: kind, newest: newest, includeSystemFiles: showSystemFiles)
                DispatchQueue.main.async {
                    guard token == self.request else { return }
                    self.searching = false
                    if self.files != result.files { self.files = result.files }
                    if self.counts != result.counts { self.counts = result.counts }
                    if self.total != result.total { self.total = result.total }
                    self.milliseconds = result.milliseconds
                    if !self.files.contains(where: { $0.path == self.selected }) {
                        self.selected = nil
                    }
                }
            } catch { DispatchQueue.main.async { if token == self.request { self.searching = false; self.searchFailure = error.localizedDescription; self.issue = error.localizedDescription } } }
        }
        pending = work; reader.asyncAfter(deadline: .now() + .milliseconds(90), execute: work)
    }
    func chooseFolder(purpose: FolderSelectionPurpose = .search) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        switch purpose {
        case .search: panel.message = "选择本次要搜索的文件夹。"; panel.prompt = "搜索此文件夹"
        case .favorite: panel.message = "保存常用文件夹，方便下次快速切换；不会开始扫描。"; panel.prompt = "加入常用"
        case .index: panel.message = "仅为未覆盖或主动排除的目录补充索引，已覆盖的位置无需重复添加。"; panel.prompt = "补充索引"
        }
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = panel.url {
                switch purpose {
                case .search: self?.selectFolder(url.path)
                case .favorite: self?.addFavorite(url.path)
                case .index: self?.addSearchLocation(url.path)
                }
            }
        }
        if let window = NSApp.mainWindow, window.attachedSheet == nil { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func saveFavorites() {
        if ProcessInfo.processInfo.environment["XUNJI_DATA_DIR"] == nil && ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] == nil {
            UserDefaults.standard.set(favoriteFolders, forKey: "favoriteFolders")
        }
    }
    func addFavorite(_ input: String) {
        let path = canonicalPath(input)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { issue = "文件夹不存在或磁盘未连接。"; return }
        guard !favoriteFolders.contains(path) else { return }
        favoriteFolders.append(path); saveFavorites()
    }
    func removeFavorite(_ path: String) { favoriteFolders.removeAll { $0 == path }; saveFavorites() }
    func coveringLocation(_ path: String) -> String? {
        roots.filter { parent in
            guard parent != path, parent == "/" || path.hasPrefix(parent + "/"), let item = catalog.roots[parent], item.state == .ready else { return false }
            return !item.excluded.contains { path == $0 || path.hasPrefix($0 + "/") }
        }.max(by: { $0.count < $1.count })
    }
    func addSearchLocation(_ input: String) {
        let path = canonicalPath(input)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { issue = "文件夹不存在或磁盘未连接。"; return }
        if roots.contains(path) { return }
        if coveringLocation(path) != nil {
            issue = "该文件夹已包含在现有索引中，无需重复添加。需要快速切换时，可将它加入“常用文件夹”。"
        } else { addRoot(path) }
    }
    func selectFolder(_ input: String) {
        let path = canonicalPath(input)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
            issue = "文件夹不存在或磁盘未连接。"; return
        }
        scope = path
        pendingComputer = false; pendingFolder = nil
        scopeNotice = "已切换到所选文件夹"
        let covered = roots.contains { $0 == "/" || path == $0 || path.hasPrefix($0 + "/") }
        if covered && !excluded(path) {
            scopeNotice = indexing ? "已切换范围 · 正在建立索引，结果会陆续出现" : "已切换范围 · 使用已有索引搜索"
            return
        }
        if indexing {
            pendingFolder = path; cancellation.cancel()
            scopeNotice = "已选择文件夹 · 正在切换索引"
            return
        }
        scopeNotice = "已选择文件夹 · 正在建立索引"
        addRoot(path)
    }
    func openDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    private func continuePendingScan() {
        if let folder = pendingFolder { pendingFolder = nil; selectFolder(folder) }
        else if pendingComputer { pendingComputer = false; indexComputer() }
    }
    func addRoot(_ path: String) {
        let path = canonicalPath(path)
        guard !indexing else { issue = "请等待当前索引完成，或先停止索引。"; return }
        if !roots.contains(path) {
            roots.removeAll { path == "/" || $0.hasPrefix(path + "/") }; roots.append(path)
            if ProcessInfo.processInfo.environment["XUNJI_TEST_ROOT"] == nil { UserDefaults.standard.set(roots, forKey: "indexRoots") }
        }
        watch(); rebuild(paths: [path])
    }
    func indexHome() { addRoot(NSHomeDirectory()); scope = nil }
    func indexComputer() {
        pendingFolder = nil; scopeNotice = ""
        if indexing && !roots.contains("/") {
            pendingComputer = true; cancellation.cancel(); scope = nil
            status = "正在切换到整台 Mac…"
            return
        }
        if !roots.contains("/") { addRoot("/") }
        scope = nil
    }
    func rebuild(paths: [String]? = nil) {
        guard !indexing, let store = writeStore else { return }
        let targets = paths ?? indexCoverage.map(\.path)
        guard !targets.isEmpty else { return }
        indexing = true; status = "正在核对文件索引…"; cancellation = Cancellation()
        for path in targets where roots.contains(path) {
            var value = catalog.roots[path] ?? RootCoverage(path: path); value.state = .scanning; catalog.roots[path] = value
        }
        saveCatalog()
        let cancel = cancellation
        writer.async { [weak self] in
            guard let self else { return }
            do {
                for path in targets {
                    if cancel.isCancelled { break }
                    let report = try Scanner().scan(root: URL(fileURLWithPath: path), store: store, cancelled: { cancel.isCancelled }, progress: { count in
                        DispatchQueue.main.async { self.status = "正在索引 \(path == "/" ? "整台 Mac" : URL(fileURLWithPath: path).lastPathComponent) · \(count.formatted()) 项"; self.search() }
                    })
                    DispatchQueue.main.async { self.mergeCoverage(path, report: report); self.saveCatalog() }
                }
                let count = try store.count()
                DispatchQueue.main.async {
                    self.indexCount = count; self.indexing = false
                    for path in targets where self.roots.contains(path) && self.catalog.roots[path]?.state == .scanning {
                        self.catalog.roots[path]?.state = .interrupted
                    }
                    if self.catalog.checkpoint == nil && !self.coverage.contains(where: { [.pending,.scanning,.interrupted].contains($0.state) }) { self.catalog.checkpoint = self.baselineEventID }
                    self.saveCatalog()
                    self.status = cancel.isCancelled ? "扫描已停止 · 未完成范围可继续" : "搜索已就绪 · 文件变化时自动更新"
                    self.search()
                    if self.scope != nil { self.scopeNotice = "当前文件夹范围已生效" }
                    self.continuePendingScan()
                    self.scheduleChanges()
                }
            } catch { DispatchQueue.main.async {
                self.indexing = false; self.issue = error.localizedDescription; self.status = "索引遇到错误，可重新建立"
                for path in targets where self.catalog.roots[path]?.state == .scanning { self.catalog.roots[path]?.state = .interrupted }
                self.saveCatalog()
                self.continuePendingScan()
            } }
        }
    }
    private func mergeCoverage(_ path: String, report: ScanReport) {
        if roots.contains(path) { catalog.record(path, report: report) }
        for root in roots where root != path && (root == "/" || path.hasPrefix(root + "/")) {
            guard var value = catalog.roots[root] else { continue }
            value.denied.removeAll { $0 == path || $0.hasPrefix(path + "/") }
            value.excluded.removeAll { $0 == path || $0.hasPrefix(path + "/") }
            value.denied = Array(Set(value.denied + report.denied)).sorted()
            value.excluded = Array(Set(value.excluded + report.excluded)).sorted()
            if [.ready,.partial].contains(value.state) { value.state = value.denied.isEmpty ? .ready : .partial }
            catalog.roots[root] = value
        }
        refreshCoverage()
    }
    func stop() { pendingComputer = false; pendingFolder = nil; cancellation.cancel() }
    func reveal(_ file: FileRecord? = nil) {
        guard let file = file ?? selection else { return }
        guard FileManager.default.fileExists(atPath: file.path) else { issue = "文件已移动、删除或磁盘未连接。请更新索引。"; search(); return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
    func openSelection() {
        guard let file = selection else { return }
        if !NSWorkspace.shared.open(file.url) { issue = "无法打开这个文件，请检查文件是否仍存在。" }
    }
    func copyPath() { guard let path = selection?.path else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
    func moveSelection(_ delta: Int) {
        let ordered = grouped ? FileKind.allCases.flatMap { kind in files.filter { $0.kind == kind } } : files
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.path == selected } ?? (delta > 0 ? -1 : ordered.count)
        selected = ordered[min(ordered.count - 1, max(0, current + delta))].path
    }
    func resizeWindow(style: String) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else { return }
            window.setContentSize(style == "spotlight" ? NSSize(width: 780, height: 620) : NSSize(width: 1280, height: 820))
            window.center()
        }
    }
    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "点觅" }) { window.makeKeyAndOrderFront(nil) }
        else { NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil) }
        NotificationCenter.default.post(name: .init("XunjiFocusSearch"), object: nil)
    }
    private func excluded(_ path: String) -> Bool {
        if URL(fileURLWithPath: path).lastPathComponent == ".DS_Store" { return true }
        if path == databaseURL.path || path.hasPrefix(databaseURL.deletingLastPathComponent().path + "/") { return true }
        let specific = roots.filter { path == $0 || $0 == "/" || path.hasPrefix($0 + "/") }.max(by: { $0.count < $1.count }) ?? "/"
        let library = NSHomeDirectory() + "/Library"
        if (path == library || path.hasPrefix(library + "/")), !(specific == library || specific.hasPrefix(library + "/")) { return true }
        if specific == "/", Scanner.excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let relative = String(path.dropFirst(specific.count))
        return relative.split(separator: "/").contains(where: { [".git", ".build", "node_modules", ".Trash"].contains(String($0)) })
    }
    private func watch() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil }
        monitoring = false
        guard !roots.isEmpty else { return }
        if baselineEventID == 0 { baselineEventID = FSEventsGetCurrentEventId() }
        historyCaughtUp = catalog.checkpoint == nil
        let watchPaths = minimalPaths(roots.map { path -> String in
            var candidate = path
            while IndexCatalog.identity(candidate) == nil && candidate != "/" { candidate = URL(fileURLWithPath: candidate).deletingLastPathComponent().path }
            return candidate
        })
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
            guard let info else { return }
            let model = Unmanaged<SearchModel>.fromOpaque(info).takeUnretainedValue()
            let values = unsafeBitCast(paths, to: NSArray.self) as! [String]
            for i in 0..<count {
                if flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 {
                    model.pendingEventID = max(model.pendingEventID, ids[i]); model.historyCaughtUp = true; continue
                }
                let path = canonicalPath(values[i])
                let ownData = model.databaseURL.deletingLastPathComponent().path
                if path == ownData || path.hasPrefix(ownData + "/") { continue }
                model.pendingEventID = max(model.pendingEventID, ids[i])
                let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped)
                if flags[i] & lost != 0 {
                    model.catalog.checkpoint = nil
                    for root in model.roots { model.catalog.roots[root]?.state = .pending }
                    model.saveCatalog()
                    model.changed.formUnion(model.roots); model.recursiveChanges.formUnion(model.roots)
                    continue
                }
                if !model.roots.contains(where: { $0 == "/" || path == $0 || path.hasPrefix($0 + "/") }) {
                    let broad = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged)
                    if flags[i] & broad != 0 {
                        let affected = model.roots.filter { $0.hasPrefix(path + "/") }
                        model.changed.formUnion(affected); model.recursiveChanges.formUnion(affected)
                    }
                    continue
                }
                if model.excluded(path) { continue }
                model.changed.insert(path)
                let recursiveFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount)
                if flags[i] & recursiveFlags != 0 { model.recursiveChanges.insert(path) }
            }
            model.scheduleChanges()
        }
        stream = FSEventStreamCreate(nil, callback, &context, watchPaths as CFArray, catalog.checkpoint ?? baselineEventID, 0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); monitoring = FSEventStreamStart(stream) }
        if !monitoring { historyCaughtUp = true; status = "自动更新未能启动，请使用手动更新索引" }
    }
    private func scheduleChanges() {
        guard refresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.refresh = nil; self?.updateChanges() }; refresh = work
        // Coalesce bursts instead of waking the writer and redrawing every half second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    private func updateChanges() {
        if indexing || applyingChanges { scheduleChanges(); return }
        guard pendingEventID > 0 || !changed.isEmpty else { return }
        let paths = changed.sorted { $0.count < $1.count }, recursive = recursiveChanges
        let eventID = pendingEventID
        changed.removeAll(); recursiveChanges.removeAll(); pendingEventID = 0
        var minimal: [String] = []
        for path in paths where !minimal.contains(where: { recursive.contains($0) && ($0 == "/" || path.hasPrefix($0 + "/")) }) { minimal.append(path) }
        guard let store = writeStore else { return }
        let rootSet = Set(roots)
        let cancel = Cancellation()
        applyingChanges = true
        if !minimal.isEmpty && !historyCaughtUp { status = "正在补充关闭期间的文件变化…" }
        writer.async { [weak self] in
            guard let self else { return }
            do {
                var reports: [(String, ScanReport)] = []
                var updates: [FileRecord] = [], removals: [String] = []
                func flush() throws {
                    try store.applyChanges(updates, removing: removals, generation: "event")
                    updates.removeAll(keepingCapacity: true); removals.removeAll(keepingCapacity: true)
                }
                for path in minimal {
                    do {
                        let url = URL(fileURLWithPath: path)
                        let values = try url.resourceValues(forKeys: [.isHiddenKey,.isDirectoryKey,.isPackageKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey])
                        let directory = values.isDirectory == true
                        if !rootSet.contains(path) {
                            updates.append(FileRecord(path: path, name: url.lastPathComponent, kind: .classify(url, directory: directory && values.isPackage != true), size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0, isHidden: values.isHidden == true))
                        }
                        if directory && values.isPackage != true && values.isSymbolicLink != true && recursive.contains(path) {
                            try flush()
                            let report = try Scanner().scan(root: url, store: store, cancelled: { cancel.isCancelled })
                            if report.cancelled { throw IndexError.database("文件变化核对被中断，将在下次启动继续") }
                            reports.append((path, report))
                        }
                    } catch let error as IndexError { throw error }
                      catch {
                        if isMissingFile(error) {
                            if rootSet.contains(path) { reports.append((path, ScanReport(scanned: 0, denied: [], cancelled: false, unavailable: true))) }
                            else { removals.append(path) }
                        } else { reports.append((path, ScanReport(scanned: 0, denied: [path], cancelled: false))) }
                    }
                    if updates.count + removals.count >= 500 { try flush() }
                }
                try flush()
                let count = minimal.isEmpty ? nil : try store.count()
                DispatchQueue.main.async {
                    for (path, report) in reports { self.mergeCoverage(path, report: report) }
                    // Advance only after every write in this event batch has committed.
                    if eventID > 0 { self.catalog.checkpoint = max(self.catalog.checkpoint ?? 0, eventID) }
                    self.saveCatalog(refresh: !minimal.isEmpty)
                    if let count, count != self.indexCount { self.indexCount = count }
                    self.applyingChanges = false
                    let nextStatus = self.monitoring ? "搜索已就绪 · 文件变化时自动更新" : "自动更新未启动，请手动核对索引"
                    if self.status != nextStatus { self.status = nextStatus }
                    // Changes outside the selected folder, or to hidden program data,
                    // cannot change the current visible result set.
                    let affectsResults = minimal.contains { path in
                        let inScope = self.scope.map { scope in scope == "/" || path == scope || path.hasPrefix(scope + "/") || scope.hasPrefix(path == "/" ? "/" : path + "/") } ?? true
                        return inScope && (self.showSystemFiles || !IndexStore.isSystemOrGenerated(path))
                    }
                    if affectsResults { self.search() }
                    if self.pendingEventID > 0 || !self.changed.isEmpty { self.scheduleChanges() }
                }
            } catch {
                DispatchQueue.main.async {
                    self.applyingChanges = false; self.changed.formUnion(minimal); self.recursiveChanges.formUnion(recursive)
                    self.pendingEventID = max(self.pendingEventID, eventID)
                    self.status = "部分变化尚未核对，下次启动会继续"; self.issue = error.localizedDescription
                    // Keep the old persisted cursor. A restart replays this batch.
                }
            }
        }
    }
}
