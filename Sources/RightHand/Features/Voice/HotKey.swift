import AppKit
import Carbon.HIToolbox

/// A key combination like ⌥Space. Stored in UserDefaults; registered as a system-wide hotkey,
/// which needs no permission (unlike watching all key presses).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32

    static let defaultVoice = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    static var voice: Shortcut {
        get {
            UserDefaults.standard.data(forKey: VoiceSettings.Key.shortcut)
                .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .defaultVoice
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: VoiceSettings.Key.shortcut) }
    }

    /// From a key press in the shortcut recorder; nil without ⌘, ⌥ or ⌃ (a plain key would type nothing anywhere else).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Combinations macOS already uses (Spotlight ⌘Space, input sources ⌃Space and ⌃⌥Space,
    /// app switching, quitting, …); taking them would break those.
    var isReservedBySystem: Bool {
        let cmd = UInt32(cmdKey), opt = UInt32(optionKey), ctrl = UInt32(controlKey), shift = UInt32(shiftKey)
        let reserved: [(Int, UInt32)] = [
            (kVK_Space, cmd), (kVK_Space, cmd | opt), (kVK_Space, ctrl), (kVK_Space, ctrl | opt), (kVK_Space, ctrl | cmd),
            (kVK_Tab, cmd), (kVK_Tab, cmd | shift), (kVK_ANSI_Q, cmd), (kVK_ANSI_W, cmd), (kVK_ANSI_H, cmd), (kVK_ANSI_M, cmd),
            (kVK_ANSI_C, cmd), (kVK_ANSI_V, cmd), (kVK_ANSI_X, cmd), (kVK_ANSI_Z, cmd), (kVK_ANSI_A, cmd),
            (kVK_ANSI_3, cmd | shift), (kVK_ANSI_4, cmd | shift), (kVK_ANSI_5, cmd | shift), (kVK_Escape, cmd | opt),
        ]
        return reserved.contains { UInt32($0.0) == keyCode && $0.1 == modifiers }
    }

    /// The keys spelled out for people who don't read ⌥: "⌥ Option + Space".
    var spokenName: String {
        var names: [String] = []
        if modifiers & UInt32(controlKey) != 0 { names.append("⌃ Control") }
        if modifiers & UInt32(optionKey) != 0 { names.append("⌥ Option") }
        if modifiers & UInt32(shiftKey) != 0 { names.append("⇧ Shift") }
        if modifiers & UInt32(cmdKey) != 0 { names.append("⌘ Command") }
        return (names + [Self.keyName(keyCode)]).joined(separator: " + ")
    }

    /// "⌃⌥Space".
    var displayName: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
                                      kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                                      kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
                                      kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
        if let name = special[Int(code)] { return name }
        // The character this key types on the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let layout = unsafeBitCast(pointer, to: CFData.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboard in
            UCKeyTranslate(keyboard, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &characters)
        }
        return status == noErr && length > 0 ? String(utf16CodeUnits: characters, count: length).uppercased() : "#\(code)"
    }
}

/// A system-wide hotkey. Pressing it anywhere calls `action` on the main thread.
@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private let id: UInt32
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init(_ shortcut: Shortcut, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.installHandler()
        Self.actions[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x5248_4E44), id: id) // "RHND"
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
    }

    /// False when another app already uses the same combination.
    var isRegistered: Bool { reference != nil }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.actions[id]?() } }
            return noErr
        }, 1, &type, nil, nil)
    }
}
