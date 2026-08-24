import CoreGraphics

// MARK: - Inputs

/// A reaction as the interaction policy sees it.
///
/// Deliberately *not* `NativeReactionItem`. That type is a typealias onto a C++
/// struct whose initialiser goes through `std.string` and the generated bridge,
/// so carrying it here would drag CocoaPods and C++ interop into anything that
/// wants to construct one — including tests. The host maps at the boundary,
/// which is what an adapter is for.
struct Reaction: Equatable {
  let id: String
  let emoji: String
  let symbolIos: String?
  let symbolAndroid: String?
  let accessibilityLabel: String

  init(
    id: String,
    emoji: String,
    symbolIos: String? = nil,
    symbolAndroid: String? = nil,
    accessibilityLabel: String
  ) {
    self.id = id
    self.emoji = emoji
    self.symbolIos = symbolIos
    self.symbolAndroid = symbolAndroid
    self.accessibilityLabel = accessibilityLabel
  }
}

/// Appearance of the "another reaction" item, mapped off `NativeAnotherReaction`
/// for the same reason as `Reaction`. Every field is optional: an unset field
/// keeps the built-in default.
struct AnotherReactionAppearance: Equatable {
  let symbolIos: String?
  let symbolAndroid: String?
  let emoji: String?
  let badge: Bool?
  let accessibilityLabel: String?

  init(
    symbolIos: String? = nil,
    symbolAndroid: String? = nil,
    emoji: String? = nil,
    badge: Bool? = nil,
    accessibilityLabel: String? = nil
  ) {
    self.symbolIos = symbolIos
    self.symbolAndroid = symbolAndroid
    self.emoji = emoji
    self.badge = badge
    self.accessibilityLabel = accessibilityLabel
  }
}

/// One position in the open picker.
///
/// This is the list — there is not a second one. Hit-testing, selection
/// reporting and drawing all index into these same slots, so "the plus is the
/// slot after the reactions" is a `case`, not arithmetic over two arrays that
/// happen to differ in length by one.
enum Slot: Equatable {
  /// One of the consumer's registered reactions.
  case reaction(Reaction)
  /// The emoji previously picked through "another reaction". Its id is the
  /// emoji itself — it exists in no item list, so that is its only identity.
  case custom(String)
  /// The trailing plus. Releasing here opens the system emoji picker rather
  /// than reporting a selection.
  case another(AnotherReactionAppearance?)
}

/// How slot centres are found. The pill owns this: slots are not uniform once
/// the section separator inserts its extra width, and the pill is the layout
/// authority that already has the numbers. `ReactionsPillView` satisfies it.
protocol SlotGeometry {
  func slotIndex(atLocalX x: CGFloat) -> Int?
}

// MARK: - Outputs

/// What a finger move did to the focus. Three named cases rather than an
/// `Int?`, because the rule that matters — a haptic fires when focus *lands*
/// on a slot, never when it leaves one — is then a case split rather than an
/// `if next != nil` the reader has to interpret.
enum FocusChange: Equatable {
  case unchanged
  case moved(to: Int)
  case cleared
}

/// What releasing the finger meant. The index rides along so the host never has
/// to ask what was focused after the fact — and so "celebrate at no index" is
/// unrepresentable.
enum Outcome: Equatable {
  /// Report this id through `onSelect`.
  case select(reactionId: String, at: Int)
  /// Report `nil` through `onSelect` — the user picked what was already
  /// selected, which clears it (spec §5).
  case deselect(at: Int)
  /// Report nothing; hand over to the system emoji picker.
  case another(at: Int)
  /// Report nothing, celebrate nothing.
  case cancel
}

// MARK: - Interaction

/// The rules of one long-press, from open to release.
///
/// Everything here was previously smeared across `begin`, `index(at:)`,
/// `updateFocus`, `end` and `dismiss` on the host, reachable only through a real
/// touch on a real device. It holds no UIKit — importing UIKit here fails the
/// `swift test` build on macOS, which is the point.
///
/// Its inputs are a frozen picture taken at gesture-begin. Nothing is re-read
/// from the registry afterwards: the user is choosing against the pill in front
/// of them, so the comparison that decides deselection has to use what that pill
/// was drawn from.
///
/// Cancellation is not a method. A cancelled gesture, a recycled row or a
/// `deactivate` simply drops the interaction — there was no release, so there is
/// no outcome to produce.
struct PickerInteraction {

  let triggerId: String
  let slots: [Slot]

  /// What was selected when the picker opened. See the note above on why this
  /// is a snapshot.
  private let selectedId: String?

  private let pickerFrame: CGRect
  private let tolerance: CGFloat
  private let geometry: SlotGeometry

  private(set) var focusedIndex: Int?

  init(
    triggerId: String,
    slots: [Slot],
    selectedId: String?,
    pickerFrame: CGRect,
    tolerance: CGFloat,
    geometry: SlotGeometry
  ) {
    self.triggerId = triggerId
    self.slots = slots
    self.selectedId = selectedId
    self.pickerFrame = pickerFrame
    self.tolerance = tolerance
    self.geometry = geometry
  }

  /// See `Array.separatorAfter`. Exposed here so the rule has one home even
  /// though the host needs it before an interaction exists.
  var separatorAfter: Int? { slots.separatorAfter }

  // MARK: Focus

  mutating func focus(at point: CGPoint) -> FocusChange {
    let next = index(at: point)
    guard next != focusedIndex else { return .unchanged }
    focusedIndex = next
    guard let next else { return .cleared }
    return .moved(to: next)
  }

  /// Which slot a point is pointing at, if any.
  ///
  /// The vertical slack is what stops the selection flickering at the edge; the
  /// lack of horizontal slack is deliberate. The press that opens the picker
  /// lands on the row *below* it, so generous slack here means a reaction is
  /// selected before the finger has gone anywhere near one.
  private func index(at point: CGPoint) -> Int? {
    guard !slots.isEmpty else { return nil }
    let hitArea = pickerFrame.insetBy(dx: 0, dy: -tolerance)
    guard hitArea.contains(point) else { return nil }
    return geometry.slotIndex(atLocalX: point.x - pickerFrame.minX)
  }

  // MARK: Release

  func release() -> Outcome {
    guard let index = focusedIndex, slots.indices.contains(index) else {
      return .cancel
    }
    switch slots[index] {
    case .another:
      return .another(at: index)
    case .reaction(let reaction):
      return outcome(selecting: reaction.id, at: index)
    case .custom(let emoji):
      return outcome(selecting: emoji, at: index)
    }
  }

  /// Upsert with deselect: picking what is already selected clears it
  /// (spec §5).
  private func outcome(selecting id: String, at index: Int) -> Outcome {
    id == selectedId ? .deselect(at: index) : .select(reactionId: id, at: index)
  }
}

extension Array where Element == Slot {
  /// Index of the first slot in the "another reaction" section, or nil when
  /// there is no divider to draw.
  ///
  /// Derived from the slots rather than tracked beside them, so it cannot
  /// disagree with what is on screen. Lives on the array because the host has
  /// to lay the pill out — and therefore know the separator — before it has a
  /// frame to build an interaction with.
  var separatorAfter: Int? {
    guard let first = firstIndex(where: { $0.isAnotherReactionSection })
    else { return nil }
    // Nothing on the left of the divider means nothing to divide.
    return first > 0 ? first : nil
  }
}

extension Slot {
  /// Whether this slot belongs to the "another reaction" section — the custom
  /// pick and the plus, which travel together.
  var isAnotherReactionSection: Bool {
    switch self {
    case .reaction: return false
    case .custom, .another: return true
    }
  }
}
