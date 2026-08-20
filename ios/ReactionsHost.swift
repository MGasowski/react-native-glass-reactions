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

  /// Owns the hidden text field that summons the system emoji keyboard —
  /// iOS has no standalone emoji picker API, so the keyboard *is* the native
  /// picker.
  private let emojiInput = EmojiInputController()

  // MARK: Active interaction

  private var activeTriggerId: String?
  private var activeItems: [NativeReactionItem] = []
  /// Whether the current interaction shows the trailing plus item. The plus
  /// occupies a slot after `activeItems`, so hit-testing counts it while
  /// selection reporting does not.
  private var activeShowsPlus = false
  private var activePickerFrame: CGRect = .zero
  private var focusedIndex: Int?
  private var disabledScrollView: UIScrollView?
  private var haptics: UIImpactFeedbackGenerator?

  // MARK: Spec

  var isLiquidGlassSupported: Bool { GlassSupport.isAvailable }

  func activate(
    renderMode: ReactionRenderMode,
    longPressDurationMs: Double,
    anotherReactionEnabled: Bool
  ) throws {
    let duration = longPressDurationMs
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.renderMode = renderMode
      self.anotherReactionEnabled = anotherReactionEnabled
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
      self.dismiss(selected: nil, cancelled: true)
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
    anotherSelected: String?
  ) throws {
    let tag = Int(viewTag)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.registrations[triggerId] = TriggerRegistration(
        viewTag: tag, items: items, selectedId: selectedId,
        anotherReaction: anotherReaction, anotherSelected: anotherSelected
      )
      self.triggerIdByTag[tag] = triggerId
    }
  }

  func updateTrigger(
    triggerId: String,
    items: [NativeReactionItem],
    selectedId: String?,
    anotherReaction: Bool?,
    anotherSelected: String?
  ) throws {
    DispatchQueue.main.async { [weak self] in
      guard let self, var existing = self.registrations[triggerId] else { return }
      existing.items = items
      existing.selectedId = selectedId
      existing.anotherReaction = anotherReaction
      existing.anotherSelected = anotherSelected
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
      if self.activeTriggerId == triggerId {
        self.dismiss(selected: nil, cancelled: true)
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
      dismiss(selected: nil, cancelled: true)
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

    activeTriggerId = triggerId
    activeShowsPlus = registration.anotherReaction ?? anotherReactionEnabled

    // The custom pick rides with the plus: both belong to the "another
    // reaction" section, so disabling the feature hides both.
    var selectable = registration.items
    if activeShowsPlus, let emoji = registration.anotherSelected, !emoji.isEmpty {
      selectable.append(NativeReactionItem(
        id: emoji, emoji: emoji, symbolIos: nil, symbolAndroid: nil,
        accessibilityLabel: emoji
      ))
    }
    activeItems = selectable

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

    var renderables = ReactionResolver.resolve(
      registration.items, renderMode: renderMode
    )
    if activeShowsPlus {
      if let emoji = registration.anotherSelected, !emoji.isEmpty {
        renderables.append(ReactionResolver.customRenderable(emoji: emoji))
      }
      renderables.append(ReactionResolver.anotherReactionRenderable())
    }
    // Divider between the consumer's reactions and the "another reaction"
    // section, drawn only when both sides exist.
    let separatorAfter: Int? =
      activeShowsPlus && !registration.items.isEmpty
        ? registration.items.count : nil
    picker.apply(
      items: renderables,
      selectedId: registration.selectedId,
      separatorAfter: separatorAfter
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

    activePickerFrame = CGRect(origin: origin, size: size)
    // Geometry via bounds and center, never `frame`: prepareForPresentation
    // applies the collapsed scale transform, and assigning `frame` to a
    // transformed view divides the size by the scale — which is exactly the
    // bug where every pill came out ~16% wider than its content, items packed
    // left with dead space on the right. The center accounts for the (0.5, 1)
    // anchor prepareForPresentation sets.
    picker.prepareForPresentation()
    picker.bounds = CGRect(origin: .zero, size: size)
    picker.center = CGPoint(
      x: activePickerFrame.midX, y: activePickerFrame.maxY
    )
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

    // Deliberately no initial focus: at this instant the finger is on the row
    // that was pressed, not on a reaction. Focusing here is what made a
    // reaction appear pre-selected the moment the picker opened.
    focusedIndex = nil
    pickerView?.setFocusedIndex(nil)

    onOpen?(triggerId)
  }

  private func index(at point: CGPoint) -> Int? {
    // Just enough tolerance to stop the selection flickering at the edge, not
    // enough to keep selecting from well outside the picker. The press that
    // opens the picker lands on the row below it, so generous slack here means
    // a reaction is selected before the finger has gone anywhere near one.
    let hitArea = activePickerFrame.insetBy(dx: 0, dy: -Layout.focusTolerance)
    guard hitArea.contains(point) else { return nil }

    // The pill owns the slot geometry: slots are not uniform once the section
    // separator inserts its extra width, so a plain stride would drift.
    return pickerView?.slotIndex(atLocalX: point.x - activePickerFrame.minX)
  }

  private func updateFocus(at point: CGPoint) {
    guard activeTriggerId != nil else { return }
    let next = index(at: point)
    guard next != focusedIndex else { return }
    focusedIndex = next
    pickerView?.setFocusedIndex(next)
    if next != nil {
      // Fired from the same code path that detects the change, so the haptic
      // and the visual land together (spec §4.4).
      haptics?.impactOccurred()
      haptics?.prepare()
    }
  }

  private func end() {
    guard let triggerId = activeTriggerId else { return }
    let registration = registrations[triggerId]

    // Releasing on the plus is not a selection: the celebration plays, but the
    // interaction hands over to the system emoji keyboard instead of reporting
    // through onSelect.
    if activeShowsPlus, focusedIndex == activeItems.count {
      dismiss(selected: nil, cancelled: false, reportSelection: false)
      emojiInput.present(over: keyWindow()) { [weak self] emoji in
        self?.onSelectAnother?(triggerId, emoji)
      }
      return
    }

    var selection: String?
    if let index = focusedIndex, index < activeItems.count {
      let candidate = activeItems[index].id
      // Upsert with deselect: picking the current selection clears it
      // (spec §5).
      selection = candidate == registration?.selectedId ? nil : candidate
    }

    let hadFocus = focusedIndex != nil
    dismiss(selected: hadFocus ? selection : nil, cancelled: !hadFocus)
  }

  private func dismiss(
    selected: String?, cancelled: Bool, reportSelection: Bool = true
  ) {
    guard let triggerId = activeTriggerId else { return }

    // Selection is reported at touch-up; teardown waits for the animation
    // (spec §4.3).
    if !cancelled && reportSelection {
      onSelect?(triggerId, selected)
    }

    // The celebration plays on whatever was under the finger, whether that
    // committed a new selection or cleared the existing one — either way the
    // user chose that reaction.
    let celebratedIndex = cancelled ? nil : focusedIndex

    disabledScrollView?.panGestureRecognizer.isEnabled = true
    disabledScrollView = nil

    activeTriggerId = nil
    activeItems = []
    activeShowsPlus = false
    focusedIndex = nil

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

    if let index = celebratedIndex {
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
