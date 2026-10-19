import Foundation
import SearchCore
import CSQLite

private func XCTAssertEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    do { let value = try actual(); precondition(value == expected, "Expected \(expected), got \(value)", file: file, line: line) }
    catch { fatalError("Check failed: \(error)", file: file, line: line) }
}
private func XCTAssertTrue(_ value: Bool) { precondition(value) }

final class IndexTests {
    func testCancelledSearchReleasesConnection() throws {
        let db = try store()
        try db.upsert((0..<12000).map { FileRecord(path: "/work/item-\($0).txt", name: "item-\($0).txt", kind: .document) }, generation: "1")
        var checks = 0
        do {
            _ = try db.search("item", accelerated: false, cancelled: { checks += 1; return checks > 2 })
            fatalError("Expected an in-flight query to be cancelled")
        } catch IndexError.cancelled { }
        XCTAssertTrue(checks > 2)
        XCTAssertEqual(try db.search("item", accelerated: false).total, 12000)
        XCTAssertEqual(try db.search("item-42.txt", accelerated: false).files.first?.name, "item-42.txt")
        try db.upsert([
            FileRecord(path: "/work/report.draft.pdf", name: "report.draft.pdf", kind: .document),
            FileRecord(path: "/work/report.pdf", name: "report.pdf", kind: .document),
            FileRecord(path: "/work/project final.txt", name: "project final.txt", kind: .document),
            FileRecord(path: "/work/final project/z.txt", name: "z.txt", kind: .document)
        ], generation: "2")
        XCTAssertEqual(try db.search("report", relevance: true).files.first?.name, "report.pdf")
        XCTAssertEqual(try db.search("final project", includePath: true, relevance: true).files.first?.name, "project final.txt")
        XCTAssertEqual(try db.search("", limit: 200).files.count, 200)
        XCTAssertEqual(try db.search("", limit: 400).files.count, 400)
        XCTAssertEqual(try db.search("", limit: 400).total, 12004)
    }
    func testCountCacheTracksBothConnections() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let reader = try IndexStore(path: path)
        let writer = try IndexStore(path: path)
        let document = FileRecord(path: "/work/a.pdf", name: "a.pdf", kind: .document)
        try writer.upsert([document], generation: "1")
        XCTAssertEqual(try reader.search("", kind: .document).total, 1)
        XCTAssertEqual(try reader.search("", kind: .image, newest: true).counts[.document], 1)
        try writer.upsert([FileRecord(path: "/work/b.png", name: "b.png", kind: .image)], generation: "2")
        XCTAssertEqual(try reader.search("", kind: .image).total, 1)
        XCTAssertEqual(try reader.search("").total, 2)
        try reader.remove(path: document.path)
        XCTAssertEqual(try reader.search("", kind: .document).total, 0)
        XCTAssertEqual(try reader.search("").total, 1)
        try writer.remove(path: "/work/b.png")
        XCTAssertEqual(try reader.search("").total, 0)
    }
    func testRelevanceBeforeLimitAndLiteralInput() throws {
        let db = try store()
        let names = ["00-notes-报告.txt", "报告草稿.txt", "报告.pdf", "报告", "报告补充.txt", "100%.txt", "1000.txt", "Café.pdf", "CAFE备忘.txt"]
        try db.upsert(names.enumerated().map { offset, name in
            FileRecord(path: "/work/" + name, name: name, kind: .document, modified: Double(offset))
        } + [FileRecord(path: "/work/报告目录/aaa.txt", name: "aaa.txt", kind: .document)], generation: "1")
        for accelerated in [false, true] {
            if accelerated { try db.prepareSearchIndex() }
            let result = try db.search("报告", limit: 3, accelerated: accelerated, relevance: true)
            XCTAssertEqual(result.files.map(\.name), ["报告", "报告.pdf", "报告草稿.txt"])
            XCTAssertEqual(result.total, 5)
            XCTAssertEqual(try db.search("100%", relevance: true).files.map(\.name), ["100%.txt"])
            XCTAssertEqual(try db.search("cafe", relevance: true).files.first?.name, "Café.pdf")
            XCTAssertEqual(try db.search("报告", includePath: true, relevance: true).files.last?.name, "aaa.txt")
            XCTAssertEqual(try db.search("报告", newest: true).files.first?.name, "报告补充.txt")
            XCTAssertEqual(try db.search("' OR 1=1", relevance: true).total, 0)
        }
    }
    func testVisibilityMigrationPreservesExistingIndex() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        var legacy: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &legacy), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(legacy, "CREATE TABLE files(path TEXT PRIMARY KEY,parent TEXT NOT NULL,name TEXT NOT NULL,folded TEXT NOT NULL,fullfold TEXT NOT NULL,kind TEXT NOT NULL,size INTEGER NOT NULL,modified REAL NOT NULL,generation TEXT NOT NULL); INSERT INTO files VALUES('/Users/me/.cache/a.pdf','/Users/me/.cache','a.pdf','a.pdf','/users/me/.cache/a.pdf','document',0,0,'old'),('/Users/me/Documents/a.pdf','/Users/me/Documents','a.pdf','a.pdf','/users/me/documents/a.pdf','document',0,0,'old');", nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacy)
        do {
            let db = try IndexStore(path: path)
            XCTAssertEqual(try db.count(), 2)
            XCTAssertEqual(try db.search("a", includeSystemFiles: false).total, 1)
            try db.prepareSearchIndex()
        }
        let reopened = try IndexStore(path: path)
        XCTAssertTrue(reopened.searchIndexReady)
        XCTAssertEqual(try reopened.search("a", includeSystemFiles: false).total, 1)
        XCTAssertEqual(try reopened.search("a").total, 2)
    }
    func testPersonalFileFilter() throws {
        let db = try store()
        let visible = ["/Users/me/Documents/报告.pdf", "/Volumes/Work/项目/main.swift", "/Users/me/Documents/资料.db", "/Users/me/Documents/调试.log", "/Users/me/Downloads/安装包.dmg", "/Users/me/Documents/Library-notes/报告.pdf"]
        let hidden = ["/Users/me/.cache/报告.pdf", "/Users/me/Library/报告.pdf", "/Applications/Demo.app/报告.pdf", "/usr/share/报告.pdf", "/Volumes/Work/项目/node_modules/报告.pdf", "/Users/me/Documents/package-lock.json", "/Users/me/Documents/.索引", "/Users/me/Documents/flag-hidden.txt"]
        try db.upsert((visible + hidden).map { FileRecord(path: $0, name: URL(fileURLWithPath: $0).lastPathComponent, kind: $0.hasSuffix(".pdf") ? .document : .other, isHidden: $0.hasSuffix("flag-hidden.txt")) }, generation: "1")
        for accelerated in [false, true] {
            if accelerated { try db.prepareSearchIndex() }
            let all = try db.search("", includeSystemFiles: false)
            XCTAssertEqual(Set(all.files.map(\.path)), Set(visible))
            XCTAssertEqual(all.total, visible.count)
            XCTAssertEqual(try db.search("", limit: 1, includeSystemFiles: false).total, visible.count)
            XCTAssertEqual(try db.search("报告", kind: .document, includeSystemFiles: false).total, 2)
            XCTAssertEqual(try db.search("", scope: "/Users/me/.cache", includeSystemFiles: false).total, 0)
            XCTAssertEqual(try db.search("", scope: "/Users/me/.cache", includeSystemFiles: true).total, 1)
            XCTAssertEqual(try db.search("").total, visible.count + hidden.count)
        }
        try db.upsert([FileRecord(path: hidden.last!, name: "flag-hidden.txt", kind: .other)], generation: "2")
        XCTAssertEqual(try db.search("flag-hidden", includeSystemFiles: false).total, 1)
    }
    func store() throws -> IndexStore { try IndexStore(path: ":memory:") }
    func testUnicodeTokensAndLiteralWildcards() throws {
        let db = try store()
        try db.upsert([
            FileRecord(path: "/work/品牌方案.PDF", name: "品牌方案.PDF", kind: .document),
            FileRecord(path: "/work/Café_100%.txt", name: "Café_100%.txt", kind: .document),
            FileRecord(path: "/work/other.png", name: "other.png", kind: .image)
        ], generation: "1")
        XCTAssertEqual(try db.search("品牌 pdf").total, 1)
        XCTAssertEqual(try db.search("CAFE").total, 1)
        XCTAssertEqual(try db.search("100%").total, 1)
        XCTAssertEqual(try db.search("_").total, 1)
        XCTAssertEqual(try db.search("' OR 1=1").total, 0)
    }
    func testScopeDoesNotMatchSiblingAndCanSkipDescendants() throws {
        let db = try store()
        try db.upsert([
            FileRecord(path: "/a/file.pdf", name: "file.pdf", kind: .document),
            FileRecord(path: "/a/sub/file.png", name: "file.png", kind: .image),
            FileRecord(path: "/ab/file.pdf", name: "file.pdf", kind: .document),
            FileRecord(path: "/a_1/file.txt", name: "file.txt", kind: .document),
            FileRecord(path: "/ax1/file.txt", name: "file.txt", kind: .document)
        ], generation: "1")
        XCTAssertEqual(try db.search("file", scope: "/a").total, 2)
        XCTAssertEqual(try db.search("file", scope: "/a", recursive: false).total, 1)
        XCTAssertEqual(try db.search("file", scope: "/a_1").total, 1)
        XCTAssertEqual(try db.search("/a/", includePath: true).total, 2)
        XCTAssertEqual(try db.search("/a/").total, 0)
    }
    func testCountsAreUncappedAndTypeFilterPreservesOtherCounts() throws {
        let db = try store()
        try db.upsert((0..<120).map { FileRecord(path: "/x/f\($0).pdf", name: "f\($0).pdf", kind: .document) } + [FileRecord(path: "/x/z.png", name: "z.png", kind: .image)], generation: "1")
        let result = try db.search("", kind: .image, limit: 10)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.counts[.document], 120)
        XCTAssertEqual(try db.search("", limit: 10).files.count, 10)
        XCTAssertEqual(try db.search("", limit: 10).total, 121)
    }
    func testReindexRemovesDeletedFilesAndKeepsUnreadableSubtree() throws {
        let db = try store()
        try db.upsert([
            FileRecord(path: "/a", name: "a", kind: .folder),
            FileRecord(path: "/a/deleted", name: "deleted", kind: .other),
            FileRecord(path: "/a/denied/file", name: "file", kind: .other),
            FileRecord(path: "/ab/keep", name: "keep", kind: .other)
        ], generation: "old")
        try db.removeStale(root: "/a", generation: "new", preserve: ["/a/denied"])
        XCTAssertEqual(try db.search("deleted").total, 0)
        XCTAssertEqual(try db.search("file").total, 1)
        XCTAssertEqual(try db.search("keep").total, 1)
        XCTAssertEqual(try db.count(), 3)
        try db.remove(path: "/a")
        XCTAssertEqual(try db.count(), 1)
    }
    func testRealScannerCreateRenameDeleteAndCancel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try store(), scanner = Scanner()
        let original = root.appendingPathComponent("品牌方案.txt"), renamed = root.appendingPathComponent("品牌定稿.txt")
        try Data("hello".utf8).write(to: original)
        _ = try scanner.scan(root: root, store: db)
        XCTAssertEqual(try db.search("品牌方案").total, 1)
        try FileManager.default.moveItem(at: original, to: renamed)
        _ = try scanner.scan(root: root, store: db)
        XCTAssertEqual(try db.search("品牌方案").total, 0)
        XCTAssertEqual(try db.search("品牌定稿").total, 1)
        let cancelled = try scanner.scan(root: root, store: db, cancelled: { true })
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertEqual(try db.count(), 1)
        try FileManager.default.removeItem(at: renamed)
        _ = try scanner.scan(root: root, store: db)
        XCTAssertEqual(try db.count(), 0)
    }
    func testHundredThousandFileSearchBenchmark() throws {
        let db = try store()
        let records = (0..<100_000).map { FileRecord(path: "/bench/项目\($0 % 80)/品牌方案-\($0).pdf", name: "品牌方案-\($0).pdf", kind: .document, modified: Double($0)) }
        try db.upsert(records, generation: "bench")
        let baseline = try db.search("方案 9876", accelerated: false)
        let buildStart = Date(); try db.prepareSearchIndex()
        let buildTime = Date().timeIntervalSince(buildStart)
        var fast: [Double] = [], slow: [Double] = []
        for _ in 0..<7 {
            let result = try db.search("方案 9876")
            XCTAssertEqual(result.total, 20); XCTAssertEqual(result.files, baseline.files)
            fast.append(result.milliseconds)
            slow.append(try db.search("方案 9876", accelerated: false).milliseconds)
        }
        print("BENCHMARK 100000 records, FTS build \(String(format: "%.1f", buildTime)) s, median LIKE \(String(format: "%.2f", slow.sorted()[3])) ms -> indexed \(String(format: "%.2f", fast.sorted()[3])) ms")
    }
    func testAcceleratedSubstringEquivalenceAndUpdates() throws {
        let db = try store()
        let names = ["品牌方案.PDF","品牌宣传.png","品牌_100%.txt","ab-bc.txt","abc.txt","Café.md","计划🎉终稿.txt","日本語案内.pdf","file[1].txt","a\\b.txt","编号１２３.txt"]
        try db.upsert(names.enumerated().map { FileRecord(path: "/项目/a_1/\($0.offset)/" + $0.element, name: $0.element, kind: .document) }, generation: "old")
        try db.prepareSearchIndex()
        XCTAssertTrue(db.searchIndexReady)
        for query in ["品","品牌","方案","品牌 pdf","%","_","abc","ab bc","CAFE","🎉","🎉终","日本","[1]","\\","123","not found","\" OR '", "项目"] {
            for pathMatch in [false,true] {
                let fast = try db.search(query, includePath: pathMatch)
                let slow = try db.search(query, includePath: pathMatch, accelerated: false)
                XCTAssertEqual(fast.files, slow.files); XCTAssertEqual(fast.counts, slow.counts)
            }
        }
        try db.upsert([FileRecord(path: "/项目/a_1/0/品牌方案.PDF", name: "全新名字.pdf", kind: .image)], generation: "new")
        XCTAssertEqual(try db.search("品牌方案").total, 0)
        XCTAssertEqual(try db.search("全新").total, 1)
        try db.remove(path: "/项目/a_1/0")
        XCTAssertEqual(try db.search("全新").total, 0)
        try db.removeStale(root: "/项目", generation: "new")
        XCTAssertEqual(try db.search("品").total, 0)
        try db.upsert([FileRecord(path: "/brand.txt", name: "品牌.txt", kind: .document)], generation: "1")
        for _ in 0..<4 { try db.upsert([FileRecord(path: "/brand.txt", name: "品牌.txt", kind: .document, modified: Date().timeIntervalSince1970)], generation: "2") }
        XCTAssertEqual(try db.search("品牌").total, 1)
    }
    func testInterruptedMigrationRestartsWithoutLostRows() throws {
        let db = try store()
        try db.upsert((0..<1500).map { FileRecord(path: "/\($0).txt", name: "中文\($0).txt", kind: .document) }, generation: "1")
        var progress = 0
        let ready = try db.prepareSearchIndex(cancelled: { progress >= 1000 }, progress: { progress = $0 })
        XCTAssertTrue(!ready && !db.searchIndexReady)
        XCTAssertEqual(try db.search("中文").total, 1500)
        try db.prepareSearchIndex()
        XCTAssertEqual(try db.search("中文").total, 1500)
    }
    func testDeletionUsesExactCaseAndFolderBoundary() throws {
        let db = try store(); try db.prepareSearchIndex()
        let paths = ["/work/A_1", "/work/A_1/中文.txt", "/work/A_1/sub/a.txt", "/work/a_1/keep.txt", "/work/A_10/keep.txt", "/work/A_1-other.txt", "/work/A%/child.txt", "/work/AB/keep.txt"]
        try db.upsert(paths.map { FileRecord(path: $0, name: URL(fileURLWithPath: $0).lastPathComponent, kind: .document) }, generation: "before")
        try db.remove(path: "/work/A_1")
        XCTAssertEqual(Set(try db.search("").files.map(\.path)), Set(paths.dropFirst(3)))
        try db.remove(path: "/work/A%")
        XCTAssertEqual(try db.count(), 4)
        try db.remove(path: "/")
        XCTAssertEqual(try db.count(), 0)
        XCTAssertEqual(try db.search("keep").total, 0)
    }
    func testBatchedEventWritesAndRollback() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let db = try IndexStore(path: path)
        try db.prepareSearchIndex()
        try db.upsert([FileRecord(path: "/work/old.txt", name: "旧文件.txt", kind: .document)], generation: "before")
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER reject_test BEFORE INSERT ON files WHEN new.name='reject' BEGIN SELECT RAISE(ABORT,'test failure'); END;", nil, nil, nil), SQLITE_OK)
        do {
            try db.applyChanges([FileRecord(path: "/work/new.txt", name: "reject", kind: .document)], removing: ["/work/old.txt"], generation: "event")
            fatalError("Expected database rejection")
        } catch { }
        XCTAssertEqual(try db.search("旧文件").total, 1)
        XCTAssertEqual(try db.count(), 1)
        let added = (0..<1000).map { FileRecord(path: "/work/new\($0).txt", name: "新增方案\($0).txt", kind: .document) }
        try db.applyChanges(added, removing: ["/work/old.txt"], generation: "event")
        XCTAssertEqual(try db.count(), 1000)
        XCTAssertEqual(try db.search("旧文件").total, 0)
        XCTAssertEqual(try db.search("新增方案").total, 1000)
        XCTAssertEqual(try db.search("新增方案").files, try db.search("新增方案", accelerated: false).files)
    }
    func testEmptyResultFeedbackUsesCurrentCoverage() {
        var root = RootCoverage(path: "/work"); root.state = .ready
        root.excluded = ["/work/node_modules"]; root.denied = ["/work/private"]
        func resolve(_ scope: String?, _ coverage: [RootCoverage], searching: Bool = false, failed: Bool = false, indexing: Bool = false, filtered: Bool = false) -> SearchFeedback {
            SearchFeedback.resolve(searching: searching, failed: failed, indexing: indexing, scope: scope, coverage: coverage, filtered: filtered)
        }
        XCTAssertEqual(resolve("/work/node_modules/a", [root]), .excluded)
        XCTAssertEqual(resolve("/work/private", [root]), .denied)
        XCTAssertEqual(resolve("/work/private-notes", [root]), .noMatch)
        XCTAssertEqual(resolve("/work/docs", [root]), .noMatch)
        XCTAssertEqual(resolve(nil, [root]), .noMatch)
        XCTAssertEqual(resolve(nil, [root], searching: true), .searching)
        XCTAssertEqual(resolve(nil, [root], failed: true), .failed)
        XCTAssertEqual(resolve(nil, [root], indexing: true), .indexing)
        XCTAssertEqual(resolve(nil, [root], filtered: true), .filtered)
        var supplemental = RootCoverage(path: "/work/node_modules"); supplemental.state = .ready
        XCTAssertEqual(resolve("/work/node_modules/a", [root, supplemental]), .noMatch)
        supplemental.state = .offline
        XCTAssertEqual(resolve("/work/node_modules/a", [root, supplemental]), .offline)
        XCTAssertEqual(resolve(nil, [root, supplemental]), .noMatch)
        XCTAssertEqual(resolve(nil, [supplemental]), .offline)
        root.state = .interrupted
        XCTAssertEqual(resolve("/work/docs", [root]), .incomplete)
    }
    func testCatalogStartupPolicyAndPersistence() throws {
        var catalog = IndexCatalog()
        XCTAssertTrue(catalog.needsBaseline("/x", identity: "volume:1"))
        var root = RootCoverage(path: "/x"); root.state = .ready; root.identity = "volume:1"; root.scanned = 20
        catalog.roots["/x"] = root; catalog.checkpoint = 42
        XCTAssertTrue(!catalog.needsBaseline("/x", identity: "volume:1"))
        XCTAssertTrue(catalog.needsBaseline("/x", identity: "volume:2"))
        XCTAssertTrue(!catalog.needsBaseline("/x", identity: nil))
        catalog.roots["/x"]?.state = .partial
        XCTAssertTrue(!catalog.needsBaseline("/x", identity: "volume:1"))
        catalog.roots["/x"]?.state = .interrupted
        XCTAssertTrue(catalog.needsBaseline("/x", identity: "volume:1"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try catalog.save(url)
        let loaded = try IndexCatalog.load(url)
        XCTAssertEqual(loaded.checkpoint, 42); XCTAssertEqual(loaded.roots["/x"]?.state, .interrupted)
        catalog.record("/x", report: ScanReport(scanned: 0, denied: [], cancelled: false, unavailable: true))
        XCTAssertEqual(catalog.roots["/x"]?.scanned, 20)
        XCTAssertEqual(catalog.roots["/x"]?.state, .offline)
    }
    func testScannerReportsExcludedAndOffline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules/dep"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try store(); try db.prepareSearchIndex()
        let report = try Scanner().scan(root: root, store: db)
        XCTAssertTrue(report.excluded.contains(canonicalPath(root.path) + "/node_modules"))
        let offline = try Scanner().scan(root: root.appendingPathComponent("missing"), store: db)
        XCTAssertTrue(offline.unavailable)
        XCTAssertTrue(offline.denied.isEmpty)
        let blocked = root.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
        let restricted = try Scanner().scan(root: blocked, store: db)
        XCTAssertTrue(!restricted.unavailable)
        XCTAssertEqual(restricted.denied, [canonicalPath(blocked.path)])
    }
}

