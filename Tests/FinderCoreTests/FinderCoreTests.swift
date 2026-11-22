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
