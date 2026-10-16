import Foundation

/// Explains missing results using coverage evidence, without guessing a permission failure.
public enum SearchFeedback: Equatable {
    case searching, failed, indexing, offline, denied, excluded, incomplete, filtered, noMatch
    public static func resolve(searching: Bool, failed: Bool, indexing: Bool, scope: String?, coverage: [RootCoverage], filtered: Bool) -> Self {
        if failed { return .failed }
        if searching { return .searching }
        // Prefer the most specific index: a supplemental root can cover a parent's exclusion.
        let relevant = scope.flatMap { path in coverage.filter { contains($0.path, path) }.max { $0.path.count < $1.path.count } }
        if let root = relevant, let scope {
            if root.state == .offline { return .offline }
            if root.denied.contains(where: { contains($0, scope) }) { return .denied }
            if root.excluded.contains(where: { contains($0, scope) }) { return .excluded }
        } else if scope == nil, !coverage.isEmpty, coverage.allSatisfy({ $0.state == .offline }) { return .offline }
        if indexing { return .indexing }
        if let root = relevant, [.pending, .scanning, .interrupted].contains(root.state) { return .incomplete }
        if filtered { return .filtered }
        return .noMatch
    }
    private static func contains(_ parent: String, _ path: String) -> Bool {
        parent == "/" || path == parent || path.hasPrefix(parent + "/")
    }
    public var title: String {
        switch self {
        case .searching: return "正在搜索…"
        case .failed: return "搜索暂时未完成"
        case .indexing: return "索引进行中，结果会陆续出现"
        case .offline: return "搜索位置离线或已不存在"
        case .denied: return "当前文件夹尚无法访问"
        case .excluded: return "当前文件夹未纳入索引"
        case .incomplete: return "当前范围的索引尚未完成"
        case .filtered: return "当前筛选下没有匹配文件"
        case .noMatch: return "没有找到匹配的文件"
        }
    }
    public var detail: String {
        switch self {
        case .searching: return "正在查询本地索引"
        case .failed: return "请重试；仍有问题时可在索引管理中重新核对。"
        case .indexing: return "可以继续输入关键词，无需等待扫描结束。"
        case .offline: return "请连接磁盘或确认文件夹仍存在，再重新核对索引。"
        case .denied: return "检查系统访问权限后，在索引管理中重试该位置。"
        case .excluded: return "该位置被索引规则排除；需要搜索时可单独补充索引。"
        case .incomplete: return "继续核对该范围，已有文件信息会保留。"
        case .filtered: return "可清除类型限制并包含子文件夹，再试一次。"
        case .noMatch: return "试试更短的关键词；若文件不在当前索引中，可查看索引管理。"
        }
    }
}
