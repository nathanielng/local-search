# Local Search

A native macOS file browser in the style of Finder, built for one user and for AI agents.
Its main job: **keep folder navigation history, and keep open tabs (with each tab's Back/Forward
history) across relaunches and reboots.** Agents such as Kiro and Claude can read the history and
sidebar through a bundled MCP server.

Status: in daily use but still changing; many features are awaiting hand testing. See [docs/PLAN.md](docs/PLAN.md) for what is built and what is next.

## Build and run

Needs the macOS 26 SDK from the Command Line Tools (no Xcode). Runs on macOS 14 or later.

```bash
scripts/build-app.sh     # builds dist/LocalSearch.app (signed; see docs/SIGNING.md)
open dist/LocalSearch.app
scripts/test.sh          # unit tests (swift-testing) in .build-test
```

Without the signing certificate from [docs/SIGNING.md](docs/SIGNING.md), each rebuild changes the signature and macOS may ask for folder permissions again.

## App icon

`Resources/AppIcon.svg` is the source; `scripts/make-icon.swift` renders it into `Resources/AppIcon.icns`
(`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift scripts/make-icon.swift`).
`build-app.sh` copies the `.icns` into the app bundle.

## Layout

| Target | Purpose |
|---|---|
| `FinderCore` | SQLite store, tab/navigation state, file operations, history queries. No UI. |
| `LocalSearch` | The SwiftUI app. |
| `local-search-mcp` | MCP server (JSON-RPC over stdio). Works with the app closed. |

## Features

**Browsing**
- **Tabs** with independent Back/Forward stacks, restored at launch. Close/Reopen (⇧⌘T), Duplicate, drag to reorder; optional Vertical Tabs pane.
- **Navigation log:** every successful folder visit is logged once, with its tab UUID and source. Back, Forward, Enclosing Folder and a clock button for Recent Locations.
- **Path bar** with Undo/Redo, a copy button, and a paste button that only accepts text that looks like a path. ⇧⌘G goes to a typed path; ⌘F is Quick Find.
- **Sidebar:** Special Folders, Favorites, Locations (including network servers and Web Locations), Projects and Cloud folders such as OneDrive.
- **File list:** one date column (Added or Modified) with optional grouping, sortable, selectable columns, ls-style colours, optional kind badges, hidden files off by default (⇧⌘.), optional permissions column, text size ⌘+/⌘−/⌘0.
- **Right panel** with Info & Preview, Vertical Tabs and Recent Locations; each pane has a close button, and the Info and Preview sections collapse. Previews recognise about 35 binary formats and show a readable summary instead of noise.

**Working with files**
- **Drag and drop:** dropping on a sidebar folder or a tab *moves* (⌥ copies); nothing is overwritten
  (Keep Both naming). A folder dropped on Favorites becomes a shortcut (⌘ moves it in). Dropping on the
  file list copies into the current folder. Dragging out of the list writes real file URLs so other apps accept them.
- **Undo (⌘Z)** for moves, copies, renames, new items and Move to Trash. Copy/Paste with Keep Both / Replace / Skip,
  ⌥⌘V Move Item Here, Quick Look on Space, inline rename, and the open folder refreshes when it changes on disk.
- **Transfers run in the background** with progress, speed, a queue and Cancel, so the window never freezes.
- **Permissions:** chmod buttons (make executable, 600 for keys, and so on) with an Undo.

**Command panel (⌃`)**
- Pick an action for the current folder or selection, read the exact shell command, edit it if you like, then Run (⌘↩) or Stop (⌘.). Nothing runs until you press Run.
- About 35 actions in `actions.json`: Zip, tar.gz, tar.zst, extract, find and search, largest files, folder sizes, image resize and JPEG conversion, file hashes, and a Git group that appears only inside a repository.
- **Variants** are small preset changes of one action (for example zstd at level 1, 19 or 22) and live in the same JSON. Actions can ask for values, never overwrite existing files, and ask first when they change things. A plain-language "What this does" explanation sits under the command.
- Edit your own copy at `~/Library/Application Support/LocalSearch/actions.json`; a newer bundled version replaces it and keeps a `.bak`.
- Drag the line above the panel to resize it.

**History window (⌘Y):** Timeline, Folders, Files Opened, File Operations, Commands. Search, CSV export
(UTC and local time), Clear, delete entries, "Delete all visits to <folder>". Folders can be ignored so they are never logged.

**Settings (⌘,):** General, History (retention and ignored folders), Previews, Network, Locations, and Shortcuts.

**Keyboard shortcuts:** press `?` in the file list or ⌘/ to see every shortcut. In Settings > Shortcuts you can change any
menu shortcut; only your changes are stored, in `shortcuts.json` next to `settings.json`.

## Data and privacy

History reveals file names and work patterns, so it stays on this Mac:

`~/Library/Application Support/LocalSearch/localsearch.sqlite` (WAL, schema version 6).

Use History › Clear, the retention setting, or CSV export to manage it. Nothing is sent anywhere.

## More documents

- [docs/PLAN.md](docs/PLAN.md): what is built and what is next.
- [docs/TESTING.md](docs/TESTING.md): what has been checked by hand and what has not.
- [docs/NETWORK.md](docs/NETWORK.md) and [docs/SIGNING.md](docs/SIGNING.md).

## Personal configuration

Nothing personal is hard-coded or committed. Special Folders (the top sidebar section) start empty; add one
with right-click › Add to Special Folders on a folder. A brand-new database can also be seeded from
`~/Library/Application Support/LocalSearch/settings.json`:

```json
{ "special_folders": [ { "title": "Notes", "path": "~/some/folder" } ] }
```

`network_locations` (SMB and SSH servers, shown in Locations), Projects and Web Locations are configured in the same file; see [docs/NETWORK.md](docs/NETWORK.md). Edits to it are picked up while the app runs. That file lives outside the repo. The signing certificate for stable folder permissions is described in
[docs/SIGNING.md](docs/SIGNING.md).

## MCP server

`dist/LocalSearch.app/Contents/MacOS/local-search-mcp` speaks MCP `2025-06-18` over stdio and reads the
same database. Read-only tools for now: `folders_visited`, `navigation_history`, `list_locations`,
`list_directory`.

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | dist/LocalSearch.app/Contents/MacOS/local-search-mcp
```
