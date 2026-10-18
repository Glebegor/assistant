# RightHand

Personal macOS productivity hub that lives in the camera notch. Move the mouse to the
notch and a panel drops down with Pomodoro, a file/screenshot shelf and an AI assistant.

## Run

```sh
scripts/run.sh            # build (debug) and launch build/RightHand.app
scripts/build-app.sh release
```

Requires macOS 14+ and Xcode (or Command Line Tools) with Swift 5.10+.
For editing in VS Code install the **Swift** extension (`swiftlang.swift-vscode`).

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
    Shelf/                    File/screenshot buffer (placeholder)
    Chat/                     AI assistant (placeholder)
```

## Roadmap

- [x] App skeleton: notch panel, menu bar item, settings window
- [x] Pomodoro: focus / short / long breaks, notifications, menu bar countdown
- [ ] Shelf: drag & drop files, auto-capture screenshots, clipboard history
- [ ] AI chat: Claude + ChatGPT (switchable), API keys in Keychain
- [ ] Assistant tools: apps & system control, files, screen & clipboard
- [ ] Action approval: ask before every action, with "always allow" per tool
- [ ] Integrations: Calendar / Reminders / Notes (EventKit), Notion, more
- [ ] Global hotkey, launch at login, Pomodoro statistics
