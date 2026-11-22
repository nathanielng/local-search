# Plan

The full brief lives in `finder-prompt.md` (kept outside the repo). This file tracks progress.

## Done

- SQLite store, schema v6, all tables; tabs, nav history, favorites, special folders, kv.
- Tabs: UUIDs, Back/Forward, close/reopen/duplicate, restore with nearest-parent fallback, lazy load of hidden tabs.
- Sidebar (Special Folders, Favorites, Locations, Config), file list, one date column.
- Drag and drop: move-by-default drops on sidebar rows and tabs, shortcut drops, copy into the current
  folder, AppKit drag-out (`AppKitDragFix`). **The drag into Slack, and the new rename/paste/Quick Look UI, are untested by hand.**
- File operations (`FileOps`): Keep Both, protected locations, logging to `file_ops`.
- History window (⌘Y) with CSV export, delete, clear, retention.
- Rename (inline, stem selected), New Folder / New Text File (opened for renaming), Copy / Paste with
  Keep Both / Replace / Skip / Stop, background copy with progress and Stop, copy paths, copy file text
  for AI (skips binaries and likely secrets), Quick Look (Space), Show in Finder.
- MCP server: read-only tools.

## Next

1. Quick Find (⌘F), Group by Date, Kind badges, ls-style colours, folder watching.
2. Right panel: Vertical Tabs, Recent Locations, Info & Preview.
3. Projects, Cloud, Web Locations; `settings.json` watching.
4. Command panel and `actions.json`.
5. Filing guide, local models, MCP write tools ("Allow changes"), themes.

## Gotchas

- `timeout` isn't installed; use `gtimeout` from coreutils for pushes.
- Tests need the Command Line Tools Testing framework paths (set in `scripts/test.sh`).
- `NSEvent` is not Sendable: the drag monitor wraps it in a box.
