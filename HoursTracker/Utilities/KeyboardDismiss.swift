import SwiftUI
import UIKit

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Tap-outside dismiss that does **not** steal button/list taps.
final class KeyboardTapDismissInstaller: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardTapDismissInstaller()

    private weak var installedWindow: UIWindow?
    private var recognizer: UITapGestureRecognizer?

    func installIfNeeded() {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else { return }

        if installedWindow === window, recognizer != nil { return }

        if let recognizer, let old = installedWindow {
            old.removeGestureRecognizer(recognizer)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.requiresExclusiveTouchType = false
        tap.delegate = self
        window.addGestureRecognizer(tap)

        recognizer = tap
        installedWindow = window
    }

    @objc private func handleTap() {
        Keyboard.dismiss()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Don't dismiss when the tap is already on a control that needs it
        // (text fields keep focus until user taps elsewhere).
        !(touch.view is UITextField || touch.view is UITextView || touch.view is UISearchBar)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// App-wide keyboard UX:
/// - "Done" button above the keyboard
/// - Interactive scroll-to-dismiss on forms/lists
/// - Tap outside a field dismisses the keyboard
private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.keyboardDone) {
                        Keyboard.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                KeyboardTapDismissInstaller.shared.installIfNeeded()
            }
    }
}

extension View {
    /// Apply on the root app container so every screen gets keyboard dismiss UX.
    func keyboardDismissible() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
