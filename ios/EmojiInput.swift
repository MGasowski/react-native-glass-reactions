import UIKit

/// iOS has no standalone emoji picker API — the system emoji keyboard *is* the
/// native picker. This field summons it by overriding `textInputMode` to the
/// emoji input mode, the sanctioned way to ask for a specific keyboard.
private final class EmojiTextField: UITextField {

  /// A non-nil identifier is what makes UIKit honour a per-field
  /// `textInputMode` instead of restoring the user's last-used keyboard.
  override var textInputContextIdentifier: String? { "glass-reactions-emoji" }

  override var textInputMode: UITextInputMode? {
    UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
      ?? super.textInputMode
  }
}

/// Presents the hidden field, waits for the first emoji, and cleans up. One
/// instance lives on the host; a second present dismisses the first.
final class EmojiInputController: NSObject, UITextFieldDelegate {

  private var field: EmojiTextField?
  private var onPick: ((String) -> Void)?

  /// The completion fires at most once, with a single emoji grapheme. Ending
  /// editing without typing one — Close, or the keyboard being dismissed by
  /// the app — cleans up silently.
  func present(over window: UIWindow?, onPick: @escaping (String) -> Void) {
    guard let window else { return }
    dismiss()
    self.onPick = onPick

    let field = EmojiTextField(frame: .zero)
    field.delegate = self
    field.autocorrectionType = .no
    field.spellCheckingType = .no
    // Hidden fields cannot become first responder; a zero-alpha one can.
    field.alpha = 0
    field.addTarget(self, action: #selector(textChanged), for: .editingChanged)

    // The keyboard has no visible field to dismiss from, so the accessory bar
    // is the only escape hatch.
    let toolbar = UIToolbar()
    toolbar.items = [
      UIBarButtonItem(systemItem: .flexibleSpace),
      UIBarButtonItem(
        barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
      ),
    ]
    toolbar.sizeToFit()
    field.inputAccessoryView = toolbar

    window.addSubview(field)
    self.field = field
    field.becomeFirstResponder()
  }

  func dismiss() {
    onPick = nil
    let field = self.field
    self.field = nil
    field?.resignFirstResponder()
    field?.removeFromSuperview()
  }

  @objc private func closeTapped() {
    dismiss()
  }

  @objc private func textChanged(_ sender: UITextField) {
    guard let text = sender.text, let emoji = Self.firstEmoji(in: text) else {
      sender.text = nil
      return
    }
    let pick = onPick
    dismiss()
    pick?(emoji)
  }

  func textFieldDidEndEditing(_ textField: UITextField) {
    // Dismissed by the system (app backgrounded, another responder) without a
    // pick — tear down rather than leaving an orphaned field in the window.
    dismiss()
  }

  /// Filters what the keyboard delivers down to an actual emoji: with no emoji
  /// keyboard installed the field falls back to text input, and plain
  /// characters must not be reported as reactions. ASCII is excluded because
  /// digits and symbols like `#` report `isEmoji` for keycap sequences.
  static func firstEmoji(in text: String) -> String? {
    text.first { character in
      guard !character.isASCII else { return false }
      return character.unicodeScalars.contains {
        $0.properties.isEmojiPresentation || $0.properties.isEmojiModifierBase
      } || character.unicodeScalars.first?.properties.isEmoji == true
    }
    .map(String.init)
  }
}
