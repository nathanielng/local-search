# Local Search: notes for Claude

A native macOS file browser (SwiftUI + AppKit, Swift 6 strict concurrency, macOS 14+) for one user and for AI agents. See README.md for features, docs/PLAN.md for what is built and next, docs/TESTING.md for what has and has not been hand-tested.

## Build, test, run
- `scripts/build-app.sh` builds `dist/LocalSearch.app` (signed with the local "LocalSearch Dev" certificate, see docs/SIGNING.md). Command Line Tools only, no Xcode.
- `scripts/test.sh` runs the swift-testing suites (build dir `.build-test`). Run it before saying anything is done.
- Relaunch: `pkill -x LocalSearch; sleep 2; open dist/LocalSearch.app`. Defaults domain: `dev.localsearch.LocalSearch`.
- Targets: `FinderCore` (no UI: SQLite store, actions engine, shortcuts, file ops), `LocalSearch` (the app), `local-search-mcp` (stdio MCP server, works with the app closed), `FinderCoreTests`.

## Privacy rules (strict)
- Nothing personal is ever hard-coded or committed: no real folder paths, home-directory paths, network host names, ssh aliases, share names, cloud account names, project names, web locations, email addresses or ignored-folder names. Not in code, docs, tests, examples, screenshots or commit messages.
- Those values live only in the local SQLite database or `~/Library/Application Support/LocalSearch/` (`settings.json`, `shortcuts.json`, `actions.json`). Tests and docs use invented placeholders (`~/some/folder`, `example.invalid`).
- Only the bundled `Resources/actions.json` is tracked, and it must stay free of names, paths, accounts and emails. The user's installed copy is not tracked.
- Before every commit and push: `git add -A`, then `python3 ~/.claude/skills/pii-check/pii-check.py | grep Match | grep -v "@"` and scan `git diff --cached` for personal strings. Known false positives: Swift `@attributes`, the words secret/token/password/API_KEY in preview and secret-detection code and tests, "auth" from "author" in the git log action, generic `~/`, random-number constants in test image generators.

## Workflow
- The user hand-tests each feature, then says "commit and push". Do not commit or push until told.
- Commit messages end with: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Record what was verified and what was not in docs/TESTING.md (be honest about "not hand-tested"), and plan status in docs/PLAN.md.
- Keep explanations in plain language; the user is not a Swift specialist.

## Design facts worth knowing
- State: SQLite WAL (`kv`, `nav_history`, `file_opens`, `file_ops`, `command_runs`, ...). `settings.json` is read-modify-write through `SettingsFile`; `FolderWatcher` reloads it live. Display preferences use `@AppStorage`; values the MCP server also needs go in `kv`.
- Actions (`FinderCore/Actions.swift`, `Resources/actions.json`): tokens `{{selection}} {{file}} {{stem}} {{ext}} {{folder}} {{out:Name}} {{ask:Label=default}}`; fields needs/extensions/each/tool/requires/match/confirm/notInHome/results/explain/variants/baseLabel. `{{out:}}` never overwrites. Bump the bundled `version` when the file changes: the installer replaces the user's copy only when the bundled version is higher and keeps `actions.json.bak`. `requires: ["git"]` is satisfied when `.git` exists here or above. A test syntax-checks (`zsh -n`) every action and variant.
- Shortcuts: one catalog in `FinderCore/Shortcuts.swift`; menus use `.shortcut("id")`, which reads `ShortcutStore` (user overrides from `shortcuts.json`). A test fails on clashes within a scope. Only App and Command panel scopes are rebindable.
- Table redraws need `.id(...)` when columns or colours change. File copies use `copyfile(3)` with a status callback (APFS clones report full size at once). Child processes are killed as a tree.
- SwiftUI gotcha found here: a child view given a changing value as a plain property did not update; applying the value (such as a height) in the parent worked.

## Live UI testing on this machine
- The terminal steals focus and background windows give stale screenshots. Raise the app first (`osascript` activate / AXRaise), find the window with `CGWindowListCopyWindowInfo`, and capture with `screencapture -x -o -l <windowID>`.
- Synthetic clicks and keystrokes are unreliable; keep helper tools outside the repo (a temp folder). Leave anything unconfirmed as "to hand test" in docs/TESTING.md.
- Restore any defaults changed for a test (`defaults delete dev.localsearch.LocalSearch <key>`) and delete test files you created in Application Support.
