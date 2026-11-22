# Manual test log

Scratch setup: `mkdir -p ~/Desktop/ls-test/{a,b} && cd ~/Desktop/ls-test && echo one > a/f.txt && echo two > b/f.txt && echo hi > note.md`

Unit tests: `scripts/test.sh` (38 tests). Everything below is checked by hand in the running app by the
owner (trackpad with 3-finger drag). Last full pass: 22 Nov 2026.

## Verified

| Area | What was checked |
|---|---|
| Tabs and persistence | Open, Back/Forward, new tab, close, Reopen (⇧⌘T), quit and relaunch restores tabs and stacks; History › Folders logs each visit once |
| Rename | Return starts inline edit with the stem selected; Esc cancels; case-only rename; a name clash shows an alert with the reason |
| New items | ⌥⌘N / ⇧⌘N create and open for renaming; New Folder / New Text File appear in the right-click menu on empty space and on a selection |
| Copy and paste | ⌘C, ⌘V, conflict dialog (Keep Both / Replace / Skip), Copy Paths, Copy File Text for AI (skips secrets and binaries) |
| Quick Look | Space opens the panel (preview comes from the installed MarkdownQL plugin for `.md`) |
| Clicking | Single click highlights on press; double-click opens folders; lag is slight |
| Drag a file onto a folder row in the list | Moves it in |
| Undo (⌘Z) | Reverses the drag-move |
| Favorites: add by drag | A folder dropped on the Favorites header or the top/bottom edge of a row becomes a shortcut at that position; the blue gap line appears and clears after release |
| Favorites: remove | Right-click › Remove from Favorites |
| Auto-refresh | `mv a/memo.md .` in a terminal updates the open folder by itself |
| Drag out to another app | `memo.md` dragged into WhatsApp is delivered (Slack not tried) |
| ⌥-drag | Copies instead of moving |
| Drop on a Favorites row | `memo.md` dropped on Documents moves in; ⌘Z undoes it |
| Folder on the middle of a Favorites row | Moves into that favorite |
| ⌥⌘V Move Item Here | Moves the copied files into the current folder |
| History window (⌘Y) | Tabs, search, export, delete and Clear work |
| Reorder sidebar rows | Dragging Favorites and Special Folders rows reorders them (blue bar shows where); the order survives relaunch; plain clicks on rows still navigate; folder drops on favorites still work |
| Quick Find (⌘F) | Finds folders and files (`memo`, `memo.md`), instant local matches then Spotlight, ↑/↓ choose, Esc closes |
| Tab reorder | Dragging a tab to the front and, via the end-of-row target, to the very end; a bar shows where it lands |
| Redo (⇧⌘Z) | Move: ⌘Z then ⇧⌘Z re-applies it; copy: ⌘Z trashes the copy and ⇧⌘Z restores it; rename; menu shows "Redo <action>" |
| History symbols | 📋 copy, ➡️ move, 🗑️ trash, ✏️ rename, ➕ create shown in the History window |
- Network: SMB connect and open `/Volumes/nat` work; Disconnect is asynchronous (window stays usable) and closes the tab on that volume (tested with several tabs, including tabs on different folders of the same volume: all close); SSH mount of the Pi works
- Sidebar: draggable divider; width is kept across collapse/expand and across quitting and relaunching; collapse button and View › Hide Sidebar
- SSH: connecting to an unreachable host gives up after about 25 seconds and the yellow bar shows the reason
- Network: Add SSH Location menu; Remove from Locations; Remove from Special Folders
- Dropping a file onto a tab; the signed build keeps folder permissions across rebuilds (no re-grant needed)
- Slack drag-out skipped (not installed); WhatsApp works, Slack should too
- Column headers: click to sort, click again to reverse, chevron shows direction; the arrow button at the top right removes all sorting
- Group by Date (⌃⌘G, View menu): headers show when sorted by Added or Modified

## Not yet tested by hand

- Kind badges (confirmed by the user; tag button in the path bar, ⌃⌘B, View menu): strip with a count per kind; click to filter, click again or "Show all" to clear (checked by the assistant on Desktop); the filter applies only in the tab and folder where it was set

