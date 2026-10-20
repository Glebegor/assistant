# RightHand

Personal macOS productivity hub that lives in the camera notch. Move the mouse to the
notch and a panel drops down with Pomodoro, a file/screenshot shelf and an AI assistant.

## Run

Run `make` to list all commands (`make run`, `make install`, `make release`, …).
They call the scripts below.

```sh
scripts/run.sh            # build (debug) and launch build/RightHand.app
scripts/build-app.sh release
scripts/install.sh        # build (release) and install into /Applications, then launch
```

Requires macOS 14+ and Xcode (or Command Line Tools) with Swift 5.10+.
For editing in VS Code install the **Swift** extension (`swiftlang.swift-vscode`).

## Ellipse, the voice assistant

Ellipse is RightHand's voice assistant. Press **⌥Space** (or the 🎙 button in the notch chat, or
the menu bar item), speak in English, Ukrainian, Czech or Russian, and press it again. The notch
glows while Ellipse listens and works, and the answer is read aloud by the Mac's own voice, so you
can keep working in other windows. The conversation stays in the notch chat.

What Ellipse does:

- **Quick answers**: questions and explanations in a sentence or two.
- **Your Mac**: opens apps, links and files; finds, reads, creates, edits, moves and deletes files;
  runs Terminal commands.
- **Tasks** in Notion and ClickUp: what's due or overdue, what to do next, marking tasks done,
  changing status, priority or due date, adding notes.
- **Gmail and Google Drive** (when connected): finds and summarizes emails and documents, creates
  Google Docs, uploads and downloads files.
- **Planning the day** from open tasks, deadlines and priorities.
- **Memory**: remembers what you ask it to keep, and knows what you wrote in *About me*.

How it behaves: it answers in the language you spoke, in one to three short sentences; it does
the task first and then says what it did; with many results it gives the most important two or
three; it asks one short question when the request is unclear. Anything that changes files, tasks
or runs commands asks for your approval in the notch first.

Speech recognition is Apple's (on the Mac for English and Russian, Apple's free service for
Ukrainian and Czech); speech is made offline by macOS. Settings → Assistant → Ellipse.

## Signing

Local builds are signed with a self-made certificate, "RightHand Local Signing", which
`scripts/setup-signing.sh` creates in your login keychain on the first build. Because every
build has the same signature, macOS keeps the app's permissions (Desktop folder, browser
control, Keychain) after rebuilds. CI builds use an ad-hoc signature.

## Releases

Versions come from commit messages since the last release (`v*` tag):
`Breaking:` → major, `Feature:` / `Enhancement:` → minor, `Feet:` / `Fix:` / `HotFix:` → patch.

```sh
scripts/next-version.sh           # show the next version (empty = nothing to release)
scripts/next-version.sh --notes   # preview the release notes
scripts/release.sh                # merge dev into master and push
scripts/package.sh                # build build/RightHand-<version>.zip locally
```

Pushing to `master` runs `.github/workflows/release.yml`, which builds the app, tags `vX.Y.Z`
and publishes a GitHub release with the zip.

## Languages

The interface is available in English, Ukrainian, Czech and Russian (Settings → General).
Translations are in `scripts/localization/translations.py`; after changing them run
`python3 scripts/localization/generate.py` to update `Support/Localization/*.lproj`.

## Project layout

```
Package.swift                 Swift Package Manager manifest
Support/Info.plist            App bundle metadata (bundle id, no Dock icon)
scripts/                      Build & run scripts (create the .app bundle)
Sources/RightHand/
  App/                        Entry point and AppDelegate (wires everything together)
  Notch/                      Notch window, hover detection, panel UI with tabs
  MenuBar/                    Menu bar icon + menu
  Settings/                   Settings window
  Shared/                     Small reusable helpers and views
  Features/
    Pomodoro/                 Timer logic, settings, view
    Shelf/                    Files, screenshots and clipboard history
    Tasks/                    Notion and ClickUp tasks in the notch
    Integrations/             Notion, ClickUp and Google (Gmail, Drive) for the AI
    Chat/                     AI chat in the notch
    Projects/                 Projects window and the conversation engine
    Tools/                    What the AI can do on the Mac (files, commands, memory)
```

## Roadmap

- [x] App skeleton: notch panel, menu bar item, settings window
- [x] Pomodoro: focus / short / long breaks, notifications, menu bar countdown
- [x] Shelf: drag & drop files, auto-capture screenshots, clipboard history, folders (saved between launches)
- [x] Eye rest: full-screen 20-20-20 break reminders
- [x] Site blocking during Pomodoro focus (Safari, Chrome, Arc, Brave, Edge, Vivaldi)
- [x] AI chat in the notch: Claude + ChatGPT (switchable), uses the same tools as projects, API keys in Keychain
- [x] Projects window: instructions, files, folders, memory, automatic summarizing
- [x] Assistant tools: files anywhere on the Mac (read, write, edit, move, copy, delete to Trash), Terminal commands, opening apps and links
- [x] Action approval: ask before every action, with "always allow" per tool; commands, deletions and anything outside the project folders always ask
- [ ] Assistant tools: screen & clipboard, system control
- [x] Tasks tab: open Notion tasks (yours or unassigned), overdue and high priority first, tick to mark done
- [x] AI tools for Notion, ClickUp, Gmail (read) and Google Drive; ClickUp tasks in the Tasks tab
- [x] "About me" profile that every chat starts with
- [x] Voice: a shortcut (⌥Space) to talk to the AI, a glowing notch with live text and the answer, answers read aloud by the Mac's own voices
- [ ] Integrations: Calendar / Reminders / Notes (EventKit), more
- [ ] Global hotkey, launch at login, Pomodoro statistics
