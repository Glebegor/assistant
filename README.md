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
    Chat/                     AI assistant (placeholder)
```

## Roadmap

- [x] App skeleton: notch panel, menu bar item, settings window
- [x] Pomodoro: focus / short / long breaks, notifications, menu bar countdown
- [x] Shelf: drag & drop files, auto-capture screenshots, clipboard history, folders (saved between launches)
- [x] Eye rest: full-screen 20-20-20 break reminders
- [x] Site blocking during Pomodoro focus (Safari, Chrome, Arc, Brave, Edge, Vivaldi)
- [ ] AI chat: Claude + ChatGPT (switchable), API keys in Keychain
- [ ] Assistant tools: apps & system control, files, screen & clipboard
- [ ] Action approval: ask before every action, with "always allow" per tool
- [ ] Integrations: Calendar / Reminders / Notes (EventKit), Notion, more
- [ ] Global hotkey, launch at login, Pomodoro statistics
