import SwiftUI

// A single reading surface: native type, neutral background, aligned sections.
// The search window keeps controls; these explanations appear only on request.
struct SearchHelpContent: View {
    @AppStorage("globalHotKeyChoice") private var hotKeyChoice = GlobalHotKeyChoice.commandShift.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section("搜索范围与常用文件夹", "“选择文件夹”限定本次搜索；“常用文件夹”只保存快速切换入口，可用范围旁的星标添加或移除。收藏不会开始扫描；搜索该文件夹时会沿用已有索引，未覆盖时才建立索引。")
            section("索引管理", "索引是保存在本机的文件信息目录，用来加快搜索。已索引整台 Mac 后，普通文件夹无需重复添加。“补充索引”用于未覆盖或被排除的目录；外接磁盘需要先连接。“已完成”表示当前规则内已核对，不包含主动排除或无法访问的位置。")
            section("隐藏与跳过有什么区别", "“显示系统与程序文件”只改变已索引结果的展示，不删除文件。主动排除的目录没有加入索引，开关不会让它们自动出现；需要时可单独添加该目录。无法访问的位置则需要检查权限。")
            section("搜索与文件定位", "按文件名搜索，空格分隔多个关键词；“匹配路径”可搜索所在位置。先加载 200 项，可继续加载至 2,000 项；分类数量统计全部匹配结果，点击分类可直接查找该类文件。先选择结果，再点“在 Finder 中显示选中文件”定位该文件；它不会打开当前搜索范围。文件变化时后台更新，首次索引或大量文件变化时会占用一些电脑资源。")
            VStack(alignment: .leading, spacing: 10) {
                Text("常用快捷键").font(.system(size: 13, weight: .semibold))
                LabeledContent("全局唤起", value: (GlobalHotKeyChoice(rawValue: hotKeyChoice) ?? .commandShift).title)
                LabeledContent("聚焦搜索", value: "⌘F")
                LabeledContent("选择文件夹", value: "⌘⇧O")
                LabeledContent("选择结果", value: "↑ / ↓")
                LabeledContent("在 Finder 中显示", value: "回车 / ⌘R")
                LabeledContent("快速预览", value: "结果列表中按空格 / ⌘Y")
                LabeledContent("关闭预览", value: "空格 / Esc")
                LabeledContent("打开文件", value: "⌘回车")
            }.font(.system(size: 12))
            section("排序与最近记录", "“相关性优先”将名称完全匹配、去掉扩展名后的完全匹配和名称前缀匹配排在前面。空搜索提供常用范围和最近在点觅中定位或打开的文件，可清除记录，也可选择浏览全部文件。排序和各风格的窗口大小与位置会保存在本机。")
        }.padding(4)
    }
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SearchHelpView: View {
    @ObservedObject var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPermissions = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("使用说明").font(.title2.bold()); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView { SearchHelpContent().frame(maxWidth: .infinity, alignment: .leading) }
            Button("访问权限设置…") { showPermissions = true }
        }.padding(24).frame(width: 620, height: 600)
            .sheet(isPresented: $showPermissions) { PermissionHelpView(model: model) }
    }
}
