import SwiftUI
import AppKit
import QuickLookUI
import SearchCore

private enum Workbench {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let inset = Color(nsColor: .controlBackgroundColor)
    static let accent = Color.accentColor
    static let spacing: CGFloat = 16
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// Intent: find a local file, verify its path, then return to Finder in one action.
// Hierarchy: search first; type groups second; path and metadata stay subordinate.
// Palette/depth: native paper, graphite, Finder blue; quiet surface shifts, 4pt rhythm.
// Typography: system 13pt rows, 11pt paths, semibold group titles; native focus states.
struct ContentView: View {
    @ObservedObject var model: SearchModel
    @AppStorage("visualStyle") private var style = "spotlight"
    @FocusState private var searchFocused: Bool
    @FocusState private var resultListFocused: Bool
    @State private var showCoverage = false
    @State private var showFavorites = false
    @State private var coverageTab = 0
    @State private var showPermissionHelp = false
    @State private var showSortOptions = false
    @State private var showSearchActivity = false
    @State private var showFilters = false
    @State private var browseAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("permissionHelpDismissed") private var permissionHelpDismissed = false
    private var compact: Bool { style == "professional" || light }
    private var light: Bool { style == "spotlight" }
    private var resultRowMinHeight: CGFloat { light ? 58 : compact ? 48 : 64 }
    private var resultRowVerticalPadding: CGFloat { light ? 7 : compact ? 4 : 8 }
    private var resultIconSize: CGFloat { light ? 28 : compact ? 26 : 32 }
    var body: some View {
        HStack(spacing: 0) {
            if !light { sidebar.frame(width: 204); Divider() }
            VStack(spacing: 0) {
                searchHeader
                Divider()
                if model.roots.isEmpty { welcome }
                else if model.query.isEmpty && model.kind == nil && !browseAll { quickStart }
                else { results }
                Divider()
                statusBar
            }.frame(minWidth: 440, maxWidth: .infinity)
            if !light { Divider(); previewPane.frame(width: 280) }
        }
        .background(Workbench.canvas)
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                    Text(notice.message).lineLimit(2)
                    Button { model.dismissNotice() } label: {
                        Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24)
                    }.buttonStyle(InteractionButtonStyle()).help("关闭提示").accessibilityLabel("关闭提示")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
                .padding(.horizontal, 20).padding(.bottom, 44)
                .id(notice.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
                .accessibilityLabel(notice.message)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.notice?.id)
        .tint(.accentColor)
        .onReceive(NotificationCenter.default.publisher(for: .init("XunjiFocusSearch"))) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .init("XunjiFocusResults"))) { _ in
            browseAll = true
            searchFocused = false
            DispatchQueue.main.async { resultListFocused = true }
        }
        .onChange(of: searchFocused) { model.searchFieldActive = $0 }
        .onChange(of: resultListFocused) { model.resultsActive = $0 }
        .onChange(of: showSortOptions) { _ in model.transientPanelActive = showSortOptions || showFilters }
        .onChange(of: showFilters) { _ in model.transientPanelActive = showSortOptions || showFilters }
        .onChange(of: model.query) { if $0.isEmpty { browseAll = false } }
        .onAppear { searchFocused = true }
        .onChange(of: model.scope) { path in
            browseAll = true
            if path == nil { model.showNotice("已返回\(model.scopeTitle)") }
        }
        .task(id: model.searching) {
            showSearchActivity = false
            guard model.searching else { return }
            do { try await Task.sleep(nanoseconds: 220_000_000) } catch { return }
            if model.searching { showSearchActivity = true }
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
                if showSearchActivity { ProgressView().controlSize(.small).help("正在搜索本地索引") }
                if !model.query.isEmpty { Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("清空搜索") }
            }.padding(light ? 12 : 16).background(Workbench.inset.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(searchFocused ? Workbench.accent.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: searchFocused ? 1.5 : 1))
            HStack(spacing: 10) {
                Menu {
                    Button("整台 Mac") { browseAll = true; model.indexComputer() }
                    Button("全部已索引位置") { browseAll = true; model.scope = nil }
                    Divider()
                    Button("选择文件夹…") { model.chooseFolder() }
                    ForEach(model.favoriteFolders, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { model.selectFolder(path) }.help(path)
                    }
                    Divider()
                    if let path = model.scope {
                        Button(model.favoriteFolders.contains(path) ? "移出常用文件夹" : "加入常用文件夹") {
                            if model.favoriteFolders.contains(path) { model.removeFavorite(path) } else { model.addFavorite(path) }
                        }
                    }
                    Button("管理常用文件夹…") { showFavorites = true }
                    Button("索引管理…") { showCoverage = true }
                } label: {
                    Label("范围：\(model.scopeTitle)", systemImage: model.scope == nil ? "desktopcomputer" : "folder")
                        .lineLimit(1).truncationMode(.middle)
                }
                .help(model.scope ?? "搜索全部已索引位置")
                .accessibilityLabel("当前搜索范围：\(model.scopeTitle)")
                if let path = model.scope {
                    Text(URL(fileURLWithPath: path).deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
                }
                Spacer(minLength: 0)
                if !permissionHelpDismissed || !model.denied.isEmpty {
                    Button { showPermissionHelp = true } label: { Image(systemName: "lock.shield") }
                        .help(model.denied.isEmpty ? "访问权限" : "部分位置无法访问，查看权限说明")
                        .accessibilityLabel("访问权限")
                }
                Button { showFilters.toggle() } label: { Label(activeFilterCount == 0 ? "筛选" : "筛选 (\(activeFilterCount))", systemImage: "line.3.horizontal.decrease.circle") }
                    .popover(isPresented: $showFilters) { filterOptions }
            }.font(.system(size: 12)).controlSize(.regular)
            if activeFilterCount > 0 {
                HStack(spacing: 8) {
                    Text([!model.recursive ? "仅当前文件夹" : nil, model.includePath ? "匹配路径" : nil, model.showSystemFiles ? "含系统与程序文件" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("重置") { model.recursive = true; model.includePath = false; model.showSystemFiles = false }.font(.system(size: 11))
                }
            }
            HStack(spacing: 6) {
                typeChip(nil, compact: true)
                ForEach(FileKind.allCases) { typeChip($0, compact: true) }
            }
        }.padding(light ? 16 : 20)
    }
    private var activeFilterCount: Int { (model.recursive ? 0 : 1) + (model.includePath ? 1 : 0) + (model.showSystemFiles ? 1 : 0) }
    private var filterOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("搜索选项").font(.headline)
            Toggle("包含子文件夹", isOn: $model.recursive)
            Toggle("同时匹配路径", isOn: $model.includePath)
            Toggle("显示系统与程序文件", isOn: $model.showSystemFiles)
            Text("显示开关只影响已索引结果；被排除的目录需单独补充索引。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Button("索引管理…") { showFilters = false; showCoverage = true }
            Button("访问权限…") { showFilters = false; showPermissionHelp = true }
            Button("完成") { showFilters = false }
        }.toggleStyle(.checkbox).font(.system(size: 12)).padding(20).frame(width: 300)
            .background(Color(nsColor: .controlBackgroundColor))
            .onExitCommand { showFilters = false }
    }
    private var quickStart: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("从这里开始").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("浏览此范围全部文件") { browseAll = true }
                }
                Text("输入文件名关键词，按回车在 Finder 中定位。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("桌面") { model.selectFolder(NSHomeDirectory() + "/Desktop"); browseAll = true }
                    Button("文稿") { model.selectFolder(NSHomeDirectory() + "/Documents"); browseAll = true }
                    Button("下载") { model.selectFolder(NSHomeDirectory() + "/Downloads"); browseAll = true }
                    Button("选择文件夹…") { model.chooseFolder() }
                }
                if !model.favoriteFolders.isEmpty {
                    Text("常用文件夹").font(.system(size: 12, weight: .semibold))
                    ForEach(model.favoriteFolders.prefix(4), id: \.self) { path in
                        Button { model.selectFolder(path); browseAll = true } label: {
                            Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading)
                        }.help(path)
                    }
                }
                if !model.recentFiles.isEmpty {
                    HStack {
                        Text("最近定位 / 打开").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("清除记录") { model.clearRecentFiles() }.font(.system(size: 11))
                    }
                    ForEach(model.recentFiles.prefix(6)) { file in
                        Button { model.reveal(file) } label: {
                            HStack {
                                FileIcon(path: file.path).frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(file.name).font(.system(size: 13)).lineLimit(1)
                                    Text(file.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                            }.frame(minHeight: 50).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("在 Finder 中定位最近使用的文件：" + file.path)
                    }
                }
            }.padding(20)
        }
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
    private func typeChip(_ kind: FileKind?, compact: Bool = false) -> some View {
        let count = kind.map { model.counts[$0, default: 0] } ?? model.counts.values.reduce(0,+)
        return Button { model.kind = kind } label: {
            Group {
                if compact {
                    VStack(spacing: 2) {
                        Text(kind?.title ?? "全部").lineLimit(1)
                        Text(count.formatted()).font(.system(size: 10)).monospacedDigit().opacity(0.65).lineLimit(1).minimumScaleFactor(0.75)
                    }.padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    HStack(spacing: 5) { Text(kind?.title ?? "全部"); Text(count.formatted()).font(.system(size: 10)).monospacedDigit().opacity(0.65) }
                        .padding(.horizontal, 12).frame(minWidth: 70, minHeight: 40)
                }
            }
                .font(.system(size: 12, weight: .medium))
                .contentShape(Rectangle())
        }
        .buttonStyle(FilterChipStyle(selected: model.kind == kind))
        .accessibilityLabel("\(kind?.title ?? "全部")，\(count.formatted()) 项")
        .accessibilityValue(model.kind == kind ? "已选中" : "未选中")
        .help("只查看\(kind?.title ?? "全部类型")的搜索结果")
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.total == 0 ? "搜索结果" : "找到 \(model.total.formatted()) 项").font(.system(size: 12, weight: .medium)).monospacedDigit()
                Spacer()
                Button { showSortOptions.toggle() } label: {
                    HStack(spacing: 8) { Text(model.sortOrder.title); Image(systemName: "chevron.down").font(.system(size: 9)) }
                        .frame(width: 112, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("排序：" + model.sortOrder.title)
                .popover(isPresented: $showSortOptions, arrowEdge: .bottom) {
                    SortOptionsPanel(selected: model.sortOrder, choose: { order in
                        showSortOptions = false
                        if model.sortOrder != order { model.sortOrder = order }
                    }, dismiss: { showSortOptions = false })
                        .frame(width: 190, height: 136)
                        .background(Color(nsColor: .controlBackgroundColor))
                }
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
                ScrollViewReader { proxy in
                List(selection: $model.selected) {
                    ForEach(model.files) { file in row(file).tag(file.path).id(file.path) }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, resultRowMinHeight)
                .focused($resultListFocused)
                .onChange(of: model.selected) { path in
                    if let path { proxy.scrollTo(path) }
                }
                .onChange(of: model.resultScrollReset) { _ in
                    if let path = model.files.first?.path { proxy.scrollTo(path, anchor: .top) }
                }
                .onAppear { if let path = model.selected { proxy.scrollTo(path, anchor: .top) } }
                }
            }
            if model.total > model.files.count {
                HStack {
                    Text("已显示 \(model.files.count.formatted()) / \(model.total.formatted()) 项").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if model.canLoadMore { Button("继续加载 200 项") { model.loadMoreResults() }.disabled(model.searching).font(.system(size: 11)) }
                    else { Text("输入更多关键词以缩小范围").font(.system(size: 11)).foregroundStyle(.secondary) }
                }.padding(8)
            }
        }.frame(maxHeight: .infinity)
    }
    private func row(_ file: FileRecord) -> some View {
        ResultFileRow(file: file, query: model.query, selected: model.selected == file.path,
                      iconSize: resultIconSize, verticalPadding: resultRowVerticalPadding,
                      onSelect: { selectResult(file) },
                      onReveal: { selectResult(file); model.reveal(file) },
                      onOpen: { model.selected = file.path; model.openSelection() },
                      onPreview: { model.preview = file },
                      onCopy: { model.selected = file.path; model.copyPath() })
            .equatable()
    }
    private func selectResult(_ file: FileRecord) {
        guard !model.searching else { return }
        model.selected = file.path
        // Button clicks settle their own focus after the action runs. Request the
        // list focus on the next run-loop turn so active selection stays blue.
        DispatchQueue.main.async { resultListFocused = true }
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
    private var indexReady: Bool {
        model.monitoring && model.searchIndexReady && model.denied.isEmpty && !model.coverage.contains(where: { $0.state != .ready })
    }
    private var indexStatusText: String {
        if model.roots.isEmpty { return "选择搜索范围" }
        if model.indexing { return "正在更新索引…" }
        if !model.searchIndexReady { return "正在准备检索索引…" }
        if !model.denied.isEmpty || model.coverage.contains(where: { $0.state != .ready }) { return "部分位置需检查" }
        if !model.monitoring { return "文件变化监测未就绪" }
        return "已就绪"
    }
    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.indexing { ProgressView().controlSize(.mini); Button("停止") { model.stop() }.controlSize(.mini) }
            else { Circle().fill(indexReady ? Color.green : Color.orange).frame(width: 5, height: 5) }
            Button { showCoverage = true } label: {
                Text(indexStatusText)
                    .lineLimit(1)
            }.buttonStyle(.plain).help(model.status + "；点击查看索引管理")
            Spacer()
            if light { Text("↑↓ 选择 · ↵ 定位 · 空格预览").foregroundStyle(.secondary) }
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
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

// 值未改变的行保留渲染结果。选中一行时，仅前后两行需要重新生成高亮与元数据。
private struct ResultFileRow: View, Equatable {
    let file: FileRecord
    let query: String
    let selected: Bool
    let iconSize: CGFloat
    let verticalPadding: CGFloat
    let onSelect: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onCopy: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.file == rhs.file && lhs.query == rhs.query && lhs.selected == rhs.selected
            && lhs.iconSize == rhs.iconSize && lhs.verticalPadding == rhs.verticalPadding
    }
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    FileIcon(path: file.path).frame(width: iconSize, height: iconSize)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(filenameWithMatches(file.name, query: query, selected: selected))
                            .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(file.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if file.modified > 0 {
                        Text(Workbench.shortDate.string(from: Date(timeIntervalSince1970: file.modified)))
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                            .frame(width: 76, alignment: .trailing)
                    }
                    Text(file.kind == .folder ? "—" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { _ in onReveal() })
            Button(action: onReveal) {
                Image(systemName: "arrow.up.forward.square").frame(width: 40, height: 40).contentShape(Rectangle())
            }.buttonStyle(InteractionButtonStyle())
                .help("在 Finder 中显示：\(file.name)").accessibilityLabel("在 Finder 中显示：\(file.name)")
        }
        .padding(.vertical, verticalPadding).contentShape(Rectangle())
        .modifier(ResultRowHover(selected: selected)).help(file.path)
        .contextMenu {
            Button("在 Finder 中显示", action: onReveal)
            Button("打开文件", action: onOpen)
            Button("快速预览", action: onPreview)
            Button("复制路径", action: onCopy)
        }
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
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 4096
        return cache
    }()
    private var icon: NSImage {
        let key = path as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        Self.cache.setObject(image, forKey: key)
        return image
    }
    var body: some View { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true) }
}

struct SettingsView: View {
    @ObservedObject var model: SearchModel
    @AppStorage("visualStyle") private var style = "spotlight"
    @AppStorage("globalHotKeyChoice") private var hotKeyChoice = GlobalHotKeyChoice.commandShift.rawValue
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
                Picker("全局快捷键", selection: $hotKeyChoice) {
                    ForEach(GlobalHotKeyChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if !model.hotKeyStatus.isEmpty { Text(model.hotKeyStatus).font(.system(size: 11)).foregroundStyle(.secondary) }
                LabeledContent("索引数量", value: model.indexCount.formatted())
                DisclosureGroup("响应诊断") {
                    Text(model.responseTiming).font(.system(size: 11)).textSelection(.enabled)
                    Text("统计截至主线程发布结果，不包含最终屏幕绘制；不会记录文件名或查询内容。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Section("访问权限") {
                Toggle("在主窗口显示权限说明入口", isOn: Binding(get: { !permissionHelpDismissed }, set: { permissionHelpDismissed = !$0 }))
                Button("打开完全磁盘访问设置") { model.openDiskAccessSettings() }
            }
            Section("关于点觅 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
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
