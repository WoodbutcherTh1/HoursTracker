import AppIntents

// MARK: - Widget Interactive Buttons (iOS 17+)

/// The button intents themselves (clock in/out, start/end break) live in
/// `ShiftIntents.swift`, shared with the app so iOS runs them in the app's process
/// without opening it. The widget stays stateless: it never writes sessions itself.

extension WidgetBridge {
    /// Deep links for tapping (non-button) areas of the widget.
    static let deepLinkHome = "hourstracker://tab/home"
    static let deepLinkHistory = "hourstracker://tab/history"
}