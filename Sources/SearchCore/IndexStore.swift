import Foundation
import CSQLite

public enum FileKind: String, CaseIterable, Identifiable {
    case document, image, video, audio, folder, archive, code, other
    public var id: String { rawValue }
    public var title: String {
        switch self { case .document: return "文档"; case .image: return "图片"; case .video: return "视频"; case .audio: return "音频"; case .folder: return "文件夹"; case .archive: return "压缩包"; case .code: return "代码"; case .other: return "其他" }
    }
    public var symbol: String {
        switch self { case .document: return "doc.text"; case .image: return "photo"; case .video: return "film"; case .audio: return "waveform"; case .folder: return "folder"; case .archive: return "archivebox"; case .code: return "chevron.left.forwardslash.chevron.right"; case .other: return "doc" }
    }
    public static func classify(_ url: URL, directory: Bool) -> Self {
        if directory { return .folder }
        let ext = url.pathExtension.lowercased()
        if ["pdf","doc","docx","pages","xls","xlsx","numbers","ppt","pptx","key","txt","md","rtf","csv","epub"].contains(ext) { return .document }
        if ["jpg","jpeg","png","gif","heic","webp","tiff","tif","svg","psd","ai","avif","raw","dng"].contains(ext) { return .image }
        if ["mp4","mov","mkv","avi","webm","m4v"].contains(ext) { return .video }
        if ["mp3","wav","m4a","flac","aiff","aac","ogg"].contains(ext) { return .audio }
        if ["zip","rar","7z","gz","tar","dmg","pkg","xz"].contains(ext) { return .archive }
        if ["swift","py","js","ts","tsx","jsx","html","css","json","yaml","yml","toml","rs","go","c","h","cpp","java","sh","sql"].contains(ext) { return .code }
        return .other
    }
}

public struct FileRecord: Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let kind: FileKind
    public let size: Int64
    public let modified: Double
    public let isHidden: Bool
    public var url: URL { URL(fileURLWithPath: path) }
    public init(path: String, name: String, kind: FileKind, size: Int64 = 0, modified: Double = 0, isHidden: Bool = false) {
        self.path = path; self.name = name; self.kind = kind; self.size = size; self.modified = modified; self.isHidden = isHidden
    }
}

public struct SearchResult {
    public let files: [FileRecord]
    public let counts: [FileKind: Int]
    public let total: Int
    public let milliseconds: Double
}

public enum IndexError: Error, LocalizedError {
    case database(String)
    public var errorDescription: String? { switch self { case .database(let message): return "索引数据库：\(message)" } }
}

