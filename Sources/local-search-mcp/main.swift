import Foundation
import FinderCore

// Newline-delimited JSON-RPC 2.0 over stdio (MCP 2025-06-18). No network listener.
let store = try FinderStore()
let pid = ProcessInfo.processInfo.processIdentifier
store.setKV("mcp_status:\(pid)", iso8601Now())
atexit { if let s = try? FinderStore() { s.deleteKV("mcp_status:\(ProcessInfo.processInfo.processIdentifier)") } }

func send(_ obj: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
          var s = String(data: d, encoding: .utf8) else { return }
    s += "\n"
    FileHandle.standardOutput.write(Data(s.utf8))
}

func tool(_ name: String, _ desc: String, _ props: [String: Any] = [:]) -> [String: Any] {
    ["name": name, "description": desc,
     "inputSchema": ["type": "object", "properties": props], "annotations": ["readOnlyHint": true]]
}

let limitProp: [String: Any] = ["limit": ["type": "integer", "description": "Max rows (default 50)"]]
let tools: [[String: Any]] = [
    tool("folders_visited", "Folders ranked by estimated time spent (gap to next visit, capped at 30 min).", limitProp),
    tool("navigation_history", "Recent folder visits, newest first.",
         limitProp.merging(["search": ["type": "string"]]) { a, _ in a }),
    tool("list_locations", "Special folders, favorites and open tabs."),
    tool("list_directory", "List a folder's entries.", ["path": ["type": "string"]]),
]

func text(_ s: String) -> [String: Any] { ["content": [["type": "text", "text": s]]] }
func json(_ o: Any) -> [String: Any] {
    let d = (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    return text(String(data: d, encoding: .utf8) ?? "")
}

func call(_ name: String, _ a: [String: Any]) throws -> [String: Any] {
    let limit = a["limit"] as? Int ?? 50
    switch name {
    case "folders_visited":
        return json(try store.foldersVisited(limit: limit).map {
            ["path": $0.path, "visits": $0.visits, "estimated_minutes": ($0.estimatedSeconds / 60 * 10).rounded() / 10] })
    case "navigation_history":
        return json(try store.navigationHistory(limit: limit, search: a["search"] as? String).map {
            ["path": $0.path, "source": $0.source, "at": $0.at, "tab": $0.tabID] })
    case "list_locations":
        let tabs = try store.loadOpenTabs().tabs.map { ["id": $0.id.uuidString, "path": $0.path] }
        return json(["special_folders": try store.specialFolders().map { ["title": $0.title, "path": $0.path] },
                     "favorites": try store.favorites().map { ["title": $0.title, "path": $0.path] },
                     "open_tabs": tabs])
    case "list_directory":
        guard let p = a["path"] as? String else { return text("path required") }
        let names = try FileManager.default.contentsOfDirectory(atPath: (p as NSString).expandingTildeInPath)
            .filter { !$0.hasPrefix(".") }.sorted().prefix(500)
        return json(Array(names))
    default: return text("unknown tool \(name)")
    }
}

while let line = readLine() {
    guard let d = line.data(using: .utf8), let msg = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let method = msg["method"] as? String else { continue }
    let id = msg["id"]
    func reply(_ result: [String: Any]) { if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) } }
    switch method {
    case "initialize":
        reply(["protocolVersion": "2025-06-18", "capabilities": ["tools": [String: Any]()],
               "serverInfo": ["name": "local-search", "version": "0.1.0"]])
    case "tools/list": reply(["tools": tools])
    case "tools/call":
        let p = msg["params"] as? [String: Any] ?? [:]
        do { reply(try call(p["name"] as? String ?? "", p["arguments"] as? [String: Any] ?? [:])) }
        catch { reply(["isError": true, "content": [["type": "text", "text": "\(error)"]]]) }
    case "ping": reply([:])
    default:
        if let id { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]]) }
    }
}
