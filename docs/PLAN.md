# Plan

The full brief lives in `finder-prompt.md` (kept outside the repo). This file tracks progress.

## Done

- SQLite store, schema v6, all tables; tabs, nav history, favorites, special folders, kv.
- Tabs: UUIDs, Back/Forward, close/reopen/duplicate, restore with nearest-parent fallback, lazy load of hidden tabs.
- Sidebar (Special Folders, Favorites, Locations, Config), file list, one date column.
- Drag and drop: move-by-default drops on sidebar rows and tabs, shortcut drops, copy into the current
  folder, AppKit drag-out (`AppKitDragFix`). See [TESTING.md](TESTING.md) for what has been verified by hand. The drag into Slack is still untested.
- File operations (`FileOps`): Keep Both, protected locations, logging to `file_ops`.
- History window (⌘Y) with CSV export, delete, clear, retention.
- Rename (inline, stem selected), New Folder / New Text File (opened for renaming), Copy / Paste with
  Keep Both / Replace / Skip / Stop, background copy with progress and Stop, copy paths, copy file text
  for AI (skips binaries and likely secrets), Quick Look (Space), Show in Finder.
- Quick Find (⌘F): instant local results, then Spotlight, ranked by name, location and frecency.
- Drag to reorder Favorites and Special Folders.
- Redo, History symbols, tab drop marker and end-of-row target.
- Undo (⌘Z), Move Item Here (⌥⌘V), folder watching, Favorites drop zones and right-click removal.
- MCP server: read-only tools.

## Next

1. Group by Date, Kind badges, ls-style colours.
2. Right panel: Vertical Tabs, Recent Locations, Info & Preview.
3. Projects, Cloud, Web Locations; `settings.json` watching.
4. Command panel and `actions.json`.
5. Filing guide, local models, MCP write tools ("Allow changes"), themes.

## Gotchas

- After every rebuild macOS re-asks for Desktop/Documents/Downloads access. Until it is answered, folder listings fail and Spotlight/Quick Find silently omit files from those folders. A stable code-signing identity fixes this.
- `timeout` isn't installed; use `gtimeout` from coreutils for pushes.
- Tests need the Command Line Tools Testing framework paths (set in `scripts/test.sh`).
- `NSEvent` is not Sendable: the drag monitor wraps it in a box.
- NSTableView hides drag events inside its mouse tracking loop. Never consume and replay clicks; only watch the pointer while the button is held.
- SwiftUI can skip `dropExited`; keep drop highlights in one shared place and clear them when the button is up.
