# TodoIt

A tiny, native macOS menubar task app. Live in the menubar; check things off as you do them. Schedule tasks for future days and they stay hidden until their day arrives. A companion `todoit` CLI lets shell scripts (and Claude) add and complete tasks too.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Features

- **Menubar-first.** Click the checklist icon in the menubar to see today's tasks, check them off, or quick-add a new one.
- **Day-scoped scheduling.** Schedule a task for any future date — it won't appear in today's list until that day arrives. Overdue tasks stay visible until you check them off.
- **Main window for the bigger picture.** Sidebar with Today / Upcoming / All Active / Completed. Add, edit, prioritize, and add notes.
- **Live `todoit` CLI.** Anything you (or a script, or Claude) does via the CLI shows up in the menubar immediately — the app watches the data file and reloads.
- **Plain JSON storage.** Tasks live at `~/Library/Application Support/TodoIt/tasks.json` so you can back them up, diff them, or move them between machines.
- **No background daemon.** The menubar app is the daemon; there's no helper process.

## Install

Requires macOS 14+ and the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/jturnbach/todoit.git
cd todoit
./install.sh
```

`install.sh` builds a release `.app` bundle and copies:

- `TodoIt.app` → `/Applications/TodoIt.app`
- `todoit` (CLI) → the first writable directory in your PATH (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, …)

Override the CLI destination with `TODOIT_CLI_DEST=/some/path/todoit ./install.sh`.

Then launch it:

```sh
open -a TodoIt
```

You should see a `☑︎` (checklist) icon appear in your menubar.

### Build without installing

```sh
./build.sh
open build/TodoIt.app
```

## Using the menubar

Click the menubar icon to open the popover:

- **Header.** Today's date and how many open tasks.
- **List.** Today's tasks plus any overdue. Tap a circle to mark a task done. Hover for a delete button.
- **Quick-add.** A text field at the bottom — type and press return to add a task for today.
- **Footer.** "Open TodoIt" reveals the main window (with Dock icon while open). "Quit" exits the app.

## Using the main window

Open it from the menubar's "Open TodoIt" button, or by running `open -a TodoIt` twice.

Sidebar sections:

- **Today** — tasks scheduled for today and earlier (anything not yet completed).
- **Upcoming** — tasks scheduled for a future date.
- **All Active** — every open task, grouped by day.
- **Completed** — everything you've already checked off, newest first.

Double-click any task to edit it. Right-click for a context menu. Toolbar has **New Task** (⌘N).

The editor lets you set:

- Title (required)
- Notes (free text)
- Scheduled date (with **Today** / **Tomorrow** / **+1 Week** shortcuts)
- Priority (Low / Normal / High)

## Using the `todoit` CLI

After `./install.sh`, the `todoit` command is on your PATH. It's the same data the menubar app sees — changes show up instantly.

```sh
# Add a task for today (default)
todoit add "Reply to Sarah's email"

# Add a high-priority task for tomorrow
todoit add "Prep board deck" --tomorrow --priority high

# Schedule something a few days out, with notes
todoit add "Renew passport" --in 14 --notes "Photos are in iCloud"

# Or an exact date
todoit add "Anniversary dinner" --date 2026-06-12 --priority high

# See what's on today's plate (includes overdue)
todoit list

# Other scopes
todoit list --upcoming     # future-dated only
todoit list --all          # everything not yet completed
todoit list --completed    # history

# Complete or delete by ID prefix (the 8-char prefix from `list`)
todoit complete 30ccc704
todoit uncomplete 30ccc704
todoit remove   3a9b13a2

# Where is the data?
todoit path        # → ~/Library/Application Support/TodoIt/tasks.json
```

Run `todoit help` for the full reference.

## Letting Claude add tasks

The CLI is the integration surface. Give Claude shell access (Claude Code, an MCP shell tool, etc.) and it can drop tasks onto your board:

```sh
todoit add "Refactor the auth module" --tomorrow --priority high
todoit add "Read paper on retrieval-augmented generation" --in 3
```

Anything written this way shows up in the menubar within ~150ms thanks to the file watcher.

## Data layout

```
~/Library/Application Support/TodoIt/
├── tasks.json     # source of truth
└── tasks.lock     # advisory flock so app + CLI don't clobber each other
```

`tasks.json` is plain, sorted, pretty-printed JSON — friendly to diff, sync, and back up.

## Architecture

- **`TodoIt`** — SwiftUI `App` with a `MenuBarExtra` for the popover. The main window is an `NSWindow` managed by an `AppDelegate` so the app can flip between `.accessory` (no Dock icon) and `.regular` (visible in Dock and ⌘-Tab) depending on whether the main window is open.
- **`TodoItCore`** — shared library: data models, JSON codec, atomic save, file-based advisory lock.
- **`todoit`** — standalone CLI executable linking `TodoItCore`; reads and writes the same JSON file.
- **Live reload** — the app opens an `O_EVTONLY` file descriptor on `tasks.json` and uses `DispatchSource.makeFileSystemObjectSource` to react to writes/renames. The handler is debounced ~150ms then re-decodes the file and rewires the watch (atomic renames invalidate the old fd).

## Project layout

```
.
├── Package.swift
├── Resources/Info.plist
├── Sources/
│   ├── TodoItCore/       # Models, Paths, Storage
│   ├── TodoIt/           # SwiftUI app + AppKit window manager
│   └── todoit-cli/       # CLI entry point
├── build.sh              # builds TodoIt.app and the todoit binary
└── install.sh            # builds and installs to /Applications + PATH
```

## License

MIT
