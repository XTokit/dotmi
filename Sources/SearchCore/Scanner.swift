import Foundation

public func canonicalPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return URL(fileURLWithPath: path).standardizedFileURL.path }
    defer { free(resolved) }
    return String(cString: resolved)
}
public func isMissingFile(_ error: Error) -> Bool {
    let value = error as NSError
    if value.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code) { return true }
    if value.domain == NSPOSIXErrorDomain && [Int(ENOENT),Int(ENOTDIR)].contains(value.code) { return true }
    if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { return isMissingFile(underlying) }
    return false
}

public struct ScanReport {
    public let scanned: Int
    public let denied: [String]
    public let cancelled: Bool
    public var excluded: [String] = []
    public var unavailable: Bool = false
    public init(scanned: Int, denied: [String], cancelled: Bool, excluded: [String] = [], unavailable: Bool = false) {
        self.scanned = scanned; self.denied = denied; self.cancelled = cancelled; self.excluded = excluded; self.unavailable = unavailable
    }
}

public final class Scanner {
    public init() {}
    public static let excludedPaths = ["/System", "/Library", "/private", "/dev", "/net", "/Network", "/cores"]
    public func scan(root: URL, store: IndexStore, cancelled: () -> Bool = { false }, progress: (Int) -> Void = { _ in }) throws -> ScanReport {
        let root = URL(fileURLWithPath: canonicalPath(root.path))
        let fm = FileManager.default
        let generation = UUID().uuidString
        let keys: [URLResourceKey] = [.isHiddenKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        var denied: [String] = [], skipped: [String] = [], batch: [FileRecord] = [], total = 0
        do { _ = try fm.attributesOfItem(atPath: root.path) }
        catch { return ScanReport(scanned: 0, denied: isMissingFile(error) ? [] : [root.path], cancelled: false, unavailable: isMissingFile(error)) }
        guard fm.isReadableFile(atPath: root.path) else { return ScanReport(scanned: 0, denied: [root.path], cancelled: false) }
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { url, error in if !isMissingFile(error) { denied.append(url.path) }; return true }) else {
            return ScanReport(scanned: 0, denied: [root.path], cancelled: false)
        }
        for case let url as URL in enumerator {
            if cancelled() { return ScanReport(scanned: total, denied: denied, cancelled: true, excluded: skipped) }
            if url.lastPathComponent == ".DS_Store" { continue }
            // System mirrors contain the same user files twice. Packages remain searchable as one file.
            if root.path == "/", Self.excludedPaths.contains(where: { url.path == $0 }) { skipped.append(url.path); enumerator.skipDescendants(); continue }
            if url.path == NSHomeDirectory() + "/Library" || url.path.hasSuffix("/.Trash") || url.path.hasSuffix("/.git") || url.path.hasSuffix("/.build") || url.path.hasSuffix("/node_modules") {
                skipped.append(url.path); enumerator.skipDescendants(); continue
            }
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                let directory = values.isDirectory == true
                if values.isSymbolicLink == true || values.isPackage == true { enumerator.skipDescendants() }
                batch.append(FileRecord(path: url.path, name: url.lastPathComponent, kind: FileKind.classify(url, directory: directory && values.isPackage != true), size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0, isHidden: values.isHidden == true))
                total += 1
                if batch.count >= 1000 { try store.upsert(batch, generation: generation); batch.removeAll(keepingCapacity: true); progress(total) }
            } catch let error as IndexError { throw error }
              catch { if !isMissingFile(error) { denied.append(url.path) } }
        }
        if !batch.isEmpty { try store.upsert(batch, generation: generation) }
        if cancelled() { return ScanReport(scanned: total, denied: denied, cancelled: true, excluded: skipped) }
        try store.removeStale(root: root.path, generation: generation, preserve: denied + skipped)
        progress(total)
        return ScanReport(scanned: total, denied: Array(Set(denied)), cancelled: false, excluded: skipped)
    }
}