- Click a column header to sort by it and click again to reverse (checked by the assistant on Size); the arrow button at the top right removes all sorting

- Multi-row tabs (up to 3 rows, then scrolls): wrapping checked by the assistant with 18 tabs; reordering and drop targets across rows need your test
- Group by Date (⌃⌘G, View menu): headers appear in the list when sorted by date; headers can't be selected, dragged or opened

- Quick Find magnifier button; partial-name search (`mo.md` shows memo.md with the match highlighted); SMB 15-second timeout. Network folders, original item: the Locations section lists mounted external/network volumes (right-click › Eject / Disconnect); a configured SMB server is dimmed until connected, clicking mounts it (sign-in dialog if needed) and opens it; Disconnect unmounts. SSH locations need FUSE-T + sshfs and key login (docs/NETWORK.md)
- Quick Find: the matched part of a file name is shown in bold accent colour (new), and the "No matches" hint about macOS privacy; ⌘↩ (new tab / open file); revealing a file selects it in its folder
- Special folders: right-click a folder in the list › Add to Special Folders; right-click a Special Folders row › Remove (new). A new database seeds them from settings.json
- Dropping a file onto a tab (moves into the tab's folder)
- Dragging into Slack specifically; a browser upload field
- Dropping a file on a Locations or Config row
- Settings retention; Show in Finder (⌥⌘R); ⌘⌫ Move to Trash from the menu
- Right-click › Open in New Tab / Show in Finder in the sidebar

## Known gaps

- Locations and Config rows are not reorderable (they come from fixed lists / settings.json, not the database).

## Bugs found and fixed during testing

1. Dragging in the file list only rubber-band selected rows. The table's private mouse tracking hides drag events from event monitors; the drag is now started by `AppKitDragFix` once the pointer moves 4 pt.
2. A first version of that fix took every click and replayed it. That broke double-click and left the table ignoring the mouse for a few seconds. Plain clicks are no longer consumed.
3. Folders in the file list were not drop targets; sidebar rows left gaps that didn't accept drops.
4. A stale blue drop line stayed after releasing, because SwiftUI can skip the "exited" callback. The highlight is now shared and cleared when the button is up.
5. A failed rename was easy to miss; it now shows an alert with the reason.
6. A rebuilt app has a new ad-hoc signature, so macOS may block folder access again. The app now says so when a folder can't be read.
7. Quick Find "didn't find memo.md" right after a rebuild: macOS had withdrawn the app's Desktop permission, and Spotlight hides files in protected folders from an app without it (TCC logged the new grant at the moment it was answered). Not a search bug. A stable signing identity would stop this.

- File colours (⌃⌘K and View menu toggle, confirmed by the user): ls-style name colours
- Date column switcher (calendar button in the path bar, View > Date Column): Added or Modified / Modified / Added changes the column title, the dates shown, the sort and Group by Date; not yet tested by hand (the assistant checked the Modified header live)
- Right panel, stage 1 (View > Show Vertical Tabs ⌃⌘V, Show Recent Locations ⌃⌘R; draggable remembered width): Vertical Tabs with filter, select and close; Recent Locations in tight bands with an × on each row, Open in New Tab and Remove from Recent (hides the folder, keeps history); not yet tested by hand (the assistant saw both panes render with live data)
- Recent Locations, stage 2: Folders / Files Opened switch (click a file to open it and log the open; × deletes that file's recorded opens; context menu Show in Finder, Open Containing Folder) and files dropped on a folder row (moves; hold ⌥ to copy); not yet tested by hand (the assistant saw the Files Opened list render; drops untested)
- Right panel splitter between Vertical Tabs and Recent Locations: drag to resize, height remembered (confirmed by the user)
- Info & Preview (View > Show Info & Preview, ⌥⌘I; Info section collapsible; third pane with its own draggable height): Info for the selected item or the open folder (kind, size, items, dimensions, dates, last opened, permissions); previews for text and code (first 8 KB checked for binary, capped at 64 KB, over 1 MB needs a click), Markdown (headings, bullets, code, rules, inline styling) and images (ImageIO thumbnail); likely secrets withheld until Show Anyway; not yet tested by hand (the assistant saw Info for a file and a folder, a rendered Markdown file, an image preview, and a withheld env file)
- Remaining previews in the Info & Preview pane: JSON (pretty, sorted keys, up to 512 KB), CSV/TSV (table, 50 rows by 20 columns, quoted fields), SVG (drawn through an <img>, so scripts never run), HTML (JavaScript off, http/https blocked, shown at 50%), zip, tar and tar.gz (first 200 entries, listing tool killed after 3 s) and Finder aliases (shows the target); not yet tested by hand (the assistant checked one of each in the running app). Also fixed: after a relaunch the pane showed "No information" because a restored selection held a bare file name.
- Projects sidebar section (between Special Folders and Favorites; stored in the local settings.json `projects`, never in the repo; up to 20; context menu Remove from Projects; file list context menu Add to Projects; drop a folder on the header to add; drop files on a row to move them in; drag to reorder; dimmed when the folder is missing): not yet tested by hand (the assistant saw the section with dimmed missing folder; reorder by drag and the add/remove menus are covered by unit tests only)
- Cloud (OneDrive only): the sidebar Cloud section lists folders found under ~/Library/CloudStorage (plus any added with Go > Add OneDrive Folder…, stored in the local settings.json `onedrive_folders`), titled "OneDrive" or "OneDrive – Name", with a green dot while the OneDrive app is running (checked by bundle id; it does not mean synced); manual folders have Remove from Cloud; hidden when there are none; not yet tested by hand (the assistant saw the section and the running dot)
- Web Locations (https:// only): sidebar section from the local settings.json `web_locations` (title, url, notes, symbol); click opens the default browser (↗); the first 10 show, then All N Web Locations…; searchable window (Go > Web Locations…, ⇧⌘L, magnifier on the header; every word must match title, address or notes); Go > Add Web Location… dialog (prefills a link from the clipboard); context menu Open, Copy Address, Remove; http:// and s3:// entries are ignored for now; not yet tested by hand (the assistant saw the sidebar rows and the window list; typing in the search box and clicking a link were not tried)
- Settings (⌘,): General tab (text size, date column, show hidden files, file colours, Kind badges, Group by Date; the same switches as the View menu) and History tab (keep history for; Ignored folders list with Add Folder… and Remove). An ignored folder and its subfolders are no longer recorded (visits and file opens) and drop out of Recent Locations at once; when adding one you can also delete the history already recorded for it. The list is stored in the local database (kv `ignored_folders`). Not yet tested by hand (the assistant saw both tabs render; the Add Folder dialog was not driven)
- Live settings.json: the sidebar lists (network locations, Projects, Cloud, Web Locations) reload when the file changes on disk, whether an editor replaces it or writes it in place; a half-saved or malformed file keeps the last good values and shows a warning, which clears when the file is valid again (the assistant checked all three live with a temporary change)
- Settings > Locations tab: Projects (add folders, remove, move up and down), Web Locations (filter, add, remove, count), OneDrive (found automatically or added by hand, add and remove manual ones), Show settings.json in Finder, Reload Now; not yet tested by hand (the assistant saw the tab render; the add dialogs and buttons were not driven)
- Command panel (⌃`, View > Show Command Panel): grouped action badges that fit the selection (All N shows the rest with the reason on hover), click fills the exact editable command, nothing runs until Run (⌘↩), Stop (⌘.) ends the whole process tree, What this does lists each part, {{ask:}} fields, confirm prompt, find/grep results clickable, new files selected when a run ends, every run recorded in History > Commands. 22 default actions are copied to ~/Library/Application Support/LocalSearch/actions.json on first launch (a newer bundled `version` replaces it and keeps actions.json.bak). The assistant ran Folder sizes live (command filled, output streamed, exit 0 logged); not yet tested by hand: Stop, ask fields, confirm, clickable results, multi-select actions, editing actions.json. No Cloud, S3 or Local AI actions yet (they need `requires` features that aren't built).
