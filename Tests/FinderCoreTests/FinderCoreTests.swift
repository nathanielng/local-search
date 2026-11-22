import Testing
import Foundation
@testable import FinderCore

private func tempStore() throws -> FinderStore {
    let p = NSTemporaryDirectory() + "af-\(UUID().uuidString).sqlite"
    return try FinderStore(path: p)
}

@Suite struct TabStateTests {
    @Test func backForwardStacks() {
        var t = TabState(path: "/a")
        t.commit(to: "/b", source: .click)
        t.commit(to: "/c", source: .click)
        #expect(t.back == ["/a", "/b"])
        t.commit(to: "/b", source: .back)
        #expect(t.forward == ["/c"] && t.back == ["/a"])
        t.commit(to: "/c", source: .forward)
        #expect(t.forward.isEmpty && t.back == ["/a", "/b"])
        t.commit(to: "/b", source: .back)
        t.commit(to: "/x", source: .typed)
        #expect(t.forward.isEmpty)
    }
    @Test func sameFolderIsNoOp() {
        var t = TabState(path: "/a")
        t.commit(to: "/a", source: .click)
        #expect(t.back.isEmpty)
    }
    @Test func restoreLeavesStacks() {
        var t = TabState(path: "/a/b", back: ["/z"])
        t.commit(to: "/a", source: .restore)
        #expect(t.back == ["/z"] && t.path == "/a")
    }
    @Test func duplicateGetsNewIDKeepsStacks() {
        let t = TabState(path: "/a", back: ["/x"])
        let d = t.duplicated()
        #expect(d.id != t.id && d.back == ["/x"])
    }
    @Test func nearestParent() {
        #expect(nearestExistingFolder("/tmp/definitely/not/here") == "/tmp")
    }
}

