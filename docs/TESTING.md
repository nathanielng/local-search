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

## Not yet tested by hand

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
