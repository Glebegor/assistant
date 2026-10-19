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
- [ ] Integrations: Calendar / Reminders / Notes (EventKit), Notion, more
- [ ] Global hotkey, launch at login, Pomodoro statistics
