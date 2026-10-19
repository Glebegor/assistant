import AppKit
import SwiftUI

extension View {
    /// Shift-Return adds a new line where the cursor is (Return still sends), like in most chat apps.
    func shiftReturnAddsNewLine() -> some View {
        onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.shift) else { return .ignored }
            NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
            return .handled
        }
    }
}