@main
struct SearchChecks {
    static func main() throws {
        let tests = IndexTests()
        try tests.testCancelledSearchReleasesConnection()
        try tests.testCountCacheTracksBothConnections()
        try tests.testRelevanceBeforeLimitAndLiteralInput()
        try tests.testDeletionUsesExactCaseAndFolderBoundary()
        try tests.testBatchedEventWritesAndRollback()
        tests.testEmptyResultFeedbackUsesCurrentCoverage()
        try tests.testPersonalFileFilter()
        try tests.testVisibilityMigrationPreservesExistingIndex()
        try tests.testUnicodeTokensAndLiteralWildcards()
        try tests.testScopeDoesNotMatchSiblingAndCanSkipDescendants()
        try tests.testCountsAreUncappedAndTypeFilterPreservesOtherCounts()
        try tests.testReindexRemovesDeletedFilesAndKeepsUnreadableSubtree()
        try tests.testRealScannerCreateRenameDeleteAndCancel()
        try tests.testAcceleratedSubstringEquivalenceAndUpdates()
        try tests.testInterruptedMigrationRestartsWithoutLostRows()
        try tests.testCatalogStartupPolicyAndPersistence()
        try tests.testScannerReportsExcludedAndOffline()
        try tests.testHundredThousandFileSearchBenchmark()
        print("PASS: 18 checks — in-flight cancellation/reuse, paged limits, multiword/path ranking, count cache invalidation, relevance before limit, Unicode/literal ranking, coverage-aware feedback, personal file filtering, migration, restart policy, 100k benchmark")
    }
}
