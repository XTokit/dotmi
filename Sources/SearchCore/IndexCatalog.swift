import Foundation

public enum CoverageState: String, Codable {
    case pending, scanning, ready, partial, offline, interrupted
    public var title: String {
        switch self {
        case .pending: return "尚未索引"
        case .scanning: return "正在索引"
        case .ready: return "已完成"
        case .partial: return "部分位置无法访问"
        case .offline: return "位置离线或不存在"
        case .interrupted: return "扫描未完成"
        }
    }
}

public struct RootCoverage: Codable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var state: CoverageState = .pending
    public var scanned: Int = 0
    public var lastScanned: Date?
    public var identity: String?
    public var denied: [String] = []
    public var excluded: [String] = []
    public init(path: String) { self.path = path }
}

public struct IndexCatalog: Codable {
    public var format = 1
    public var checkpoint: UInt64?
    public var roots: [String: RootCoverage] = [:]
    public init() {}
    public static func load(_ url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.format == 1 else { throw IndexError.database("不支持的索引状态版本") }
        return value
    }
    public func save(_ url: URL) throws { try JSONEncoder().encode(self).write(to: url, options: .atomic) }
    public static func identity(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeDirectory,
              let inode = attrs[.systemFileNumber] as? NSNumber else { return nil }
        let volume = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString ?? "local"
        return volume + ":" + inode.stringValue
    }
    // This policy never walks a directory: only explicit incomplete roots and
    // changed/reconnected volumes need a baseline scan on ordinary startup.
    public func needsBaseline(_ path: String, identity: String?) -> Bool {
        guard let identity else { return false }
        guard let root = roots[path], checkpoint != nil else { return true }
        return ![CoverageState.ready, .partial].contains(root.state) || root.identity != identity
    }
    public mutating func record(_ path: String, report: ScanReport) {
        var value = roots[path] ?? RootCoverage(path: path)
        if report.unavailable { value.state = .offline; roots[path] = value; return }
        value.state = report.unavailable ? .offline : report.cancelled ? .interrupted : report.denied.isEmpty ? .ready : .partial
        if !report.cancelled { value.scanned = report.scanned }
        value.lastScanned = report.cancelled || report.unavailable ? value.lastScanned : Date()
        value.identity = Self.identity(path)
        value.denied = report.cancelled ? Array(Set(value.denied + report.denied)) : report.denied
        value.excluded = report.cancelled ? Array(Set(value.excluded + report.excluded)) : report.excluded
        roots[path] = value
    }
}
