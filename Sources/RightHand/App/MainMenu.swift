import AppKit

/// The app's menus. RightHand shows no menu bar, but macOS still sends ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z
/// through the Edit menu, so without one copy and paste don't work in text fields.
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()

        let app = NSMenu(title: "RightHand")
        app.addItem(withTitle: "Quit RightHand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(submenu: app)

        let edit = NSMenu(title: "Edit")
        for shortcut in EditShortcut.all {
            let item = edit.addItem(withTitle: shortcut.title, action: shortcut.action, keyEquivalent: shortcut.key)
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(submenu: edit)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(submenu: window)

        return menu
    }
}

/// The standard text editing shortcuts.
struct EditShortcut {
    let title: String
    let action: Selector
    let key: String
    var modifiers: NSEvent.ModifierFlags = .command

    static let all: [EditShortcut] = [
        EditShortcut(title: "Undo", action: Selector(("undo:")), key: "z"),
        EditShortcut(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
        EditShortcut(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"),
        EditShortcut(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"),
        EditShortcut(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"),
        EditShortcut(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a"),
    ]

    /// The shortcut for a key press, if it is one of these.
    static func matching(_ event: NSEvent) -> EditShortcut? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        return all.first { $0.key == key && $0.modifiers == modifiers }
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
