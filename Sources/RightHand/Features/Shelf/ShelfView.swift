import SwiftUI

/// Shelf tab: a temporary buffer for files and screenshots (next milestone).
struct ShelfView: View {
    var body: some View {
        PlaceholderView(
            systemImage: "tray.full",
            title: "Shelf",
            message: "Drop files and screenshots here to keep them at hand."
        )
    }
}
