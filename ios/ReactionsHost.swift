import UIKit

/// What the host knows about one registered trigger. Deliberately no frame:
/// frames go stale the moment a list scrolls, so they are resolved from the
/// live view at gesture-begin instead (spec §6.5).
private struct TriggerRegistration {
  let viewTag: Int
  var items: [NativeReactionItem]
  var selectedId: String?
  /// Per-trigger override for the "another reaction" plus item; `nil` inherits
  /// the host-wide setting.
  var anotherReaction: Bool?
  /// The custom emoji previously picked through "another reaction", if any.
  var anotherSelected: String?
  /// Per-trigger appearance for the "another reaction" item; `nil` inherits the
  /// host-wide one. Replaces it outright rather than merging into it.
  var anotherAppearance: NativeAnotherReaction?
}

private enum Layout {
  /// Gap between the top of the trigger and the bottom of the picker.
  static let verticalOffset: CGFloat = 8

  /// How far outside the picker the finger may stray and still count as
  /// pointing at a reaction. Moving further clears the selection.
  static let focusTolerance: CGFloat = 12
  static let screenMargin: CGFloat = 12
}

class HybridReactionsHost: HybridReactionsHostSpec {

  // MARK: Registry

  private var registrations: [String: TriggerRegistration] = [:]
  private var triggerIdByTag: [Int: String] = [:]

  // MARK: Callbacks

  private var onSelect: ((String, String?) -> Void)?
  private var onSelectAnother: ((String, String) -> Void)?
  private var onOpen: ((String) -> Void)?
  private var onClose: ((String) -> Void)?

  // MARK: Presentation

  /// Pooled, not rebuilt. Detached between interactions so a scrolling list
  /// never composites the picker, but retained so a long-press never pays
  /// construction on the critical path (spec §6.5).
  private var pickerView: ReactionsPillView?
  private var overlayWindow: UIWindow?

  private var recognizer: UILongPressGestureRecognizer?
  private var recognizerDelegate: RecognizerDelegate?

  private var renderMode: ReactionRenderMode = .auto
  private var anotherReactionEnabled = true
  /// Host-wide appearance for the "another reaction" item; `nil` keeps the
  /// built-in chrome.
  private var anotherReactionAppearance: NativeAnotherReaction?

  /// Owns the hidden text field that summons the system emoji keyboard —
  /// iOS has no standalone emoji picker API, so the keyboard *is* the native
  /// picker.
  private let emojiInput = EmojiInputController()

  // MARK: Active interaction

  /// The rules of the press currently in flight, or nil when none is. Every
  /// question about focus and release goes here; the host only reacts to the
  /// answers. Nil is the whole of "no interaction" — there is no separate
  /// focused index that can outlive it.
  private var interaction: PickerInteraction?
  private var disabledScrollView: UIScrollView?
  private var haptics: UIImpactFeedbackGenerator?

  // MARK: Spec

  var isLiquidGlassSupported: Bool { GlassSupport.isAvailable }