@Suite struct StoreTests {
    @Test func tabsRoundTrip() throws {
        let s = try tempStore()
        let a = TabState(path: "/a", back: ["/x", "/y"], forward: ["/f"], sortKey: "size", sortAscending: false, selection: ["n"])
        let b = TabState(path: "/b")
        try s.saveTabs([a, b], selected: b.id)
        let r = try s.loadOpenTabs()
        #expect(r.tabs == [a, b] && r.selected == b.id)
    }
    @Test func closeAndReopenKeepsStacksAndHistory() throws {
        let s = try tempStore()
        let a = TabState(path: "/a", back: ["/x"])
        try s.saveTabs([a], selected: a.id)
        try s.logVisit(tabID: a.id, path: "/a", source: .click)
        try s.closeTab(a.id, state: a)
        #expect(try s.loadOpenTabs().tabs.isEmpty)
        let closed = try s.closedTabs()
        #expect(closed.first == a)
        #expect(try s.navigationHistory().count == 1)
    }
    @Test func foldersVisitedCapsGap() throws {
        let s = try tempStore()
        let id = UUID()
        try s.logVisit(tabID: id, path: "/a", source: .click)
        try s.logVisit(tabID: id, path: "/b", source: .click)
        let r = try s.foldersVisited()
        #expect(r.count == 2)
        #expect(r.allSatisfy { $0.estimatedSeconds <= 1800 })
    }
    @Test func favoritesLimit() throws {
        let s = try tempStore()
        for i in 0..<40 { try s.addFavorite(path: "/f\(i)") }
        #expect(try s.favorites().count == FinderStore.sidebarLimit)
    }
    @Test func insertFavoriteAfter() throws {
        let s = try tempStore()
        try s.insertFavorite(path: "/new", after: "\(AppPaths.home)/Documents")
        let paths = try s.favorites().map(\.path)
        #expect(paths.firstIndex(of: "/new") == (paths.firstIndex(of: "\(AppPaths.home)/Documents") ?? -2) + 1)
        try s.insertFavorite(path: "/first", after: nil, before: try s.favorites()[0].path)
        #expect(try s.favorites().first?.path == "/first")
        try s.insertFavorite(path: "/end", after: nil)
        #expect(try s.favorites().last?.path == "/end")
        try s.insertFavorite(path: "/new", after: nil) // existing stays put
        #expect(try s.favorites().filter { $0.path == "/new" }.count == 1)
    }
    @Test func reorderFavoritesAndSpecialFolders() throws {
        let s = try tempStore()
        let h = AppPaths.home
        let start = try s.favorites().map(\.path)
        #expect(start == ["\(h)/Desktop", "\(h)/Documents", "\(h)/Downloads", "/Applications"])
        try s.moveFavorite("/Applications", relativeTo: "\(h)/Desktop", after: false)
        #expect(try s.favorites().map(\.path).first == "/Applications")
        try s.moveFavorite("/Applications", relativeTo: "\(h)/Downloads", after: true)
        #expect(try s.favorites().map(\.path) == ["\(h)/Desktop", "\(h)/Documents", "\(h)/Downloads", "/Applications"])
        try s.moveFavorite("\(h)/Desktop", relativeTo: "\(h)/Documents", after: true)
        #expect(try s.favorites().map(\.path).prefix(2) == ["\(h)/Documents", "\(h)/Desktop"])
        #expect(try s.moveFavorite("/nope", relativeTo: "/Applications", after: true) == false)
        #expect(try s.moveFavorite("/Applications", relativeTo: "/Applications", after: true) == false)
        try s.addSpecialFolder(path: "/tmp/one", title: "One")
        try s.addSpecialFolder(path: "/tmp/two", title: "Two")
        try s.moveSpecialFolder("/tmp/two", relativeTo: "/tmp/one", after: false)
        #expect(try s.specialFolders().map(\.title) == ["Two", "One"])
    }
    @Test func specialFoldersComeFromSettingsNotCode() throws {
        // a fresh database has none of its own
        #expect(try tempStore().specialFolders().isEmpty)
        // they are seeded once from settings.json (with ~ expansion), only when the database is created
        let dir = try tempDir()
        let settings = URL(fileURLWithPath: dir + "/settings.json")
        try Data(#"{"special_folders":[{"title":"Notes","path":"~/example-notes"},{"title":"Media","path":"/tmp/example-media"}]}"#.utf8).write(to: settings)
        let dbPath = dir + "/db.sqlite"
        let s = try FinderStore(path: dbPath, settingsURL: settings)
        #expect(try s.specialFolders().map(\.title) == ["Notes", "Media"])
        #expect(try s.specialFolders()[0].path == AppPaths.home + "/example-notes")
        try s.removeSpecialFolder(path: "/tmp/example-media")
        let again = try FinderStore(path: dbPath, settingsURL: settings) // reopening doesn't re-seed
        #expect(try again.specialFolders().map(\.title) == ["Notes"])
    }
    @Test func schemaVersion() throws {
        let s = try tempStore()
        #expect(try s.db.query("PRAGMA user_version").first?["user_version"]?.int == 6)
    }
}

private func tempDir() throws -> String {
    let d = NSTemporaryDirectory() + "af-dir-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}

@Suite struct FileOpsTests {
    @Test func keepBothNaming() throws {
        let d = try tempDir()
        FileManager.default.createFile(atPath: d + "/a.txt", contents: Data())
        #expect(FileOps.uniqueDestination(name: "a.txt", in: d) == d + "/a 2.txt")
        FileManager.default.createFile(atPath: d + "/a 2.txt", contents: Data())
        #expect(FileOps.uniqueDestination(name: "a.txt", in: d) == d + "/a 3.txt")
        #expect(FileOps.uniqueDestination(name: "new.txt", in: d) == d + "/new.txt")
    }
    @Test func moveNeverOverwritesAndLogs() throws {
        let s = try tempStore(), a = try tempDir(), b = try tempDir()
        try Data("one".utf8).write(to: URL(fileURLWithPath: a + "/f.txt"))
        try Data("two".utf8).write(to: URL(fileURLWithPath: b + "/f.txt"))
        let r = FileOps.perform(.move, sources: [a + "/f.txt"], into: b, store: s)
        #expect(r[0].result == "done" && r[0].dst == b + "/f 2.txt")
        #expect(try String(contentsOfFile: b + "/f.txt", encoding: .utf8) == "two")
        #expect(!FileManager.default.fileExists(atPath: a + "/f.txt"))
        let log = try s.history(.fileOp)
        #expect(log.count == 1 && log[0].detail == "done · app")
    }
    @Test func copyKeepsSource() throws {
        let a = try tempDir(), b = try tempDir()
        FileManager.default.createFile(atPath: a + "/f.txt", contents: Data())
        let r = FileOps.perform(.copy, sources: [a + "/f.txt"], into: b, store: nil)
        #expect(r[0].result == "done" && FileManager.default.fileExists(atPath: a + "/f.txt"))
    }
    @Test func refusesProtectedAndSelfMoves() throws {
        let a = try tempDir()
        #expect(FileOps.isProtected("/System") && FileOps.isProtected(AppPaths.home))
        #expect(FileOps.isProtected(AppPaths.home + "/Documents"))
        #expect(FileOps.perform(.move, sources: ["/Applications"], into: a, store: nil)[0].result == "skipped")
        try FileManager.default.createDirectory(atPath: a + "/sub", withIntermediateDirectories: true)
        #expect(FileOps.perform(.move, sources: [a], into: a + "/sub", store: nil)[0].result == "skipped")
        #expect(FileOps.perform(.move, sources: [a + "/sub"], into: "/usr/bin", store: nil)[0].result == "skipped")
    }
}

@Suite struct HistoryTests {
    @Test func timelineGroupsBatchesAndSearches() throws {
        let s = try tempStore(), a = try tempDir(), b = try tempDir()
        for n in ["x.txt", "y.txt", "z.txt"] { FileManager.default.createFile(atPath: a + "/" + n, contents: Data()) }
        FileOps.perform(.move, sources: ["x", "y", "z"].map { a + "/\($0).txt" }, into: b, store: s)
        try s.logVisit(tabID: UUID(), path: b, source: .click)
        let t = try s.timeline()
        #expect(t.count == 2 && t.contains { $0.title.hasPrefix("move 3 items") })
        #expect(try s.timeline(search: "click").count == 1)
        #expect(try s.history(.fileOp).count == 3)
    }
    @Test func deleteClearAndPurge() throws {
        let s = try tempStore(), id = UUID()
        try s.logVisit(tabID: id, path: "/a", source: .click)
        try s.logVisit(tabID: id, path: "/b", source: .click)
        try s.delete(try s.history(.folder)[0])
        #expect(try s.history(.folder).count == 1)
        try s.purgeHistory(olderThanDays: 1, now: Date().addingTimeInterval(3 * 86400))
        #expect(try s.history(.folder).isEmpty)
        try s.logVisit(tabID: id, path: "/c", source: .click)
        try s.clear(nil)
        #expect(try s.timeline().isEmpty)
    }
    @Test func csvHasUTCAndLocalAndEscapes() throws {
        let e = HistoryEntry(id: "1", kind: .folder, at: "2026-01-01T00:00:00.000Z", title: "a \"q\"", detail: "d", folder: "/a",
                             table: "t", column: "c", key: .null)
        let csv = FinderStore.csv([e])
        #expect(csv.contains("time_utc,time_local") && csv.contains("\"a \"\"q\"\"\"") && csv.contains("2026-01-01T00:00:00.000Z"))
    }
}

@Suite struct FileEditingTests {
    @Test func createNaming() throws {
        let d = try tempDir()
        #expect(FileOps.createTextFile(in: d, store: nil).dst == d + "/untitled.txt")
        #expect(FileOps.createTextFile(in: d, store: nil).dst == d + "/untitled 2.txt")
        #expect(FileOps.createFolder(in: d, store: nil).dst == d + "/untitled folder")
        #expect(FileOps.createFolder(in: d, store: nil).dst == d + "/untitled folder 2")
    }
    @Test func renameRules() throws {
        let s = try tempStore(), d = try tempDir()
        for n in ["a.txt", "b.txt"] { FileManager.default.createFile(atPath: d + "/" + n, contents: Data()) }
        #expect(FileOps.rename(d + "/a.txt", to: "b.txt", store: s).result == "failed") // never overwrites
        #expect(FileOps.rename(d + "/a.txt", to: "x/y", store: s).message == "invalid name")
        #expect(FileOps.rename(d + "/a.txt", to: "a.txt", store: s).result == "skipped")
        #expect(FileOps.rename(d + "/a.txt", to: "A.txt", store: s).result == "done") // case-only
        #expect(try FileManager.default.contentsOfDirectory(atPath: d).contains("A.txt"))
        #expect(FileOps.rename(AppPaths.home + "/Documents", to: "Docs", store: s).message == "protected location")
        #expect(try s.history(.fileOp).filter { $0.title.hasPrefix("rename") }.count == 2)
    }
    @Test func conflictChoices() throws {
        let a = try tempDir(), b = try tempDir()
        try Data("new".utf8).write(to: URL(fileURLWithPath: a + "/f.txt"))
        try Data("old".utf8).write(to: URL(fileURLWithPath: b + "/f.txt"))
        #expect(FileOps.conflicts(sources: [a + "/f.txt"], into: b) == ["f.txt"])
        #expect(FileOps.perform(.copy, sources: [a + "/f.txt"], into: b, store: nil, conflict: .skip)[0].result == "skipped")
        #expect(try String(contentsOfFile: b + "/f.txt", encoding: .utf8) == "old")
        let r = FileOps.perform(.copy, sources: [a + "/f.txt"], into: b, store: nil, conflict: .replace)
        #expect(r[0].dst == b + "/f.txt")
        #expect(try String(contentsOfFile: b + "/f.txt", encoding: .utf8) == "new")
        #expect(try FileManager.default.contentsOfDirectory(atPath: b) == ["f.txt"])
    }
    @Test func copyIntoSameFolderKeepsBoth() throws {
        let a = try tempDir()
        FileManager.default.createFile(atPath: a + "/f.txt", contents: Data())
        #expect(FileOps.conflicts(sources: [a + "/f.txt"], into: a).isEmpty)
        #expect(FileOps.perform(.copy, sources: [a + "/f.txt"], into: a, store: nil, conflict: .replace)[0].dst == a + "/f 2.txt")
    }
    @Test func cancelStopsRemainingItems() throws {
        let a = try tempDir(), b = try tempDir()
        for n in 1...3 { FileManager.default.createFile(atPath: a + "/\(n).txt", contents: Data()) }
        let t = CancelToken(); t.cancel()
        #expect(FileOps.perform(.copy, sources: (1...3).map { a + "/\($0).txt" }, into: b, store: nil, cancel: t).isEmpty)
    }
}

@Suite struct CopyTextTests {
    @Test func secretsAndBinariesSkipped() throws {
        let d = try tempDir()
        try Data("hello".utf8).write(to: URL(fileURLWithPath: d + "/a.txt"))
        try Data("world".utf8).write(to: URL(fileURLWithPath: d + "/b.md"))
        try Data(("AWS_KEY=" + "AKIA" + String(repeating: "X", count: 16)).utf8).write(to: URL(fileURLWithPath: d + "/c.txt"))
        try Data("TOKEN=1".utf8).write(to: URL(fileURLWithPath: d + "/.env"))
        try Data([0, 1, 2, 3]).write(to: URL(fileURLWithPath: d + "/d.bin"))
        let out = CopyText.build(paths: ["a.txt", "b.md", "c.txt", ".env", "d.bin"].map { d + "/" + $0 })
        #expect(out.included.count == 2)
        #expect(out.text == "===== \(d)/a.txt =====\nhello\n\n===== \(d)/b.md =====\nworld")
        #expect(Set(out.skipped.map(\.reason)) == ["likely secret", "binary"])
    }
    @Test func singleFileHasNoHeaderAndLimitsApply() throws {
        let d = try tempDir()
        try Data(repeating: 97, count: 300_000).write(to: URL(fileURLWithPath: d + "/big.txt"))
        let out = CopyText.build(paths: [d + "/big.txt"])
        #expect(out.text.hasPrefix("aaa") && out.text.hasSuffix("[truncated at 200 KB]"))
        #expect(SecretGuard.isSecretPath("/x/.ssh/config") && SecretGuard.isSecretPath("/x/server.pem"))
        #expect(!SecretGuard.isSecretPath("/x/readme.md") && !SecretGuard.isBinary(Data("héllo".utf8)))
    }
}

@Suite struct UndoTests {
    @Test func redoReappliesMoveCopyAndRename() throws {
        let a = try tempDir(), b = try tempDir()
        FileManager.default.createFile(atPath: a + "/f.txt", contents: Data("x".utf8))
        let fm = FileManager.default
        // move: undo then redo
        let mv = FileOps.perform(.move, sources: [a + "/f.txt"], into: b, store: nil)
        let u1 = FileOps.undoWithRedo(try #require(UndoRecord.forJob(.move, results: mv, conflict: .keepBoth)), store: nil)
        #expect(fm.fileExists(atPath: a + "/f.txt"))
        FileOps.undo(try #require(u1.redo), store: nil)
        #expect(fm.fileExists(atPath: b + "/f.txt") && !fm.fileExists(atPath: a + "/f.txt"))
        // copy: undo trashes the copy, redo restores it from the Trash
        FileManager.default.createFile(atPath: a + "/g-\(UUID().uuidString).txt", contents: Data("y".utf8))
        let g = a + "/" + (try fm.contentsOfDirectory(atPath: a)[0])
        let cp = FileOps.perform(.copy, sources: [g], into: b, store: nil)
        let u2 = FileOps.undoWithRedo(try #require(UndoRecord.forJob(.copy, results: cp, conflict: .keepBoth)), store: nil)
        #expect(!fm.fileExists(atPath: cp[0].dst!))
        FileOps.undo(try #require(u2.redo), store: nil)
        #expect(try String(contentsOfFile: cp[0].dst!, encoding: .utf8) == "y")
        // rename
        let r = FileOps.rename(b + "/f.txt", to: "h.txt", store: nil)
        let u3 = FileOps.undoWithRedo(UndoRecord(label: "Rename", steps: [.moveBack(from: r.dst!, to: r.src)]), store: nil)
        FileOps.undo(try #require(u3.redo), store: nil)
        #expect(fm.fileExists(atPath: b + "/h.txt") && !fm.fileExists(atPath: b + "/f.txt"))
    }
    @Test func historySymbols() {
        func e(_ t: String) -> HistoryEntry { HistoryEntry(id: "x", kind: .fileOp, at: "", title: t, detail: "", folder: nil, table: "", column: "", key: .null) }
        #expect(e("move /a → /b").displayTitle == "➡️ /a → /b")
        #expect(e("copy 3 items → /b").displayTitle == "📋 3 items → /b".replacingOccurrences(of: "3 items", with: "3 items"))
        #expect(e("trash /a").displayTitle == "🗑️ /a" && e("rename /a → /b").displayTitle.hasPrefix("✏️"))
        #expect(e("unknown /a").displayTitle == "unknown /a")
    }
    @Test func undoMoveAndCopy() throws {
        let a = try tempDir(), b = try tempDir()
        FileManager.default.createFile(atPath: a + "/f.txt", contents: Data("x".utf8))
        let mv = FileOps.perform(.move, sources: [a + "/f.txt"], into: b, store: nil)
        let rec = try #require(UndoRecord.forJob(.move, results: mv, conflict: .keepBoth))
        #expect(FileOps.undo(rec, store: nil)[0].result == "done")
        #expect(FileManager.default.fileExists(atPath: a + "/f.txt") && !FileManager.default.fileExists(atPath: b + "/f.txt"))
        let cp = FileOps.perform(.copy, sources: [a + "/f.txt"], into: b, store: nil)
        FileOps.undo(try #require(UndoRecord.forJob(.copy, results: cp, conflict: .keepBoth)), store: nil)
        #expect(!FileManager.default.fileExists(atPath: b + "/f.txt") && FileManager.default.fileExists(atPath: a + "/f.txt"))
        #expect(UndoRecord.forJob(.copy, results: cp, conflict: .replace) == nil)
    }
    @Test func undoRenameIncludingCaseOnly() throws {
        let d = try tempDir()
        FileManager.default.createFile(atPath: d + "/a.txt", contents: Data())
        for new in ["b.txt", "B.txt"] {
            let old = try FileManager.default.contentsOfDirectory(atPath: d)[0]
            let r = FileOps.rename(d + "/" + old, to: new, store: nil)
            FileOps.undo(UndoRecord(label: "Rename", steps: [.moveBack(from: r.dst!, to: r.src)]), store: nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: d) == [old])
        }
    }
    @Test func undoTrashRestores() throws {
        let s = try tempStore(), d = try tempDir()
        try Data("keep".utf8).write(to: URL(fileURLWithPath: d + "/t-\(UUID().uuidString).txt"))
        let p = d + "/" + (try FileManager.default.contentsOfDirectory(atPath: d)[0])
        let (rec, res) = FileOps.trash([p], store: s)
        #expect(res[0].result == "done" && !FileManager.default.fileExists(atPath: p))
        #expect(FileOps.undo(try #require(rec), store: s)[0].result == "done")
        #expect(try String(contentsOfFile: p, encoding: .utf8) == "keep")
    }
    @Test func undoNeverOverwrites() throws {
        let d = try tempDir()
        FileManager.default.createFile(atPath: d + "/new.txt", contents: Data())
        FileManager.default.createFile(atPath: d + "/orig.txt", contents: Data())
        let r = FileOps.undo(UndoRecord(label: "Move", steps: [.moveBack(from: d + "/new.txt", to: d + "/orig.txt")]), store: nil)
        #expect(r[0].result == "failed" && r[0].message?.contains("already exists") == true)
    }
}

@Suite struct QuickFindTests {
    private func files(_ names: [String]) throws -> (String, [String]) {
        let d = try tempDir()
        for n in names {
            let p = d + "/" + n
            try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: p, contents: Data())
        }
        return (d, names.map { d + "/" + $0 })
    }

    @Test func nameMatchBeatsPathMatchAndAllWordsRequired() throws {
        let (d, p) = try files(["budget.xlsx", "old/budget notes.txt", "reports/budget/readme.md", "other.txt"])
        let r = QuickFind.rank(paths: p, query: "budget", currentFolder: nil, frecency: [:])
        #expect(r.count == 3 && r[0].name == "budget.xlsx" && r.last?.name == "readme.md")
        #expect(QuickFind.rank(paths: p, query: "budget notes", currentFolder: nil, frecency: [:]).map(\.name) == ["budget notes.txt"])
        #expect(QuickFind.rank(paths: p, query: "budget zzz", currentFolder: nil, frecency: [:]).isEmpty)
        #expect(QuickFind.rank(paths: p, query: "  ", currentFolder: nil, frecency: [:]).isEmpty)
        _ = d
    }
    @Test func locationFrecencyAndNoise() throws {
        let (d, p) = try files(["a/plan.md", "b/plan.md", "Library/Caches/plan.md"])
        let inB = QuickFind.rank(paths: p, query: "plan", currentFolder: d + "/b", frecency: [:])
        #expect(inB[0].path == d + "/b/plan.md")
        let used = QuickFind.rank(paths: p, query: "plan", currentFolder: nil, frecency: [d + "/a/plan.md": 8])
        #expect(used[0].path == d + "/a/plan.md")
        #expect(used.last?.path.contains("/Library/Caches/") == true) // noise sinks to the bottom
    }
    @Test func frecencyDecaysWithAge() throws {
        let s = try tempStore()
        try s.logVisit(tabID: UUID(), path: "/recent", source: .click)
        try s.db.exec("INSERT INTO nav_history(tab_id,path,source,visited_at) VALUES('t','/old','click',?)",
                      [.text(iso8601(Date().addingTimeInterval(-60 * 86400)))])
        try s.db.exec("INSERT INTO file_opens(path,opened_at) VALUES('/file',?)", [.text(iso8601Now())])
        let f = try s.frecencyScores()
        #expect(f["/recent"]! > 0.9 && f["/old"]! < 0.05 && f["/file"]! > 1.9)
    }
    @Test func mdfindExpressionAndLineCap() {
        #expect(MDFind.expression(for: "foo bar") == "kMDItemFSName == \"*foo*\"cd && kMDItemFSName == \"*bar*\"cd")
        #expect(MDFind.expression(for: "a\"b")?.contains("a\\\"b") == true)
        #expect(MDFind.expression(for: "   ") == nil)
        let big = Data((1...1000).map { "/p\($0)\n" }.joined().utf8)
        #expect(MDFind.lines(from: big).count == 400)
    }
    @Test func spotlightSearchRunsAndRespectsLimit() async {
        let r = await MDFind.search(query: "Package", onlyIn: "/Applications", limit: 5)
        #expect(r.count <= 5)
    }
}

@Suite struct NetworkTests {
    @Test func settingsLoadOnlyValidEntries() throws {
        let dir = try tempDir(), f = URL(fileURLWithPath: dir + "/settings.json")
        try Data(#"""
        {"network_locations":[
          {"title":"NAS","kind":"smb","url":"smb://nas.example/share"},
          {"title":"Pi","kind":"ssh","host":"pi.example","user":"me","path":"/home/me"},
          {"title":"Bad","kind":"ftp"}, {"kind":"smb"}]}
        """#.utf8).write(to: f)
        let l = NetworkLocation.load(from: f)
        #expect(l.map(\.title) == ["NAS", "Pi"] && l[1].user == "me" && l[0].kind == .smb)
        #expect(NetworkLocation.load(from: URL(fileURLWithPath: dir + "/none.json")).isEmpty)
    }
    @Test func smbMatchesHowMacOSNamesMounts() {
        #expect(Mounts.hostAndShare("//USER@NAS._smb._tcp.local/share")! == ("nas", "share"))
        #expect(Mounts.hostAndShare("smb://me@Nas.example.local/My%20Docs")! == ("nas.example", "my docs"))
        let vols = [MountedVolume(mountPoint: "/Volumes/share", from: "//USER@NAS._smb._tcp.local/share", fsType: "smbfs"),
                    MountedVolume(mountPoint: "/", from: "/dev/disk3s1", fsType: "apfs")]
        #expect(Mounts.smbMountPoint(for: "smb://nas/share", in: vols) == "/Volumes/share")
        #expect(Mounts.smbMountPoint(for: "smb://NAS", in: vols) == "/Volumes/share") // no share named: any share on that host
        #expect(Mounts.smbMountPoint(for: "smb://nas/other", in: vols) == nil)
        #expect(Mounts.smbMountPoint(for: "smb://elsewhere/share", in: vols) == nil)
        #expect(vols[0].isNetwork && !vols[1].isNetwork)
    }
    @Test func sshMountPointIsPerTitleAndInsideSupportFolder() {
        let a = NetworkLocation(title: "My Pi!", kind: .ssh, host: "h")
        #expect(a.sshMountPoint.hasSuffix("/LocalSearch/mnt/my-pi-"))
        #expect(Mounts.mountPoint(for: a, in: [MountedVolume(mountPoint: a.sshMountPoint, from: "x", fsType: "macfuse")]) == a.sshMountPoint)
        #expect(Mounts.mountPoint(for: a, in: []) == nil)
    }
    @Test func listsRealMounts() {
        #expect(Mounts.all().contains { $0.mountPoint == "/" })
    }
    @Test func sshWithoutSshfsExplainsWhatToInstall() {
        guard NetworkMounter.sshfsPath == nil else { return }
        #expect(throws: NetworkError.self) { try NetworkMounter.mount(NetworkLocation(title: "x", kind: .ssh, host: "h")) }
    }
}

@Suite struct SSHConfigTests {
    @Test func listsNamedHostsOnly() {
        let cfg = """
        Host *
          ServerAliveInterval 30
        Host pi nas
          User me
        host=build
        Host *.example !bad
        # Host commented
        """
        #expect(SSHConfig.hosts(from: cfg) == ["pi", "nas", "build"])
        #expect(SSHConfig.hosts(from: "").isEmpty)
    }
}

@Suite struct NetworkEditTests {
    @Test func addAndRemoveKeepOtherSettings() throws {
        let f = URL(fileURLWithPath: try tempDir() + "/settings.json")
        try Data(#"{"special_folders":[{"title":"A","path":"/a"}]}"#.utf8).write(to: f)
        #expect(NetworkLocation.addSSH(alias: "pi", at: f))
        #expect(!NetworkLocation.addSSH(alias: "pi", at: f)) // no duplicates
        #expect(NetworkLocation.load(from: f).map(\.title) == ["pi"])
        #expect(NetworkLocation.remove(title: "pi", at: f))
        #expect(!NetworkLocation.remove(title: "pi", at: f))
        #expect(NetworkLocation.load(from: f).isEmpty)
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as? [String: Any]
        #expect(obj?["special_folders"] != nil)
    }
}

@Suite struct QuickFindPartialTests {
    @Test func partialNameInTheMiddleStillFindsTheFile() {
        let r = QuickFind.rank(paths: ["/tmp/x/memo.md", "/tmp/x/other.txt"], query: "mo.md", currentFolder: nil, frecency: [:], home: "/nonexistent")
        #expect(r.map(\.name) == ["memo.md"])
    }
}

@Suite struct QuickFindFolderTests {
    @Test func folderWithoutTheTextIsNotAMatch() {
        let r = QuickFind.rank(paths: ["/Users/x/Desktop/ls-test"], query: "mo.md", currentFolder: "/Users/x/Desktop/ls-test", frecency: [:], home: "/Users/x")
        #expect(r.isEmpty)
    }
}

@Suite struct DateGroupTests {
    @Test func bucketsFollowTheSpec() {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 15))! // a Wednesday
        func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: h))! }
        #expect(DateGroup.label(for: d(2026, 11, 25, 1), now: now, calendar: cal) == "Today")
        #expect(DateGroup.label(for: d(2026, 11, 24, 23), now: now, calendar: cal) == "Yesterday")
        #expect(DateGroup.label(for: d(2026, 11, 22), now: now, calendar: cal) == "Last 3 Days")
        #expect(DateGroup.label(for: d(2026, 11, 21), now: now, calendar: cal) == "Earlier This Month") // Saturday, previous week
        #expect(DateGroup.label(for: d(2026, 11, 3), now: now, calendar: cal) == "Earlier This Month")
        #expect(DateGroup.label(for: d(2026, 6, 1), now: now, calendar: cal) == "Earlier This Year")
        #expect(DateGroup.label(for: d(2025, 12, 31), now: now, calendar: cal) == "Before This Year")
        #expect(DateGroup.label(for: d(2026, 12, 1), now: now, calendar: cal) == "Today") // future dates
    }
    @Test func earlierThisWeekIsReachable() {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2; cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 29, hour: 15))! // Sunday: week began Mon 23rd
        let mon = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!
        #expect(DateGroup.label(for: mon, now: now, calendar: cal) == "Earlier This Week")
    }
}

@Suite struct FileColorTests {
    @Test func categories() {
        #expect(FileColor.classify(name: "a", isDirectory: true, isSymlink: false, isExecutable: false) == .directory)
        #expect(FileColor.classify(name: "a", isDirectory: true, isSymlink: true, isExecutable: false) == .symlink)
        #expect(FileColor.classify(name: "x.ZIP", isDirectory: false, isSymlink: false, isExecutable: false) == .archive)
        #expect(FileColor.classify(name: "run.sh", isDirectory: false, isSymlink: false, isExecutable: true) == .executable)
        #expect(FileColor.classify(name: "notes.txt", isDirectory: false, isSymlink: false, isExecutable: false) == .plain)
    }
    @Test func extensionBeatsExecutableBit() {
        #expect(FileColor.classify(name: "pic.jpg", isDirectory: false, isSymlink: false, isExecutable: true) == .image)
    }
}

@Suite struct RecentTests {
    @Test func bands() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000 + 12 * 3600)
        func band(_ h: Double) -> String? { RecentBand.label(for: now.addingTimeInterval(-h * 3600), now: now, calendar: cal) }
        #expect(band(1) == "Last 3 Hours")
        #expect(band(5) == "Last 12 Hours")
        #expect(band(30) == "Yesterday")
        #expect(band(24 * 2 + 1) == "2 Days Ago")
        #expect(band(24 * 6) == "Last 7 Days")
        #expect(band(24 * 20) == nil)
    }
    @Test func uniqueHideAndReturn() throws {
        let s = try tempStore()
        let t = UUID()
        try s.logVisit(tabID: t, path: "/x/a", source: .click)
        try s.logVisit(tabID: t, path: "/x/b", source: .click)
        try s.logVisit(tabID: t, path: "/x/a", source: .click)
        #expect(try s.recentFolders().map(\.path).sorted() == ["/x/a", "/x/b"])
        try s.hideRecent("/x/a")
        #expect(try s.recentFolders().map(\.path) == ["/x/b"])
        #expect(try s.navigationHistory().count == 3)
        try s.logVisit(tabID: t, path: "/x/a", source: .click)
        #expect(try s.recentFolders().map(\.path).contains("/x/a"))
    }
}

@Suite struct RecentFilesTests {
    @Test func uniqueAndDelete() throws {
        let s = try tempStore()
        try s.logOpen(path: "/x/a.txt"); try s.logOpen(path: "/x/b.txt"); try s.logOpen(path: "/x/a.txt")
        #expect(try s.recentFiles().map(\.path).sorted() == ["/x/a.txt", "/x/b.txt"])
        try s.deleteOpens(of: "/x/a.txt")
        #expect(try s.recentFiles().map(\.path) == ["/x/b.txt"])
    }
}

@Suite struct PreviewTests {
    private func tmp(_ name: String, _ data: Data) -> String {
        let dir = NSTemporaryDirectory() + "pv-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = dir + "/" + name
        FileManager.default.createFile(atPath: p, contents: data)
        return p
    }
    @Test func kinds() {
        #expect(Preview.kind(forName: "a.MD") == .markdown)
        #expect(Preview.kind(forName: "a.png") == .image)
        #expect(Preview.kind(forName: "a.swift") == .text)
        if case .unsupported = Preview.kind(forName: "a.dmg") {} else { Issue.record("dmg should be unsupported") }
    }
    @Test func binaryDetection() {
        #expect(Preview.looksBinary(Data([0x68, 0x00, 0x69])))
        #expect(!Preview.looksBinary(Data("héllo".utf8)))
        #expect(Preview.looksBinary(Data([0xff, 0xfe, 0xfd, 0xfc, 0xfb, 0xfa])))
    }
    @Test func textIsCappedAt64KB() {
        let p = tmp("big.txt", Data(String(repeating: "a", count: 100_000).utf8))
        guard case .text(let t) = Preview.loadText(path: p, size: 100_000) else { Issue.record("expected text"); return }
        #expect(t.truncated)
        #expect(t.text.utf8.count <= Preview.textCap)
    }
    @Test func overOneMegabyteNeedsAClick() {
        let p = tmp("huge.txt", Data(String(repeating: "a", count: 1_100_000).utf8))
        #expect(Preview.loadText(path: p, size: 1_100_000) == .needsClick(size: 1_100_000))
        if case .text = Preview.loadText(path: p, size: 1_100_000, allowLarge: true) {} else { Issue.record("allowLarge should read") }
    }
    @Test func secretsAreWithheldUntilShown() {
        let p = tmp(".env", Data("A=1\n".utf8))
        if case .withheld = Preview.loadText(path: p, size: 4) {} else { Issue.record("a .env file should be withheld") }
        if case .text = Preview.loadText(path: p, size: 4, showSecrets: true) {} else { Issue.record("Show Anyway should read it") }
        let q = tmp("notes.txt", Data("password = hunter2hunter2hunter2\n".utf8))
        if case .withheld = Preview.loadText(path: q, size: 40) {} else { Issue.record("a password line should be withheld") }
        let r = tmp("plain.txt", Data("just notes\n".utf8))
        if case .text = Preview.loadText(path: r, size: 11) {} else { Issue.record("plain text should show") }
    }
    @Test func binaryFileIsRejected() {
        let p = tmp("x.dat", Data([0x00, 0x01, 0x02, 0x03]))
        #expect(Preview.loadText(path: p, size: 4) == .unsupported("Binary file"))
    }
    @Test func markdownBlocks() {
        let b = MarkdownBlocks.parse("# Title\n\nSome *text*\nmore\n\n- one\n- two\n\n```\ncode\n```\n---\n")
        #expect(b == [.heading(1, "Title"), .paragraph("Some *text* more"), .bullet("one"), .bullet("two"), .code("code"), .rule])
    }
}

@Suite struct MorePreviewTests {
    @Test func newKinds() {
        #expect(Preview.kind(forName: "a.json") == .json)
        #expect(Preview.kind(forName: "a.csv") == .csv(","))
        #expect(Preview.kind(forName: "a.tsv") == .csv("\t"))
        #expect(Preview.kind(forName: "a.svg") == .svg)
        #expect(Preview.kind(forName: "a.HTML") == .html)
        #expect(Preview.kind(forName: "a.zip") == .archive)
        #expect(Preview.kind(forName: "a.tar.gz") == .archive)
    }
    @Test func jsonPretty() {
        #expect(JSONPreview.pretty("{\"b\":1,\"a\":[1,2]}")?.contains("\n  \"a\" : [") == true)
        #expect(JSONPreview.pretty("not json") == nil)
    }
    @Test func csvQuotesAndLimits() {
        let t = CSVPreview.parse("a,b\n\"x,1\",\"he said \"\"hi\"\"\"\n", delimiter: ",")
        #expect(t.rows == [["a", "b"], ["x,1", "he said \"hi\""]])
        let wide = CSVPreview.parse((1...30).map(String.init).joined(separator: ","), delimiter: ",")
        #expect(wide.rows[0].count == 20 && wide.moreColumns)
        let tall = CSVPreview.parse((1...80).map { "r\($0)" }.joined(separator: "\n"), delimiter: ",")
        #expect(tall.rows.count == 50 && tall.moreRows)
        #expect(CSVPreview.parse("a\tb\n", delimiter: "\t").rows == [["a", "b"]])
    }
    @Test func archiveListing() throws {
        let dir = NSTemporaryDirectory() + "ar-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/src", withIntermediateDirectories: true)
        for i in 1...250 { FileManager.default.createFile(atPath: dir + "/src/f\(i).txt", contents: Data("x".utf8)) }
        func run(_ exe: String, _ args: [String]) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
            p.currentDirectoryURL = URL(fileURLWithPath: dir); p.standardOutput = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
        }
        try run("/usr/bin/zip", ["-qr", "a.zip", "src"])
        try run("/usr/bin/tar", ["-czf", "a.tar.gz", "src"])
        for name in ["a.zip", "a.tar.gz"] {
            let r = try #require(Archive.list(path: dir + "/" + name))
            #expect(r.entries.count == 200 && r.truncated)
        }
        #expect(Archive.list(path: dir + "/missing.zip") == nil)
    }
}

@Suite struct ProjectsTests {
    private func settings(_ json: String? = nil) -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory() + "pj-\(UUID().uuidString)/settings.json")
        if let json { try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try? json.write(to: u, atomically: true, encoding: .utf8) }
        return u
    }
    @Test func loadExpandsTildeAndDefaultsTitle() {
        let u = settings(#"{"projects":[{"title":"A","path":"~/x/a"},{"path":"/y/b"},{"title":"bad"}]}"#)
        let p = Projects.load(from: u)
        #expect(p.map(\.title) == ["A", "b"])
        #expect(p[0].path == NSHomeDirectory() + "/x/a")
    }
    @Test func addRemoveKeepsOtherKeys() throws {
        let u = settings(#"{"network_locations":[{"title":"n","kind":"smb"}]}"#)
        #expect(Projects.add(path: "/p/one", at: u) == .added)
        #expect(Projects.add(path: "/p/one", at: u) == .alreadyThere)
        #expect(Projects.add(path: "/p/two", title: "Two", at: u) == .added)
        #expect(Projects.load(from: u).map(\.title) == ["one", "Two"])
        #expect(Projects.remove(path: "/p/one", at: u))
        #expect(!Projects.remove(path: "/p/none", at: u))
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: u)) as? [String: Any]
        #expect((obj?["network_locations"] as? [Any])?.count == 1)
    }
    @Test func limitOfTwenty() {
        let u = settings()
        for i in 1...20 { #expect(Projects.add(path: "/p/\(i)", at: u) == .added) }
        #expect(Projects.add(path: "/p/21", at: u) == .full)
    }
    @Test func reorder() {
        let u = settings()
        for n in ["a", "b", "c"] { Projects.add(path: "/p/\(n)", at: u) }
        #expect(Projects.move("/p/c", relativeTo: "/p/a", after: false, at: u))
        #expect(Projects.load(from: u).map(\.title) == ["c", "a", "b"])
        #expect(Projects.move("/p/c", relativeTo: "/p/b", after: true, at: u))
        #expect(Projects.load(from: u).map(\.title) == ["a", "b", "c"])
        #expect(!Projects.move("/p/c", relativeTo: "/p/c", after: true, at: u))
    }
}

@Suite struct CloudAndWebTests {
    private func tmpDir() -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory() + "cw-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    @Test func oneDriveTitlesAndDiscovery() throws {
        #expect(Cloud.title(forFolderName: "OneDrive") == "OneDrive")
        #expect(Cloud.title(forFolderName: "OneDrive-Acme") == "OneDrive – Acme")
        let d = tmpDir()
        for n in ["OneDrive", "OneDrive-Acme", "Dropbox", "OneDriveFile"] {
            if n == "OneDriveFile" { FileManager.default.createFile(atPath: d.appendingPathComponent(n).path, contents: Data()) }
            else { try FileManager.default.createDirectory(at: d.appendingPathComponent(n), withIntermediateDirectories: true) }
        }
        #expect(Cloud.discover(in: d).map(\.title) == ["OneDrive", "OneDrive – Acme"])
    }
    @Test func manualFoldersMergeAndKeepOtherKeys() throws {
        let d = tmpDir(), s = d.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: d.appendingPathComponent("OneDrive"), withIntermediateDirectories: true)
        try #"{"projects":[{"path":"/p"}]}"#.write(to: s, atomically: true, encoding: .utf8)
        #expect(Cloud.add(path: "/x/odrive", title: "Mine", settings: s))
        #expect(!Cloud.add(path: "/x/odrive", settings: s))
        #expect(Cloud.add(path: d.appendingPathComponent("OneDrive").path, settings: s)) // also discovered
        let all = Cloud.load(settings: s, storage: d)
        #expect(all.map(\.title) == ["OneDrive", "Mine"] && all.map(\.manual) == [false, true])
        #expect(Cloud.remove(path: "/x/odrive", settings: s))
        #expect(Projects.load(from: s).count == 1)
    }
    @Test func onlyHttpsIsAccepted() {
        #expect(WebLocations.validURL("https://example.org/a") != nil)
        #expect(WebLocations.validURL("http://example.org") == nil)
        #expect(WebLocations.validURL("s3://bucket/key") == nil)
        #expect(WebLocations.validURL("javascript:alert(1)") == nil)
        #expect(WebLocations.validURL("https://") == nil)
    }
    @Test func loadAddRemoveSearch() throws {
        let s = tmpDir().appendingPathComponent("settings.json")
        try #"{"web_locations":[{"title":"Wiki","url":"https://wiki.example/home","notes":"team docs"},{"url":"s3://b/k"},{"url":"http://plain.example"},{"url":"https://host.example/x"}]}"#.write(to: s, atomically: true, encoding: .utf8)
        var all = WebLocations.load(from: s)
        #expect(all.map(\.title) == ["Wiki", "host.example"])
        #expect(WebLocations.add(title: "Tracker", url: "https://t.example", notes: "bugs", at: s) == .added)
        #expect(WebLocations.add(title: "x", url: "https://t.example", at: s) == .alreadyThere)
        #expect(WebLocations.add(title: "x", url: "ftp://t.example", at: s) == .invalid)
        all = WebLocations.load(from: s)
        #expect(all.count == 3)
        #expect(WebLocations.search(all, "docs team").map(\.title) == ["Wiki"])
        #expect(WebLocations.search(all, "t.example bugs").map(\.title) == ["Tracker"])
        #expect(WebLocations.search(all, "docs bugs").isEmpty)
        #expect(WebLocations.remove(url: "https://t.example", at: s))
        #expect(WebLocations.load(from: s).count == 2)
    }
}

@Suite struct IgnoredFoldersTests {
    @Test func normaliseAndMatch() {
        #expect(FinderStore.normalizedIgnored("/a/b/") == "/a/b")
        #expect(FinderStore.normalizedIgnored("/") == nil)
        #expect(FinderStore.normalizedIgnored("") == nil)
        #expect(FinderStore.normalizedIgnored("~/x") == NSHomeDirectory() + "/x")
        #expect(FinderStore.isIgnored("/a/b", in: ["/a/b"]))
        #expect(FinderStore.isIgnored("/a/b/c/d", in: ["/a/b"]))
        #expect(!FinderStore.isIgnored("/a/bc", in: ["/a/b"]))
    }
    @Test func ignoredPathsAreNotRecorded() throws {
        let s = try tempStore(), t = UUID()
        s.setIgnoredFolders(["/secret/", "/secret", "/"])
        #expect(s.ignoredFolders() == ["/secret"])
        try s.logVisit(tabID: t, path: "/secret/inner", source: .click)
        try s.logOpen(path: "/secret/file.txt")
        try s.logVisit(tabID: t, path: "/open/one", source: .click)
        try s.logOpen(path: "/open/file.txt")
        #expect(try s.navigationHistory().map(\.path) == ["/open/one"])
        #expect(try s.recentFiles().map(\.path) == ["/open/file.txt"])
    }
    @Test func newIgnoreHidesRecentAndCanDeleteExisting() throws {
        let s = try tempStore(), t = UUID()
        try s.logVisit(tabID: t, path: "/p/a", source: .click)
        try s.logVisit(tabID: t, path: "/p/a/sub", source: .click)
        try s.logVisit(tabID: t, path: "/p/ab", source: .click)
        try s.logOpen(path: "/p/a/f.txt")
        s.setIgnoredFolders(["/p/a"])
        #expect(try s.recentFolders().map(\.path) == ["/p/ab"])      // hidden from Recent at once
        #expect(try s.navigationHistory().count == 3)               // history kept until deleted
        #expect(try s.deleteHistory(under: "/p/a") == 3)
        #expect(try s.navigationHistory().map(\.path) == ["/p/ab"])
        #expect(try s.recentFiles().isEmpty)
    }
}

@Suite struct SettingsFileTests {
    private func file(_ text: String?) -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory() + "sf-\(UUID().uuidString).json")
        if let text { try? text.write(to: u, atomically: true, encoding: .utf8) }
        return u
    }
    @Test func malformedDetection() {
        #expect(!SettingsFile.isMalformed(file(nil)))            // missing is fine
        #expect(!SettingsFile.isMalformed(file("")))             // empty is fine
        #expect(!SettingsFile.isMalformed(file("  \n")))
        #expect(!SettingsFile.isMalformed(file(#"{"projects":[]}"#)))
        #expect(SettingsFile.isMalformed(file(#"{"projects":["#)))
        #expect(SettingsFile.isMalformed(file("[1,2]")))         // valid JSON, but not an object
        #expect(SettingsFile.isMalformed(file("nope")))
    }
}

@Suite struct ActionsTests {
    private func act(_ cmd: String, _ f: (inout Action) -> Void = { _ in }) -> Action {
        var a = Action(id: "t", title: "T", group: "G", description: "d", command: cmd)
        f(&a); return a
    }
    private func ctx(_ sel: [String], folder: String = "/w", exists: @escaping @Sendable (String) -> Bool = { _ in false }) -> ActionContext {
        ActionContext(folder: folder, selection: sel, home: "/home/u", isDirectory: { $0.hasSuffix("/dir") }, exists: exists)
    }

    @Test func quoting() {
        #expect(Actions.shellQuote("a.txt") == "a.txt")
        #expect(Actions.shellQuote("my file.txt") == "'my file.txt'")
        #expect(Actions.shellQuote("it's") == "'it'\\''s'")
        #expect(Actions.shellQuote("$(rm -rf ~)") == "'$(rm -rf ~)'")
        #expect(Actions.shellQuote("") == "''")
    }
    @Test func selectionAndFileTokens() {
        let a = act("zip {{selection}}")
        #expect(Actions.render(a, in: ctx(["/w/a b.txt", "/w/c.txt"])) == "zip 'a b.txt' c.txt")
        let f = act("cp {{file}} {{stem}}.{{ext}}.bak")
        #expect(Actions.render(f, in: ctx(["/w/r.png"])) == "cp r.png r.png.bak")
        #expect(Actions.render(act("cd {{folder}}"), in: ctx([], folder: "/my dir")) == "cd '/my dir'")
    }
    @Test func eachRendersOneLinePerItemWithDistinctOutputs() {
        let a = act("conv {{file}} {{out:<stem>.png}}") { $0.each = true }
        let out = Actions.render(a, in: ctx(["/w/a.jpg", "/w/a.gif"]))
        #expect(out == "conv a.jpg a.png\nconv a.gif 'a 2.png'")
    }
    @Test func outNeverOverwrites() {
        #expect(Actions.uniqueName("A.zip", in: "/w", exists: { _ in false }) == "A.zip")
        #expect(Actions.uniqueName("A.zip", in: "/w", exists: { $0 == "/w/A.zip" }) == "A 2.zip")
        #expect(Actions.uniqueName("A.zip", in: "/w", exists: { $0 == "/w/A.zip" || $0 == "/w/A 2.zip" }) == "A 3.zip")
        #expect(Actions.uniqueName("dir", in: "/w", exists: { $0 == "/w/dir" }) == "dir 2")
    }
    @Test func askValuesAreQuotedAndDefaulted() {
        let a = act("grep {{ask:Text=TODO}} .")
        #expect(Actions.asks(in: a.command).map(\.label) == ["Text"])
        #expect(Actions.asks(in: a.command).first?.def == "TODO")
        #expect(Actions.render(a, in: ctx([])) == "grep TODO .")
        #expect(Actions.render(a, in: ctx([]), asks: ["Text": "a b; rm x"]) == "grep 'a b; rm x' .")
    }
    @Test func availabilityRules() {
        #expect(Actions.availability(of: act("zip {{selection}}"), in: ctx([])) == .unavailable("Select one or more items"))
        #expect(Actions.availability(of: act("zip {{selection}}"), in: ctx(["/w/a"])).isAvailable)
        #expect(Actions.availability(of: act("x {{file}}"), in: ctx(["/w/a", "/w/b"])) == .unavailable("Select exactly one item"))
        #expect(Actions.availability(of: act("x {{file}}") { $0.each = true }, in: ctx(["/w/a", "/w/b"])).isAvailable)
        #expect(Actions.availability(of: act("ls"), in: ctx([])).isAvailable)
        let img = act("x {{file}}") { $0.extensions = ["png"] }
        #expect(Actions.availability(of: img, in: ctx(["/w/a.PNG"])).isAvailable)
        #expect(!Actions.availability(of: img, in: ctx(["/w/a.txt"])).isAvailable)
        #expect(!Actions.availability(of: img, in: ctx(["/w/x/dir"])).isAvailable)
        let home = act("find .") { $0.notInHome = true }
        #expect(!Actions.availability(of: home, in: ctx([], folder: "/home/u")).isAvailable)
        #expect(Actions.availability(of: home, in: ctx([], folder: "/home/u/code")).isAvailable)
        let cloud = act("aws s3 ls") { $0.requires = ["s3"] }
        #expect(!Actions.availability(of: cloud, in: ctx([])).isAvailable)
        let tool = act("ffmpeg") { $0.tool = "ffmpeg" }
        let none = ActionContext(folder: "/w", selection: [], hasTool: { _ in false })
        #expect(Actions.availability(of: tool, in: none) == .unavailable("ffmpeg isn't installed"))
    }
    @Test func bundledDefaultsParseAndAreUnique() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/actions.json").standardized
        let f = try #require(Actions.parse(try Data(contentsOf: url)).file)
        #expect(f.actions.count >= 20)
        #expect(Set(f.actions.map(\.id)).count == f.actions.count)
        for a in f.actions { #expect(!a.description.isEmpty && !a.command.isEmpty, "\(a.id)") }
    }
    @Test func installAndUpgrade() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory() + "act-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let b = dir.appendingPathComponent("b.json"), t = dir.appendingPathComponent("sub/actions.json")
        func write(_ v: Int, to u: URL) throws { try Data(#"{"version":\#(v),"actions":[]}"#.utf8).write(to: u) }
        try write(2, to: b)
        #expect(Actions.installDefaults(bundled: b, to: t))                 // created
        #expect(!Actions.installDefaults(bundled: b, to: t))                // same version: untouched
        try write(3, to: b)
        #expect(Actions.installDefaults(bundled: b, to: t))                 // upgraded
        #expect(FileManager.default.fileExists(atPath: t.appendingPathExtension("bak").path))
        try Data("not json".utf8).write(to: t)
        #expect(Actions.installDefaults(bundled: b, to: t))                 // unreadable: replaced, old kept
    }
}

@Suite(.serialized) struct AdjustableLimitsTests {
    private let keys = ["previewTextKB", "previewBigMB", "previewWithholdSecrets", "smbTimeoutSeconds", "sshTimeoutSeconds"]
    private func reset() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    @Test func defaultsAndClamping() {
        reset(); defer { reset() }
        #expect(Preview.textCap == 64 * 1024)
        #expect(Preview.bigFile == 1_048_576)
        #expect(Preview.withholdSecrets)
        #expect(NetworkMounter.smbTimeout == 15 && NetworkMounter.sshTimeout == 25)
        UserDefaults.standard.set(256, forKey: "previewTextKB")
        UserDefaults.standard.set(999, forKey: "previewBigMB")      // out of range: clamped to 100
        UserDefaults.standard.set(1, forKey: "smbTimeoutSeconds")   // out of range: clamped to 5
        #expect(Preview.textCap == 256 * 1024)
        #expect(Preview.bigFile == 100 * 1_048_576)
        #expect(NetworkMounter.smbTimeout == 5)
    }
    @Test func secretsSwitchAndBigLimitApply() throws {
        reset(); defer { reset() }
        let dir = NSTemporaryDirectory() + "lim-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let f = dir + "/.env"
        try "API_KEY=abc123\n".write(toFile: f, atomically: true, encoding: .utf8)
        if case .withheld = Preview.loadText(path: f, size: 15) {} else { Issue.record("expected withheld") }
        UserDefaults.standard.set(false, forKey: "previewWithholdSecrets")
        if case .text = Preview.loadText(path: f, size: 15) {} else { Issue.record("expected text") }
        let big = dir + "/big.txt"
        try String(repeating: "line\n", count: 300_000).write(toFile: big, atomically: true, encoding: .utf8)   // ~1.5 MB
        if case .needsClick = Preview.loadText(path: big, size: 1_500_000) {} else { Issue.record("expected needsClick") }
        UserDefaults.standard.set(5, forKey: "previewBigMB")
        if case .text = Preview.loadText(path: big, size: 1_500_000) {} else { Issue.record("expected text after raising limit") }
    }
}

@Suite struct PermissionsTests {
    @Test func stringsLikeLs() {
        #expect(Permissions.string(mode: 0o755, isDirectory: true) == "drwxr-xr-x")
        #expect(Permissions.string(mode: 0o644, isDirectory: false) == "-rw-r--r--")
        #expect(Permissions.string(mode: 0o400, isDirectory: false) == "-r--------")
        #expect(Permissions.string(mode: 0o2777, isDirectory: true) == "drwxrwsrwx")      // setgid
        #expect(Permissions.string(mode: 0o1777, isDirectory: true) == "drwxrwxrwt")      // sticky
        #expect(Permissions.string(mode: 0o4755, isDirectory: false) == "-rwsr-xr-x")     // setuid
        #expect(Permissions.string(mode: 0o4644, isDirectory: false) == "-rwSr--r--")
        #expect(Permissions.string(mode: 0o777, isDirectory: false, isSymlink: true) == "lrwxrwxrwx")
        #expect(Permissions.octal(0o644) == "644" && Permissions.octal(0o7) == "007" && Permissions.octal(0o4755) == "4755")
    }
    @Test func presets() {
        #expect(Permissions.newMode(0o644, .makeExecutable, isDirectory: false) == 0o755)
        #expect(Permissions.newMode(0o755, .removeExecute, isDirectory: false) == 0o644)
        #expect(Permissions.newMode(0o755, .removeExecute, isDirectory: true) == 0o755)    // folders keep x
        #expect(Permissions.newMode(0o644, .privateToOwner, isDirectory: false) == 0o600)
        #expect(Permissions.newMode(0o755, .privateToOwner, isDirectory: true) == 0o700)
        #expect(Permissions.newMode(0o644, .readOnly, isDirectory: false) == 0o400)
        #expect(Permissions.newMode(0o4755, .privateToOwner, isDirectory: false) == 0o600)  // special bits cleared
    }
    @Test func applyAndRestoreOnDisk() throws {
        let dir = NSTemporaryDirectory() + "perm-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let f = dir + "/key", link = dir + "/ln"
        try "x".write(toFile: f, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: f)
        chmod(f, 0o644)
        let c = try #require(try Permissions.apply(.readOnly, to: f, isDirectory: false))
        #expect(Permissions.mode(of: f) == 0o400 && c.old == 0o644)
        #expect(try Permissions.apply(.readOnly, to: f, isDirectory: false) == nil)       // already so
        #expect(try Permissions.apply(.makeExecutable, to: link, isDirectory: false) == nil)   // symlink skipped
        Permissions.restore(c)
        #expect(Permissions.mode(of: f) == 0o644)
    }
    @Test func pasteChecks() {
        #expect(PathText.looksLikePath("/Users/x/My Docs/a.txt\n") == "/Users/x/My Docs/a.txt")
        #expect(PathText.looksLikePath("~/code") == "~/code")
        #expect(PathText.looksLikePath("'/a b/c'") == "/a b/c")
        #expect(PathText.looksLikePath("/a\\ b/c") == "/a b/c")
        #expect(PathText.looksLikePath("file:///tmp/a%20b") == "/tmp/a b")
        #expect(PathText.looksLikePath("hello world") == nil)
        #expect(PathText.looksLikePath("https://example.org/a") == nil)
        #expect(PathText.looksLikePath("/a\n/b") == nil)          // two lines
        #expect(PathText.looksLikePath("~bob/x") == nil)
        #expect(PathText.looksLikePath("") == nil && PathText.looksLikePath(nil) == nil)
    }
}
