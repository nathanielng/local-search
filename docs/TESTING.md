# Manual test log

Scratch setup: `mkdir -p ~/Desktop/ls-test/{a,b} && cd ~/Desktop/ls-test && echo one > a/f.txt && echo two > b/f.txt && echo hi > note.md`

Unit tests: `scripts/test.sh` (29 tests). Everything below is checked by hand in the running app by the
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

## Not yet tested by hand

- Drag a file out of the list into Slack or a browser upload field (the main reason for `AppKitDragFix`)
- ⌥-drag to copy, in the list and onto sidebar rows or tabs
- Dropping a file or folder onto a tab; dragging tabs to reorder
- Dropping a folder on the middle of a Favorites row (should move it in)
- Dropping a file on a Favorites or Locations row
- ⌥⌘V Move Item Here
- History window (⌘Y): tabs, search, CSV export, delete, Clear; Settings retention
- Redo, Show in Finder (⌥⌘R), ⌘⌫ Move to Trash from the menu
- Right-click › Open in New Tab / Show in Finder in the sidebar

## Bugs found and fixed during testing

1. Dragging in the file list only rubber-band selected rows. The table's private mouse tracking hides drag events from event monitors; the drag is now started by `AppKitDragFix` once the pointer moves 4 pt.
2. A first version of that fix took every click and replayed it. That broke double-click and left the table ignoring the mouse for a few seconds. Plain clicks are no longer consumed.
3. Folders in the file list were not drop targets; sidebar rows left gaps that didn't accept drops.
4. A stale blue drop line stayed after releasing, because SwiftUI can skip the "exited" callback. The highlight is now shared and cleared when the button is up.
5. A failed rename was easy to miss; it now shows an alert with the reason.
6. A rebuilt app has a new ad-hoc signature, so macOS may block folder access again. The app now says so when a folder can't be read.
