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

1. (ls-style colours: done. Date-column switcher: built, awaiting hand test.) (Group by Date, multi-row tabs and Kind badges: done.)
2. Right panel: Vertical Tabs and Recent Locations (folders): built, awaiting hand test. Files Opened and drops on Recent rows: built, awaiting hand test. Info & Preview (info and all previews): built, awaiting hand test.
3. Projects, Cloud (OneDrive) and Web Locations (https only): built, awaiting hand test. Live `settings.json` watching: built. Still to do: WorkDocs Drive, s3:// Web Locations (needs the command panel).
4. Command panel (built: panel, runner, actions.json with 22 defaults, awaiting hand test; Cloud/S3/Local AI actions still to do) and `actions.json`.
5. Settings (⌘,): General, History, Previews, Network and Locations tabs built, awaiting hand test.
6. Rebindable shortcuts: own `shortcuts.json` (overrides only, so new defaults still arrive) and a Settings > Shortcuts tab (click a row, press the keys, clash warning, reset); in-context keys and system keys stay fixed.
7. Filing guide, local models, MCP write tools ("Allow changes"), themes.

## Gotchas

- After every rebuild macOS re-asks for Desktop/Documents/Downloads access. Until it is answered, folder listings fail and Spotlight/Quick Find silently omit files from those folders. A stable code-signing identity fixes this.
- `timeout` isn't installed; use `gtimeout` from coreutils for pushes.
- Tests need the Command Line Tools Testing framework paths (set in `scripts/test.sh`).
- `NSEvent` is not Sendable: the drag monitor wraps it in a box.
- NSTableView hides drag events inside its mouse tracking loop. Never consume and replay clicks; only watch the pointer while the button is held.
- SwiftUI can skip `dropExited`; keep drop highlights in one shared place and clear them when the button is up.
