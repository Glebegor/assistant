import Observation

/// Runs `apply` now and again every time an `@Observable` value it read changes.
/// SwiftUI views do this automatically; AppKit code (like the menu bar item) needs this helper.
@MainActor
func observeChanges(_ apply: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in observeChanges(apply) }
    }
}
