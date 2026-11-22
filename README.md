# Local Search

A native macOS file browser in the style of Finder, built for one user and for AI agents.
Its main job: **keep folder navigation history, and keep open tabs (with each tab's Back/Forward
history) across relaunches and reboots.** Agents such as Kiro and Claude can read the history and
sidebar through a bundled MCP server.

Status: early. See [docs/PLAN.md](docs/PLAN.md) for what is built and what is next.

## Build and run

Needs the macOS 26 SDK from the Command Line Tools (no Xcode).

```bash
scripts/build-app.sh     # builds dist/LocalSearch.app (ad-hoc signed)
open dist/LocalSearch.app
scripts/test.sh          # unit tests (swift-testing) in .build-test
```

Each rebuild changes the ad-hoc signature, so macOS may ask for privacy permissions again.

## Layout

| Target | Purpose |
|---|---|
| `FinderCore` | SQLite store, tab/navigation state, file operations, history queries. No UI. |
| `LocalSearch` | The SwiftUI app. |
| `local-search-mcp` | MCP server (JSON-RPC over stdio). Works with the app closed. |

## Features

- **Tabs** with independent Back/Forward stacks, restored at launch. Close/Reopen (⇧⌘T), Duplicate, drag to reorder.
- **Navigation log:** every successful folder visit is logged once, with its tab UUID and source.
- **Sidebar:** Special Folders, Favorites, Locations, Config (20 items per section max).
- **File list:** one date column (Added or Modified), sortable, hidden files off by default (⇧⌘.), text size ⌘+/⌘−/⌘0.
- **Drag and drop:** dropping on a sidebar folder or a tab *moves* (⌥ copies); nothing is overwritten
  (Keep Both naming). A folder dropped on Favorites becomes a shortcut (⌘ moves it in). Dropping on the
  file list copies into the current folder. Dragging out of the list writes real file URLs so other apps,
  including Slack, accept them.
- **Favorites:** drop a folder in the gap between two favorites (blue line) to add a shortcut there; right-click to remove.
- **Undo (⌘Z)** for moves, copies, renames, new items and Move to Trash. Copy/Paste with Keep Both / Replace / Skip,
  ⌥⌘V Move Item Here, Quick Look on Space, inline rename, and the open folder refreshes when it changes on disk.
- **History window (⌘Y):** Timeline, Folders, Files Opened, File Operations, Commands. Search, CSV export
  (UTC and local time), Clear, delete entries, "Delete all visits to <folder>". Retention is in Settings.

## Data and privacy

History reveals file names and work patterns, so it stays on this Mac:

`~/Library/Application Support/LocalSearch/localsearch.sqlite` (WAL, schema version 6).

Use History › Clear, the retention setting, or CSV export to manage it. Nothing is sent anywhere.

## Personal configuration

Nothing personal is hard-coded or committed. Special Folders (the top sidebar section) start empty; add one
with right-click › Add to Special Folders on a folder. A brand-new database can also be seeded from
`~/Library/Application Support/LocalSearch/settings.json`:

```json
{ "special_folders": [ { "title": "Notes", "path": "~/some/folder" } ] }
```

That file lives outside the repo. The signing certificate for stable folder permissions is described in
[docs/SIGNING.md](docs/SIGNING.md).

## MCP server

`dist/LocalSearch.app/Contents/MacOS/local-search-mcp` speaks MCP `2025-06-18` over stdio and reads the
same database. Read-only tools for now: `folders_visited`, `navigation_history`, `list_locations`,
`list_directory`.

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | dist/LocalSearch.app/Contents/MacOS/local-search-mcp
```