// Each connection belongs to one serial queue. WAL lets searches run while indexing.
public final class IndexStore {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw IndexError.database("无法打开索引") }
        sqlite3_busy_timeout(db, 5000)
        sqlite3_create_function_v2(db, "xunji_grams", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, values in
            guard let context, let value = values?[0], let bytes = sqlite3_value_text(value) else { sqlite3_result_null(context); return }
            let result = IndexStore.grams(String(cString: bytes))
            result.withCString { sqlite3_result_text(context, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        }, nil, nil, nil)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        try execute("CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, parent TEXT NOT NULL, name TEXT NOT NULL, folded TEXT NOT NULL, fullfold TEXT NOT NULL, kind TEXT NOT NULL, size INTEGER NOT NULL, modified REAL NOT NULL, generation TEXT NOT NULL);")
        try execute("CREATE INDEX IF NOT EXISTS files_parent ON files(parent); CREATE INDEX IF NOT EXISTS files_kind ON files(kind);")
        try execute("CREATE INDEX IF NOT EXISTS files_name_sort ON files(folded,path);")
        try execute("CREATE TABLE IF NOT EXISTS index_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);")
        sqlite3_create_function_v2(db, "xunji_noise", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, values in
            guard let context, let value = values?[0], let bytes = sqlite3_value_text(value) else { return }
            sqlite3_result_int(context, IndexStore.isSystemOrGenerated(String(cString: bytes)) ? 1 : 0)
        }, nil, nil, nil)
        // Upgrade the existing metadata in place; no disk traversal or FTS rebuild.
        try execute("BEGIN IMMEDIATE")
        do {
            let columns = try statement("PRAGMA table_info(files)")
            var hasNoise = false
            while sqlite3_step(columns) == SQLITE_ROW {
                if String(cString: sqlite3_column_text(columns, 1)) == "noise" { hasNoise = true }
            }
            sqlite3_finalize(columns)
            if !hasNoise {
                try execute("ALTER TABLE files ADD COLUMN noise INTEGER NOT NULL DEFAULT 0")
                try execute("UPDATE files SET noise=xunji_noise(path)")
            }
            try execute("CREATE INDEX IF NOT EXISTS files_visible_sort ON files(noise,folded,path)")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS file_search USING fts5(namegrams,pathgrams,content='',detail='column',tokenize='ascii');")
        // Only active after the one-time backfill is committed. Deletion supplies the
        // same gram set as insertion, as required by contentless FTS5 tables.
        try execute("""
        CREATE TRIGGER IF NOT EXISTS search_insert AFTER INSERT ON files
        WHEN (SELECT value FROM index_meta WHERE key='search_version')='1' BEGIN
          INSERT INTO file_search(rowid,namegrams,pathgrams) VALUES(new.rowid,xunji_grams(new.folded),xunji_grams(new.fullfold));
        END;
        CREATE TRIGGER IF NOT EXISTS search_delete AFTER DELETE ON files
        WHEN (SELECT value FROM index_meta WHERE key='search_version')='1' BEGIN
          INSERT INTO file_search(file_search,rowid,namegrams,pathgrams) VALUES('delete',old.rowid,xunji_grams(old.folded),xunji_grams(old.fullfold));
        END;
        CREATE TRIGGER IF NOT EXISTS search_update AFTER UPDATE OF folded,fullfold ON files
        WHEN (old.folded!=new.folded OR old.fullfold!=new.fullfold) AND (SELECT value FROM index_meta WHERE key='search_version')='1' BEGIN
          INSERT INTO file_search(file_search,rowid,namegrams,pathgrams) VALUES('delete',old.rowid,xunji_grams(old.folded),xunji_grams(old.fullfold));
          INSERT INTO file_search(rowid,namegrams,pathgrams) VALUES(new.rowid,xunji_grams(new.folded),xunji_grams(new.fullfold));
        END;
        """)
    }
    deinit { sqlite3_close(db) }
    private func error() -> IndexError { .database(String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String) throws { if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw error() } }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error() }
        return stmt
    }
    private func bind(_ values: [String], to stmt: OpaquePointer) {
        for (i, value) in values.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient) }
    }
    public static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    public static func isSystemOrGenerated(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        let systemRoots: Set<String> = ["System", "Library", "Applications", "private", "usr", "bin", "sbin", "dev", "cores", "opt", "net", "Network"]
        if let first = parts.first, systemRoots.contains(String(first)) { return true }
        let generated: Set<String> = ["Library", "node_modules", "__pycache__", "DerivedData", "Pods", "Carthage"]
        for component in parts {
            if component.hasPrefix(".") || generated.contains(String(component)) || component.lowercased().hasSuffix(".app") { return true }
        }
        // Specific generated artifacts, rather than all databases, logs or JSON files.
        let name = parts.last.map(String.init) ?? ""
        return ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Cargo.lock", "Podfile.lock"].contains(name)
            || name.hasSuffix(".pyc") || name.hasSuffix(".sqlite-wal") || name.hasSuffix(".sqlite-shm")
    }
    private func literal(_ text: String) -> String { text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") }
    private static func terms(_ text: String, singles: Bool) -> Set<String> {
        let scalars = Array(text.unicodeScalars)
        var result: Set<String> = []
        for i in scalars.indices {
            let code = String(scalars[i].value, radix: 16)
            if singles || scalars.count == 1 { result.insert("u" + code) }
            if i + 1 < scalars.count { result.insert("b" + code + "x" + String(scalars[i+1].value, radix: 16)) }
        }
        return result
    }
    private static func grams(_ text: String) -> String { terms(text, singles: true).joined(separator: " ") }
    public var searchIndexReady: Bool {
        guard let stmt = try? statement("SELECT value FROM index_meta WHERE key='search_version'") else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW && String(cString: sqlite3_column_text(stmt, 0)) == "1"
    }
    @discardableResult
    public func prepareSearchIndex(cancelled: () -> Bool = { false }, progress: (Int) -> Void = { _ in }) throws -> Bool {
        if searchIndexReady { return true }
        try execute("INSERT INTO file_search(file_search) VALUES('delete-all')")
        let rows = try statement("SELECT rowid,folded,fullfold FROM files")
        let insert = try statement("INSERT INTO file_search(rowid,namegrams,pathgrams) VALUES(?,?,?)")
        defer { sqlite3_finalize(rows); sqlite3_finalize(insert) }
        var count = 0, transaction = false
        do {
            while true {
                let rc = sqlite3_step(rows)
                if rc == SQLITE_DONE { break }; guard rc == SQLITE_ROW else { throw error() }
                if cancelled() { if transaction { try execute("ROLLBACK") }; return false }
                if !transaction { try execute("BEGIN IMMEDIATE"); transaction = true }
                sqlite3_reset(insert); sqlite3_clear_bindings(insert)
                sqlite3_bind_int64(insert, 1, sqlite3_column_int64(rows, 0))
                let name = Self.grams(String(cString: sqlite3_column_text(rows, 1)))
                let path = Self.grams(String(cString: sqlite3_column_text(rows, 2)))
                sqlite3_bind_text(insert, 2, name, -1, transient); sqlite3_bind_text(insert, 3, path, -1, transient)
                guard sqlite3_step(insert) == SQLITE_DONE else { throw error() }
                count += 1
                if count % 1000 == 0 { try execute("COMMIT"); transaction = false; progress(count) }
            }
            if transaction { try execute("COMMIT"); transaction = false }
            try execute("INSERT OR REPLACE INTO index_meta VALUES('search_version','1')")
            progress(count)
            return true
        } catch { if transaction { try? execute("ROLLBACK") }; throw error }
    }
    public func upsert(_ files: [FileRecord], generation: String) throws {
        try applyChanges(files, removing: [], generation: generation)
    }
    /// Commit a bounded event batch once, so FTS does not merge after every file.
    public func applyChanges(_ files: [FileRecord], removing paths: [String], generation: String) throws {
        guard !files.isEmpty || !paths.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for path in paths { try remove(path: path) }
            let stmt = try statement("""
            INSERT INTO files(path,parent,name,folded,fullfold,kind,size,modified,generation,noise) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET
            parent=excluded.parent,name=excluded.name,folded=excluded.folded,fullfold=excluded.fullfold,
            kind=excluded.kind,size=excluded.size,modified=excluded.modified,generation=excluded.generation,noise=excluded.noise
            """)
            defer { sqlite3_finalize(stmt) }
            for file in files {
                sqlite3_reset(stmt); sqlite3_clear_bindings(stmt)
                bind([file.path, file.url.deletingLastPathComponent().path, file.name, Self.fold(file.name), Self.fold(file.path), file.kind.rawValue, String(file.size), String(file.modified), generation, file.isHidden || Self.isSystemOrGenerated(file.path) ? "1" : "0"], to: stmt)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func removeStale(root: String, generation: String, preserve: [String] = []) throws {
        var sql = "DELETE FROM files WHERE path LIKE ? ESCAPE '\\' AND generation != ?"
        var args = [literal(root == "/" ? "" : root) + "/%", generation]
        for path in preserve { sql += " AND NOT (path = ? OR path LIKE ? ESCAPE '\\')"; args += [path, literal(path) + "/%"] }
        let stmt = try statement(sql); defer { sqlite3_finalize(stmt) }; bind(args, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
    public func remove(path: String) throws {
        // Binary path bounds use the primary-key index. LIKE defaults to NOCASE,
        // so it otherwise scans the whole table for every deleted/renamed file.
        let lower = path == "/" ? "/" : path + "/"
        let upper = path == "/" ? "0" : path + "0"
        let stmt = try statement("DELETE FROM files WHERE path = ? OR (path >= ? AND path < ?)")
        defer { sqlite3_finalize(stmt) }; bind([path, lower, upper], to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
    public func count() throws -> Int {
        let stmt = try statement("SELECT count(*) FROM files"); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw error() }; return Int(sqlite3_column_int64(stmt, 0))
    }
    public func search(_ query: String, scope: String? = nil, recursive: Bool = true, includePath: Bool = false, kind: FileKind? = nil, newest: Bool = false, limit: Int = 2000, accelerated: Bool = true, includeSystemFiles: Bool = true) throws -> SearchResult {
        let start = Date()
        var clauses = ["1=1"], args: [String] = []
        if !includeSystemFiles { clauses.append("noise = 0") }
        if accelerated && searchIndexReady {
            let tokens = Self.fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let terms = Set(tokens.flatMap { Self.terms($0, singles: false) }).sorted().prefix(48)
            if !terms.isEmpty {
                clauses.append("rowid IN (SELECT rowid FROM file_search WHERE file_search MATCH ?)")
                args.append("\(includePath ? "pathgrams" : "namegrams") : (" + terms.joined(separator: " AND ") + ")")
            }
        }
        for token in Self.fold(query).split(whereSeparator: { $0.isWhitespace }) {
            clauses.append("\(includePath ? "fullfold" : "folded") LIKE ? ESCAPE '\\'")
            args.append("%" + literal(String(token)) + "%")
        }
        if let scope {
            if recursive {
                let prefix = scope == "/" ? "" : scope
                clauses.append("path >= ? AND path < ?"); args += [prefix + "/", prefix + "0"]
            } else { clauses.append("parent = ?"); args.append(scope) }
        }
        let base = clauses.joined(separator: " AND ")
        let countsStmt = try statement("SELECT kind,count(*) FROM files WHERE \(base) GROUP BY kind")
        bind(args, to: countsStmt)
        var counts: [FileKind: Int] = [:]
        while true {
            let rc = sqlite3_step(countsStmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { sqlite3_finalize(countsStmt); throw error() }
            if let k = FileKind(rawValue: String(cString: sqlite3_column_text(countsStmt, 0))) { counts[k] = Int(sqlite3_column_int64(countsStmt, 1)) }
        }
        sqlite3_finalize(countsStmt)
        if let kind { clauses.append("kind = ?"); args.append(kind.rawValue) }
        let order = newest ? "modified DESC,path" : "folded,path"
        let stmt = try statement("SELECT path,name,kind,size,modified FROM files WHERE \(clauses.joined(separator: " AND ")) ORDER BY \(order) LIMIT \(max(1, limit))")
        defer { sqlite3_finalize(stmt) }; bind(args, to: stmt)
        var files: [FileRecord] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }; guard rc == SQLITE_ROW else { throw error() }
            files.append(FileRecord(path: String(cString: sqlite3_column_text(stmt, 0)), name: String(cString: sqlite3_column_text(stmt, 1)), kind: FileKind(rawValue: String(cString: sqlite3_column_text(stmt, 2))) ?? .other, size: sqlite3_column_int64(stmt, 3), modified: sqlite3_column_double(stmt, 4)))
        }
        return SearchResult(files: files, counts: counts, total: kind.map { counts[$0, default: 0] } ?? counts.values.reduce(0,+), milliseconds: Date().timeIntervalSince(start) * 1000)
    }
}
