import SwiftUI
import AppKit
import QuickLookUI
import SearchCore

private enum Workbench {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let inset = Color(nsColor: .controlBackgroundColor)
    static let accent = Color.accentColor
    static let spacing: CGFloat = 16
}

// Intent: find a local file, verify its path, then return to Finder in one action.
// Hierarchy: search first; type groups second; path and metadata stay subordinate.
// Palette/depth: native paper, graphite, Finder blue; quiet surface shifts, 4pt rhythm.
// Typography: system 13pt rows, 11pt paths, semibold group titles; native focus states.
struct ContentView: View {
    @ObservedObject var model: SearchModel
    @AppStorage("visualStyle") private var style = "spotlight"
    @FocusState private var searchFocused: Bool
    @State private var showCoverage = false
    @State private var showFavorites = false
    @State private var coverageTab = 0
    @State private var showPermissionHelp = false
    @AppStorage("permissionHelpDismissed") private var permissionHelpDismissed = false
    private var compact: Bool { style == "professional" || light }
    private var light: Bool { style == "spotlight" }
    var body: some View {
        HStack(spacing: 0) {
            if !light { sidebar.frame(width: 204); Divider() }
            VStack(spacing: 0) {
                searchHeader
                Divider()
                if model.roots.isEmpty { welcome }
                else { results }
                Divider()
                statusBar
            }.frame(minWidth: 440, maxWidth: .infinity)
            if !light { Divider(); previewPane.frame(width: 280) }
        }
        .background(Workbench.canvas)
        .tint(.accentColor)
        .onReceive(NotificationCenter.default.publisher(for: .init("XunjiFocusSearch"))) { _ in searchFocused = true }
        .onAppear { searchFocused = true }
        .sheet(item: $model.preview) { file in
            VStack(spacing: 0) {
                HStack { Text(file.name).font(.headline); Spacer(); Button("完成") { model.preview = nil }.keyboardShortcut(.cancelAction) }.padding()
                QuickPreview(url: file.url).frame(minWidth: 700, minHeight: 500)
            }
        }
        .sheet(isPresented: $showCoverage) { coverage }
        .sheet(isPresented: $showFavorites) { FavoritesView(model: model) }
        .sheet(isPresented: $showPermissionHelp) { PermissionHelpView(model: model) }
        .alert("点觅", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) { Button("好") { model.issue = nil } } message: { Text(model.issue ?? "") }
        .toolbar {
            ToolbarItemGroup {
                Button { model.reveal() } label: { Label("在 Finder 中显示选中文件", systemImage: "arrow.up.forward.square").labelStyle(.titleAndIcon) }.disabled(model.selection == nil).help(model.selection.map { "在 Finder 中选中：" + $0.name + "（⌘R）" } ?? "先选择一条搜索结果")
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) { Text("点觅").font(.system(size: 19, weight: .semibold)); Text("文件，即刻找到").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.top, 12)
            VStack(alignment: .leading, spacing: 4) {
                Text("搜索范围").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.bottom, 6)
                computerScopeButton
                scopeButton("全部已索引位置", icon: "externaldrive", path: nil)
                scopeButton("桌面", icon: "menubar.dock.rectangle", path: NSHomeDirectory() + "/Desktop")
                scopeButton("文稿", icon: "doc.on.doc", path: NSHomeDirectory() + "/Documents")
                scopeButton("下载", icon: "arrow.down.circle", path: NSHomeDirectory() + "/Downloads")
                ForEach(model.favoriteFolders, id: \.self) { path in
                    scopeButton(URL(fileURLWithPath: path).lastPathComponent, icon: "folder", path: path)
                }
                Button("管理常用文件夹…") { showFavorites = true }.font(.system(size: 11)).buttonStyle(.link)
                Button { model.chooseFolder() } label: { Label("选择其他文件夹…", systemImage: "plus").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }.buttonStyle(.plain).disabled(model.indexing).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("搜索选项").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Toggle("包含子文件夹", isOn: $model.recursive).font(.system(size: 12))
                Toggle("同时匹配路径", isOn: $model.includePath).font(.system(size: 12))
            }.toggleStyle(.checkbox)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("\(model.indexCount.formatted()) 项已索引").font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
        }.padding(16).frame(maxHeight: .infinity).background(Workbench.canvas)
    }
    private func scopeButton(_ title: String, icon: String, path: String?) -> some View {
        Button {
            if let path { model.selectFolder(path) } else { model.scope = nil; model.scopeNotice = "" }
        } label: {
            Label(title, systemImage: icon).font(.system(size: 12, weight: model.scope == path ? .semibold : .regular)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 9)
                .background(model.scope == path ? Workbench.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(model.scope == path ? Workbench.accent : .primary)
        }.buttonStyle(.plain).help(path ?? "搜索所有已建立索引的位置")
    }
    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: light ? 10 : 16) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 21)).foregroundStyle(Workbench.accent)
                TextField("输入文件名关键词…", text: $model.query).textFieldStyle(.plain).font(.system(size: light ? 20 : 23, weight: .medium)).focused($searchFocused)
                    .onSubmit { model.reveal() }
                    .accessibilityLabel("搜索文件名")
                if !model.query.isEmpty { Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("清空搜索") }
            }.padding(light ? 12 : 16).background(Workbench.inset.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                if light { computerScopeButton }
                Spacer()
                if light {
                    Button("选择文件夹…") { model.chooseFolder() }.font(.system(size: 11))
                    favoritesMenu
                    Toggle("子文件夹", isOn: $model.recursive).toggleStyle(.checkbox).font(.system(size: 11))
                    Toggle("匹配路径", isOn: $model.includePath).toggleStyle(.checkbox).font(.system(size: 11))
                }
                if !permissionHelpDismissed || !model.denied.isEmpty {
                    Button { showPermissionHelp = true } label: { Label(model.denied.isEmpty ? "访问权限" : "部分位置无法访问", systemImage: "lock.shield") }.font(.system(size: 11)).help("查看权限说明；完成设置后可隐藏此入口")
                }
                if model.scope != nil && !light { Button("搜索整台 Mac") { model.indexComputer() }.buttonStyle(.link).font(.system(size: 11)) }
            }
            scopeBanner
            HStack {
                Toggle("显示系统与程序文件", isOn: $model.showSystemFiles)
                    .toggleStyle(.checkbox).font(.system(size: 11))
                    .help("显示已索引的隐藏文件、程序目录和依赖文件；已排除的目录需单独选择后建立索引。")
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    typeChip(nil)
                    ForEach(FileKind.allCases) { typeChip($0) }
                }
            }
        }.padding(light ? 16 : 20)
    }
    private var scopeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.scope == nil ? "desktopcomputer" : "folder.fill").foregroundStyle(Workbench.accent).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("当前搜索范围：\(model.scopeTitle)").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let path = model.scope {
                        Button {
                            if model.favoriteFolders.contains(path) { model.removeFavorite(path) } else { model.addFavorite(path) }
                        } label: { Image(systemName: model.favoriteFolders.contains(path) ? "star.fill" : "star") }
                            .buttonStyle(.plain).help(model.favoriteFolders.contains(path) ? "移出常用文件夹" : "加入常用文件夹")
                    }
                }
                if let path = model.scope {
                    Text(path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).truncationMode(.middle).help(path)
                }
                if model.indexing && !model.scopeNotice.isEmpty { Text(model.scopeNotice).font(.system(size: 10)).foregroundStyle(.secondary) }
                if !model.roots.isEmpty {
                    Button { showCoverage = true } label: { Label("索引管理…", systemImage: "externaldrive.badge.gearshape").lineLimit(2).multilineTextAlignment(.leading) }
                        .font(.system(size: 10)).buttonStyle(.link).help("查看已完成、无权限、排除和离线的位置")
                }
            }
            if model.scope != nil { Button { model.scope = nil; model.scopeNotice = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("清除文件夹限制，返回全部已索引位置") }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Workbench.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
    }
    private var favoritesMenu: some View {
        Menu {
            if model.favoriteFolders.isEmpty { Text("尚未添加常用文件夹") }
            ForEach(model.favoriteFolders, id: \.self) { path in
                Button { model.selectFolder(path) } label: { Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder") }
                    .help(path)
            }
            Divider()
            Button("加入常用文件夹…") { model.chooseFolder(purpose: .favorite) }
            Button("管理常用文件夹…") { showFavorites = true }
        } label: { Label("常用文件夹", systemImage: "star") }.font(.system(size: 11)).fixedSize()
    }
    private var computerScopeButton: some View {
        Button { model.indexComputer() } label: {
            Label("整台 Mac", systemImage: "desktopcomputer")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: light ? nil : .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(model.scope == nil && model.roots.contains("/") ? Workbench.accent.opacity(0.12) : Workbench.inset, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("搜索全电脑可访问的文件；首次点击自动建立全盘索引")
        .accessibilityLabel("搜索整台 Mac")
    }
    private func typeChip(_ kind: FileKind?) -> some View {
        let count = kind.map { model.counts[$0, default: 0] } ?? model.counts.values.reduce(0,+)
        return Button { model.kind = kind } label: {
            HStack(spacing: 5) { Text(kind?.title ?? "全部"); Text(count.formatted()).font(.system(size: 10)).monospacedDigit().opacity(0.65) }
                .font(.system(size: 11, weight: model.kind == kind ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(model.kind == kind ? Workbench.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(model.kind == kind ? Workbench.accent : .secondary)
        }.buttonStyle(.plain)
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.total == 0 ? "搜索结果" : "找到 \(model.total.formatted()) 项").font(.system(size: 12, weight: .medium)).monospacedDigit()
                Spacer()
                Toggle("按类型分组", isOn: $model.grouped).toggleStyle(.checkbox).font(.system(size: 11))
                Picker("排序", selection: $model.newest) { Text("名称排序").tag(false); Text("最近修改").tag(true) }.labelsHidden().frame(width: 100).controlSize(.small)
            }.padding(.horizontal, 20).padding(.vertical, 10)
            if model.files.isEmpty {
                VStack(spacing: 12) {
                    let feedback = model.emptyFeedback
                    if feedback == .searching || feedback == .indexing { ProgressView().controlSize(.small) }
                    else { Image(systemName: feedback == .denied ? "lock.shield" : feedback == .offline ? "externaldrive.badge.exclamationmark" : "doc.text.magnifyingglass").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.secondary) }
                    Text(feedback.title).font(.headline)
                    Text(feedback.detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 410)
                    if feedback == .filtered { Button("清除结果筛选") { model.clearResultFilters() } }
                    else if feedback == .noMatch && !model.showSystemFiles { Button("同时查找已索引的隐藏文件") { model.showSystemFiles = true } }
                    else if feedback == .denied { Button("访问权限…") { showPermissionHelp = true } }
                    else if feedback == .failed { Button("重试搜索") { model.search() } }
                    if feedback != .searching && feedback != .indexing {
                        Button("查看索引管理…") { showCoverage = true }.buttonStyle(.link).font(.system(size: 11))
                    }
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selected) {
                    if model.grouped {
                        ForEach(FileKind.allCases) { kind in
                            let group = model.files.filter { $0.kind == kind }
                            if !group.isEmpty {
                                Section {
                                    ForEach(group) { file in row(file).tag(file.path) }
                                } header: {
                                    HStack(spacing: 8) { Image(systemName: kind.symbol); Text(kind.title); Text("\(model.counts[kind, default: 0])").foregroundStyle(.secondary).monospacedDigit() }.font(.system(size: 11, weight: .semibold)).padding(.vertical, light ? 2 : 6)
                                }
                            }
                        }
                    } else { ForEach(model.files) { file in row(file).tag(file.path) } }
                }.listStyle(.inset).environment(\.defaultMinListRowHeight, compact ? 40 : 56)
            }
            if model.total > model.files.count { Text("已显示前 \(model.files.count.formatted()) 项，共 \(model.total.formatted()) 项；输入更多关键词以缩小范围。").font(.system(size: 11)).foregroundStyle(.secondary).padding(8) }
        }.frame(maxHeight: .infinity)
    }
    private func row(_ file: FileRecord) -> some View {
        HStack(spacing: 12) {
            FileIcon(path: file.path).frame(width: compact ? 24 : 32, height: compact ? 24 : 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if style == "professional" { Text(Date(timeIntervalSince1970: file.modified), style: .date).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 76, alignment: .trailing) }
            Text(file.kind == .folder ? "—" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
            Button { model.reveal(file) } label: { Image(systemName: "arrow.up.forward.square").frame(width: 28, height: 28) }.buttonStyle(.borderless).help("在 Finder 中显示")
        }
        .padding(.vertical, compact ? 2 : 6).contentShape(Rectangle())
        .onTapGesture(count: 2) { model.selected = file.path; model.reveal(file) }
        .contextMenu {
            Button("在 Finder 中显示") { model.reveal(file) }
            Button("打开文件") { model.selected = file.path; model.openSelection() }
            Button("快速预览") { model.preview = file }
            Button("复制路径") { model.selected = file.path; model.copyPath() }
        }
    }
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("文件预览").font(.system(size: 12, weight: .semibold)); Spacer(); Image(systemName: "sidebar.right").foregroundStyle(.tertiary) }
            if let file = model.selection {
                QuickPreview(url: file.url).frame(height: 240).clipped().background(Workbench.inset, in: RoundedRectangle(cornerRadius: 8))
                Text(file.name).font(.system(size: 15, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(file.kind.title).font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                detail("大小", file.kind == .folder ? "文件夹" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                detail("修改时间", Date(timeIntervalSince1970: file.modified).formatted(date: .abbreviated, time: .shortened))
                VStack(alignment: .leading, spacing: 6) { Text("位置").foregroundStyle(.secondary); Text(file.path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).lineLimit(6).truncationMode(.middle) }.font(.system(size: 11))
                Button { model.reveal() } label: { Label("在 Finder 中显示", systemImage: "arrow.up.forward.square").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.borderedProminent).help("⌘R")
                HStack { Button("打开") { model.openSelection() }; Button("快速预览") { model.preview = file }; Button { model.copyPath() } label: { Image(systemName: "doc.on.doc") }.help("复制文件路径") }.controlSize(.small)
            } else {
                Spacer()
                Image(systemName: "doc.viewfinder").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                Text("选择文件查看预览与位置").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            Text("⌘R 定位文件   ·   ⌘Y 快速预览").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(20).frame(maxHeight: .infinity, alignment: .topLeading)
    }
    private func detail(_ name: String, _ value: String) -> some View { HStack(alignment: .top) { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.system(size: 11)) }
    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.indexing { ProgressView().controlSize(.mini); Button("停止") { model.stop() }.controlSize(.mini) }
            else { Circle().fill(model.denied.isEmpty && model.monitoring && !model.coverage.contains(where: { $0.state != .ready }) ? Color.green : Color.orange).frame(width: 5, height: 5) }
            Text(model.status).lineLimit(1)
            Spacer()
            if light { Text("↑↓ 选择 · ↵ 定位 · ⌘Y 预览").foregroundStyle(.tertiary) }
            Text(String(format: "%.0f ms", model.milliseconds)).monospacedDigit()
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
    }
    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass.circle").font(.system(size: 68, weight: .ultraLight)).foregroundStyle(Workbench.accent)
            Text("让文件重新变得好找").font(.system(size: 23, weight: .semibold))
            Text("先选择要搜索的位置，建立本地文件索引。\n之后输入文件名关键词，即可按类型查看结果。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
            Button("搜索整台 Mac") { model.indexComputer() }.buttonStyle(.borderedProminent).controlSize(.large)
            HStack { Button("选择一个文件夹…") { model.chooseFolder() }; Button("仅搜索我的用户文件夹") { model.indexHome() } }.buttonStyle(.link).font(.system(size: 12))
            Text("不上传文件 · 无需订阅 · 首次索引后可离线搜索").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // Intent: locate files calmly; keep management and explanations off the search surface.
    // Hierarchy: positions first, Add at top; details/help use separate native tabs.
    // Palette/depth: Finder blue, folder blue, graphite, paper and muted gray; one inset surface.
    // Typography/spacing: native 12pt rows, 10pt metadata, 16pt groups on a 4pt rhythm.
    private var coverage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("索引管理").font(.title2.bold())
                Spacer()
                Button { showCoverage = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.chooseFolder(purpose: .index) } } label: { Label("补充索引…", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(model.indexing)
                Button("完成") { showCoverage = false }.keyboardShortcut(.cancelAction)
            }
            Picker("管理内容", selection: $coverageTab) {
                Text("索引覆盖").tag(0)
                Text("已跳过的位置").tag(1)
                Text("使用说明").tag(2)
            }.pickerStyle(.segmented)
            if coverageTab == 0 {
                Text("已索引整台 Mac 时，普通文件夹无需重复添加。只在搜索遗漏的位置或被排除的目录时补充索引。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                List {
                    ForEach(model.indexCoverage) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.path == "/" ? "desktopcomputer" : "folder.fill")
                                .foregroundStyle(Workbench.accent).frame(width: 20).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(item.path == "/" ? "整台 Mac" : URL(fileURLWithPath: item.path).lastPathComponent).fontWeight(.semibold)
                                    Label(item.state.title, systemImage: coverageSymbol(item.state)).font(.system(size: 10)).foregroundStyle(coverageColor(item.state))
                                }.font(.system(size: 12))
                                Text(item.path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle).help(item.path)
                                if let parent = model.coveringLocation(item.path) {
                                    Text("已包含在“\(parent == "/" ? "整台 Mac" : URL(fileURLWithPath: parent).lastPathComponent)”中 · 可单独搜索")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                } else if let date = item.lastScanned {
                                    Text("上次核对 \(date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("搜索此处") { model.selectFolder(item.path); showCoverage = false }.controlSize(.small)
                            Menu {
                                Button(item.state == .offline ? "重试连接" : "重新核对") { model.rebuild(paths: [item.path]) }.disabled(model.indexing)
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).help("更多操作")
                        }.padding(.vertical, 8)
                    }
                }.listStyle(.inset)
                HStack {
                    Text("\(model.indexCoverage.count) 个索引起点 · \(model.indexCount.formatted()) 项已索引").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if !model.searchIndexReady { Button("继续准备检索索引") { model.retrySearchUpgrade() }.disabled(model.indexing) }
                    Button("重新核对全部") { model.rebuild() }.disabled(model.indexing || model.roots.isEmpty)
                }
            } else if coverageTab == 1 {
                Text("主动排除与无法访问分开列出；数量按位置统计。").font(.system(size: 11)).foregroundStyle(.secondary)
                List {
                    if !model.denied.isEmpty {
                        Section("无法访问 · \(model.denied.count) 处") {
                            ForEach(model.denied, id: \.self) { path in Label(path, systemImage: "lock").font(.system(size: 11)).textSelection(.enabled).help(path) }
                        }
                    }
                    Section("主动排除 · \(model.exclusions.count) 处") {
                        if model.exclusions.isEmpty { Text("没有记录到排除的位置").foregroundStyle(.secondary) }
                        ForEach(model.exclusions, id: \.self) { path in Label(path, systemImage: "minus.circle").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).help(path) }
                    }
                }.listStyle(.inset)
                HStack {
                    Button("访问权限…") { openPermissionHelp() }
                    Spacer()
                    Button("重试无法访问的位置") { model.retryDenied() }.disabled(model.indexing || model.denied.isEmpty)
                }
            } else {
                ScrollView { SearchHelpContent().frame(maxWidth: .infinity, alignment: .leading) }
                HStack { Button("访问权限设置…") { openPermissionHelp() }; Spacer() }
            }
        }.padding(24).frame(width: 700, height: 620)
    }
    private func openPermissionHelp() {
        showCoverage = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showPermissionHelp = true }
    }
    private func coverageSymbol(_ state: CoverageState) -> String {
        switch state { case .ready: return "checkmark.circle.fill"; case .scanning: return "arrow.triangle.2.circlepath"; case .offline: return "externaldrive.badge.xmark"; case .partial: return "lock.circle"; case .interrupted,.pending: return "clock" }
    }
    private func coverageColor(_ state: CoverageState) -> Color {
        switch state { case .ready: return .green; case .partial,.interrupted: return .orange; case .scanning: return Workbench.accent; case .pending,.offline: return .secondary }
    }
}