  func activate(
    renderMode: ReactionRenderMode,
    longPressDurationMs: Double,
    anotherReactionEnabled: Bool,
    anotherReactionAppearance: NativeAnotherReaction?
  ) throws {
    let duration = longPressDurationMs
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.renderMode = renderMode
      self.anotherReactionEnabled = anotherReactionEnabled
      self.anotherReactionAppearance = anotherReactionAppearance
      self.installRecognizer(minimumPressDuration: duration / 1000.0)
      self.warmPicker()
    }
  }

  func deactivate() throws {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if let recognizer = self.recognizer {
        recognizer.view?.removeGestureRecognizer(recognizer)
      }
      self.recognizer = nil
      self.recognizerDelegate = nil
      self.emojiInput.dismiss()
      self.cancelInteraction()
      self.pickerView = nil
      self.overlayWindow?.isHidden = true
      self.overlayWindow = nil
    }
  }

  func registerTrigger(
    triggerId: String,
    viewTag: Double,
    items: [NativeReactionItem],
    selectedId: String?,
    anotherReaction: Bool?,
    anotherSelected: String?,
    anotherReactionAppearance: NativeAnotherReaction?
  ) throws {
    let tag = Int(viewTag)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.registrations[triggerId] = TriggerRegistration(
        viewTag: tag, items: items, selectedId: selectedId,
        anotherReaction: anotherReaction, anotherSelected: anotherSelected,
        anotherAppearance: anotherReactionAppearance
      )
      self.triggerIdByTag[tag] = triggerId
    }
  }

  func updateTrigger(
    triggerId: String,
    items: [NativeReactionItem],
    selectedId: String?,
    anotherReaction: Bool?,
    anotherSelected: String?,
    anotherReactionAppearance: NativeAnotherReaction?
  ) throws {
    DispatchQueue.main.async { [weak self] in
      guard let self, var existing = self.registrations[triggerId] else { return }
      existing.items = items
      existing.selectedId = selectedId
      existing.anotherReaction = anotherReaction
      existing.anotherSelected = anotherSelected
      existing.anotherAppearance = anotherReactionAppearance
      self.registrations[triggerId] = existing
    }
  }

  func unregisterTrigger(triggerId: String) throws {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if let removed = self.registrations.removeValue(forKey: triggerId) {
        self.triggerIdByTag.removeValue(forKey: removed.viewTag)
      }
      // A row recycling or scrolling away mid-interaction dismisses without
      // selection rather than leaving a picker anchored to nothing (spec §4.3).
      if self.interaction?.triggerId == triggerId {
        self.cancelInteraction()
      }
    }
  }

  func setOnSelect(callback: @escaping (String, String?) -> Void) throws {
    onSelect = callback
  }

  func setOnSelectAnother(callback: @escaping (String, String) -> Void) throws {
    onSelectAnother = callback
  }

  func setOnOpen(callback: @escaping (String) -> Void) throws {
    onOpen = callback
  }

  func setOnClose(callback: @escaping (String) -> Void) throws {
    onClose = callback
  }

  // MARK: Setup

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
  }

  private func installRecognizer(minimumPressDuration: TimeInterval) {
    guard recognizer == nil, let window = keyWindow() else { return }

    let delegate = RecognizerDelegate()
    let gesture = UILongPressGestureRecognizer(
      target: self, action: #selector(handleLongPress(_:))
    )
    gesture.minimumPressDuration = minimumPressDuration
    gesture.delegate = delegate
    // Until the picker actually opens the touch belongs to whatever is
    // underneath — a drag that starts before the threshold must still scroll
    // (spec §6.4).
    gesture.cancelsTouchesInView = false
    window.addGestureRecognizer(gesture)

    recognizer = gesture
    recognizerDelegate = delegate
  }

  private func warmPicker() {
    guard pickerView == nil else { return }
    // Built once, off the critical path, so the first long-press does not pay
    // construction of the glass container (spec §6.5).
    let picker = ReactionsPillView()
    pickerView = picker
    // Attached hidden right away so the glass materialize animation UIKit
    // plays on first attachment runs invisibly here, not on the first open.
    if let overlay = ensureOverlayWindow() {
      picker.isHidden = true
      overlay.rootViewController?.view.addSubview(picker)
    }
  }

  private func ensureOverlayWindow() -> UIWindow? {
    if let overlayWindow { return overlayWindow }
    guard let scene = keyWindow()?.windowScene else { return nil }

    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.backgroundColor = .clear
    window.rootViewController = UIViewController()
    window.rootViewController?.view.backgroundColor = .clear
    // The overlay is a presentation surface only. Touches keep going to the
    // app's own window, which is where the single recognizer lives, so there
    // is no second responder chain to arbitrate with.
    window.isUserInteractionEnabled = false
    window.isHidden = false

    overlayWindow = window
    return window
  }

  // MARK: Trigger resolution

  /// Walks up from the hit-tested view to the nearest registered trigger.
  /// Cheap (bounded by view depth) and always current, which is what lets the
  /// library keep JS off the scroll path entirely.
  private func trigger(at point: CGPoint, in window: UIWindow) -> (String, UIView)? {
    guard var view = window.hitTest(point, with: nil) else { return nil }
    while true {
      if let triggerId = triggerIdByTag[view.tag], registrations[triggerId] != nil {
        return (triggerId, view)
      }
      guard let parent = view.superview else { return nil }
      view = parent
    }
  }

  private func enclosingScrollView(of view: UIView) -> UIScrollView? {
    var current: UIView? = view
    while let candidate = current {
      if let scrollView = candidate as? UIScrollView { return scrollView }
      current = candidate.superview
    }
    return nil
  }

  // MARK: Gesture

  @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    guard let window = gesture.view as? UIWindow else { return }
    let point = gesture.location(in: window)

    switch gesture.state {
    case .began:
      begin(at: point, in: window)
    case .changed:
      updateFocus(at: point)
    case .ended:
      end()
    case .cancelled, .failed:
      cancelInteraction()
    default:
      break
    }
  }

  private func begin(at point: CGPoint, in window: UIWindow) {
    guard
      let (triggerId, triggerView) = trigger(at: point, in: window),
      let registration = registrations[triggerId],
      !registration.items.isEmpty,
      let picker = pickerView,
      let overlay = ensureOverlayWindow()
    else { return }

    let slots = slots(for: registration)

    // Ownership of the touch is now unambiguous: cancel the enclosing scroll
    // view's pan so opening the picker never scrolls the list (spec §6.4).
    if let scrollView = enclosingScrollView(of: triggerView) {
      scrollView.panGestureRecognizer.isEnabled = false
      disabledScrollView = scrollView
    }

    // The pill matches the surface it floats over, not the system theme —
    // materials, symbol tints, and the divider all resolve through this trait.
    picker.overrideUserInterfaceStyle =
      SurfaceAppearance.isDark(under: triggerView) ? .dark : .light

    // Drawn from the very list that will be hit-tested, in the same order, so
    // the row on screen and the row the rules reason about cannot disagree.
    picker.apply(
      items: slots.map {
        ReactionResolver.renderable(for: $0, renderMode: renderMode)
      },
      selectedId: registration.selectedId,
      separatorAfter: slots.separatorAfter
    )

    // Frame resolved from the live view, not from anything JS measured.
    let triggerFrame = triggerView.convert(triggerView.bounds, to: nil)
    let size = picker.intrinsicContentSize
    var origin = CGPoint(
      x: triggerFrame.midX - size.width / 2,
      y: triggerFrame.minY - size.height - Layout.verticalOffset
    )
    let bounds = overlay.bounds
    origin.x = min(
      max(Layout.screenMargin, origin.x),
      max(Layout.screenMargin, bounds.width - size.width - Layout.screenMargin)
    )
    origin.y = max(Layout.screenMargin, origin.y)
    let pickerFrame = CGRect(origin: origin, size: size)

    // Geometry via bounds and center, never `frame`: prepareForPresentation
    // applies the collapsed scale transform, and assigning `frame` to a
    // transformed view divides the size by the scale — which is exactly the
    // bug where every pill came out ~16% wider than its content, items packed
    // left with dead space on the right. The center accounts for the (0.5, 1)
    // anchor prepareForPresentation sets.
    picker.prepareForPresentation()
    picker.bounds = CGRect(origin: .zero, size: size)
    picker.center = CGPoint(x: pickerFrame.midX, y: pickerFrame.maxY)
    // Attached once and then only hidden/unhidden: re-attaching a glass
    // effect view replays UIKit's frosted "materialize" animation, which is
    // the grey flash on open. A hidden layer is not composited, so the
    // detach-between-interactions GPU saving (spec §6.5) is preserved.
    if picker.superview == nil {
      overlay.rootViewController?.view.addSubview(picker)
    }
    picker.isHidden = false
    picker.animateIn()

    haptics = UIImpactFeedbackGenerator(style: .light)
    // Prepared on open, not on first index change — an unprepared generator
    // has first-fire latency that breaks frame alignment (spec §6.5).
    haptics?.prepare()

    // Everything the rules need, frozen at this instant — `selectedId`
    // included. The user is choosing against the pill just drawn, so that is
    // what the deselect comparison has to be made against; re-reading the
    // registry at release time would compare against something never shown.
    interaction = PickerInteraction(
      triggerId: triggerId,
      slots: slots,
      selectedId: registration.selectedId,
      pickerFrame: pickerFrame,
      tolerance: Layout.focusTolerance,
      geometry: picker
    )

    // Deliberately no initial focus: at this instant the finger is on the row
    // that was pressed, not on a reaction. Focusing here is what made a
    // reaction appear pre-selected the moment the picker opened.
    picker.setFocusedIndex(nil)

    onOpen?(triggerId)
  }

  // MARK: Mapping

  /// The registration flattened into the one list the interaction reasons over.
  private func slots(for registration: TriggerRegistration) -> [Slot] {
    var slots = registration.items.map { item in
      Slot.reaction(
        Reaction(
          id: item.id,
          emoji: item.emoji,
          symbolIos: item.symbolIos,
          symbolAndroid: item.symbolAndroid,
          accessibilityLabel: item.accessibilityLabel
        )
      )
    }

    guard registration.anotherReaction ?? anotherReactionEnabled else {
      return slots
    }
    // The custom pick rides with the plus: both belong to the "another
    // reaction" section, so disabling the feature hides both.
    if let emoji = registration.anotherSelected, !emoji.isEmpty {
      slots.append(.custom(emoji))
    }
    slots.append(
      .another(appearance(registration.anotherAppearance ?? anotherReactionAppearance))
    )
    return slots
  }

  /// Maps the Nitro transport struct onto the interaction's own type. The
  /// generated, C++-backed struct stops here and goes no further in.
  private func appearance(
    _ native: NativeAnotherReaction?
  ) -> AnotherReactionAppearance? {
    guard let native else { return nil }
    return AnotherReactionAppearance(
      symbolIos: native.symbolIos,
      symbolAndroid: native.symbolAndroid,
      emoji: native.emoji,
      badge: native.badge,
      accessibilityLabel: native.accessibilityLabel
    )
  }

  // MARK: Focus and release

  private func updateFocus(at point: CGPoint) {
    guard let change = interaction?.focus(at: point) else { return }
    switch change {
    case .unchanged:
      break
    case .moved(let index):
      pickerView?.setFocusedIndex(index)
      // Fired from the same code path that detects the change, so the haptic
      // and the visual land together (spec §4.4).
      haptics?.impactOccurred()
      haptics?.prepare()
    case .cleared:
      pickerView?.setFocusedIndex(nil)
    }
  }

  private func end() {
    guard let interaction else { return }
    let triggerId = interaction.triggerId
    let outcome = interaction.release()

    // Selection is reported at touch-up; teardown waits for the animation
    // (spec §4.3).
    switch outcome {
    case .select(let reactionId, _):
      onSelect?(triggerId, reactionId)
    case .deselect:
      onSelect?(triggerId, nil)
    case .another, .cancel:
      // Releasing on the plus is not a selection: the celebration still plays,
      // but the interaction hands over to the system emoji keyboard below.
      break
    }

    finish(celebratingAt: outcome.celebratedIndex)

    if case .another = outcome {
      emojiInput.present(over: keyWindow()) { [weak self] emoji in
        self?.onSelectAnother?(triggerId, emoji)
      }
    }
  }

  /// A press that never released: the gesture was cancelled, the row was
  /// recycled out from under it, or the host was deactivated. There is no
  /// outcome because there was no release — the interaction is simply dropped.
  private func cancelInteraction() {
    guard interaction != nil else { return }
    finish(celebratingAt: nil)
  }

  private func finish(celebratingAt index: Int?) {
    guard let triggerId = interaction?.triggerId else { return }
    interaction = nil

    disabledScrollView?.panGestureRecognizer.isEnabled = true
    disabledScrollView = nil

    let picker = pickerView
    // Teardown is bound to animation-end, not touch-up: onSelect has already
    // fired above, and detaching now would cut the collapse off mid-flight
    // (spec §4.3). Detached, never deallocated: detaching buys the whole GPU
    // saving, deallocating would only re-buy construction cost (spec §6.5).
    let teardown = {
      // Hidden, not detached: re-attaching a glass effect view replays the
      // frosted materialize animation. Hidden layers are not composited, so
      // the GPU saving of spec §6.5 is intact.
      picker?.isHidden = true
      picker?.resetAfterDismissal()
    }

    if let index {
      // A firmer confirm than the per-item tick; the generator is prepared, so
      // it lands with the pop.
      haptics?.impactOccurred(intensity: 1.0)
      picker?.animateSelection(at: index, completion: teardown)
    } else {
      picker?.setFocusedIndex(nil)
      picker?.animateOut(completion: teardown)
    }

    haptics = nil
    onClose?(triggerId)
  }
}

// MARK: - Outcome

private extension Outcome {
  /// The slot the celebration plays on. It plays whether the release committed
  /// a new selection, cleared the existing one, or opened the emoji picker —
  /// either way the user chose that slot. `.cancel` chose nothing, and the
  /// enum is what makes "celebrate at no index" unrepresentable.
  var celebratedIndex: Int? {
    switch self {
    case .select(_, let index), .deselect(let index), .another(let index):
      return index
    case .cancel:
      return nil
    }
  }
}

// MARK: - Recognizer delegate

/// Kept as a separate object so the arbitration rules are stated in one place.
private final class RecognizerDelegate: NSObject, UIGestureRecognizerDelegate {

  /// Recognise alongside everything, including scroll view pans and
  /// react-native-gesture-handler's recognizers. The long-press only claims
  /// the touch once it actually fires; until then the list scrolls normally
  /// (spec §6.4).
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    true
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRequireFailureOf other: UIGestureRecognizer
  ) -> Bool {
    false
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldBeRequiredToFailBy other: UIGestureRecognizer
  ) -> Bool {
    false
  }
}
