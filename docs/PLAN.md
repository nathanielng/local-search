# Plan

The full brief lives in `finder-prompt.md` (kept outside the repo). This file tracks progress.

## Done

- SQLite store, schema v6, all tables; tabs, nav history, favorites, special folders, kv.
- Tabs: UUIDs, Back/Forward, close/reopen/duplicate, restore with nearest-parent fallback, lazy load of hidden tabs.
- Sidebar (Special Folders, Favorites, Locations, Config), file list, one date column.
- Drag and drop: move-by-default drops on sidebar rows and tabs, shortcut drops, copy into the current
  folder, AppKit drag-out (`AppKitDragFix`). **The drag into Slack is untested by hand.**
- File operations (`FileOps`): Keep Both, protected locations, logging to `file_ops`.
- History window (⌘Y) with CSV export, delete, clear, retention.
- MCP server: read-only tools.

## Next

1. Rename, New Text File, Copy/Paste with conflict prompts, Quick Look, Quick Find.
2. Right panel: Vertical Tabs, Recent Locations, Info & Preview.
3. Projects, Cloud, Web Locations; `settings.json` watching.
4. Command panel and `actions.json`.
5. Filing guide, local models, MCP write tools ("Allow changes"), themes.

## Gotchas

- `timeout` isn't installed; use `gtimeout` from coreutils for pushes.
- Tests need the Command Line Tools Testing framework paths (set in `scripts/test.sh`).
- `NSEvent` is not Sendable: the drag monitor wraps it in a box.