struct QuickPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PreviewContainer { PreviewContainer() }
    func updateNSView(_ view: PreviewContainer, context: Context) { view.show(url) }
    static func dismantleNSView(_ view: PreviewContainer, coordinator: ()) { view.clear() }
}
struct FileIcon: View {
    let path: String
    var body: some View { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true) }
}

struct SettingsView: View {
    @ObservedObject var model: SearchModel
    @AppStorage("visualStyle") private var style = "spotlight"
    @AppStorage("permissionHelpDismissed") private var permissionHelpDismissed = false
    @State private var showHelp = false
    var body: some View {
        Form {
            Section("外观") {
                Picker("设计风格", selection: $style) {
                    Text("原生 Mac 简洁风").tag("native")
                    Text("Spotlight 轻量风").tag("spotlight")
                    Text("专业效率工具风").tag("professional")
                    Text("深色极简风").tag("dark")
                }
            }
            Section("搜索") {
                Toggle("显示系统与程序文件", isOn: $model.showSystemFiles)
                Text("关闭时收起隐藏文件、系统目录和常见程序数据。").font(.caption).foregroundStyle(.secondary)
                LabeledContent("全局快捷键", value: "⌘ ⇧ 空格")
                LabeledContent("索引数量", value: model.indexCount.formatted())
            }
            Section("访问权限") {
                Toggle("在主窗口显示权限说明入口", isOn: Binding(get: { !permissionHelpDismissed }, set: { permissionHelpDismissed = !$0 }))
                Button("打开完全磁盘访问设置") { model.openDiskAccessSettings() }
            }
            Section("关于点觅 1.9") {
                Text("原生 Mac 本地文件搜索 · 无需账号或付费 API").font(.caption)
                Button("使用说明与快捷键…") { showHelp = true }
            }
        }.formStyle(.grouped).padding().sheet(isPresented: $showHelp) { SearchHelpView(model: model) }
    }
}

struct PermissionHelpView: View {
    @ObservedObject var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("permissionHelpDismissed") private var permissionHelpDismissed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("访问权限").font(.title2.bold()); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("希望访问受保护的位置，可为点觅开启完全磁盘访问。通常设置一次即可，无需逐个子文件夹授权。").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Text("1. 打开“系统设置 → 隐私与安全性 → 完全磁盘访问权限”。")
                Text("2. 点击“＋”添加下面这个点觅应用，并开启开关。")
                Text("3. 重新打开点觅，在“索引管理 → 已跳过的位置”中重试无法访问的位置。")
            }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Text(Bundle.main.bundleURL.path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开系统设置") { model.openDiskAccessSettings() }.buttonStyle(.borderedProminent)
                Button("在 Finder 中显示本应用") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
            }
            Text("授权由你在系统设置中确认。完整磁盘权限不会取消系统自身的保护，也不会改变应用默认跳过的目录。此测试版更新或更换安装位置后，系统可能要求重新授权。").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("隐藏主窗口权限入口") { permissionHelpDismissed = true; dismiss() }
                .help("只隐藏入口，不更改系统权限；发现无法访问的位置时会再次提醒。")
        }.padding(24).frame(width: 600)
    }
}
