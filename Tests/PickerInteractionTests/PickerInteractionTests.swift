import CoreGraphics
import XCTest

@testable import PickerInteraction

/// Uniform 48pt slots. The pill's real geometry is not uniform once the
/// separator inserts its extra width, but that is the pill's rule to get right;
/// what is under test here is everything *around* the lookup.
private struct UniformSlots: SlotGeometry {
  let count: Int
  var width: CGFloat = 48

  func slotIndex(atLocalX x: CGFloat) -> Int? {
    guard count > 0 else { return nil }
    return min(max(Int(x / width), 0), count - 1)
  }
}

private func reaction(_ id: String) -> Reaction {
  Reaction(id: id, emoji: "👍", accessibilityLabel: id)
}

/// A picker at (100, 200) sized 144×40 — three 48pt slots.
private let frame = CGRect(x: 100, y: 200, width: 144, height: 40)

private func makeInteraction(
  slots: [Slot],
  selectedId: String? = nil,
  tolerance: CGFloat = 12
) -> PickerInteraction {
  PickerInteraction(
    triggerId: "trigger",
    slots: slots,
    selectedId: selectedId,
    pickerFrame: frame,
    tolerance: tolerance,
    geometry: UniformSlots(count: slots.count)
  )
}

private let threeReactions: [Slot] = [
  .reaction(reaction("a")), .reaction(reaction("b")), .reaction(reaction("c")),
]

// MARK: - Focus

final class FocusTests: XCTestCase {

  /// The picker opens under a finger that is on the row *below* it. Focusing
  /// anything at that moment is what made a reaction look pre-selected the
  /// instant the picker appeared.
  func testStartsWithNothingFocused() {
    let interaction = makeInteraction(slots: threeReactions)
    XCTAssertNil(interaction.focusedIndex)
  }

  func testFocusesTheSlotUnderThePoint() {
    var interaction = makeInteraction(slots: threeReactions)
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 220)), .moved(to: 0))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 172, y: 220)), .moved(to: 1))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 220, y: 220)), .moved(to: 2))
  }

  /// Moving within one slot must not report a change, or the per-item haptic
  /// fires repeatedly while the finger sits still.
  func testMovingWithinASlotReportsNoChange() {
    var interaction = makeInteraction(slots: threeReactions)
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 110, y: 220)), .moved(to: 0))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 112, y: 220)), .unchanged)
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 140, y: 220)), .unchanged)
  }

  func testLeavingThePickerClearsFocus() {
    var interaction = makeInteraction(slots: threeReactions)
    _ = interaction.focus(at: CGPoint(x: 124, y: 220))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 400)), .cleared)
    XCTAssertNil(interaction.focusedIndex)
  }

  func testStayingOutsideReportsNoChange() {
    var interaction = makeInteraction(slots: threeReactions)
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 400)), .unchanged)
  }

  /// Vertical slack keeps the selection from flickering at the edge.
  func testToleranceExtendsFocusVertically() {
    var interaction = makeInteraction(slots: threeReactions)
    // 11pt below the bottom edge: still pointing at a reaction.
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 251)), .moved(to: 0))
    // 13pt below: past the slack.
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 253)), .cleared)
  }

  func testToleranceExtendsFocusAboveThePickerToo() {
    var interaction = makeInteraction(slots: threeReactions)
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 190)), .moved(to: 0))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 187)), .cleared)
  }

  /// There is deliberately no horizontal slack: a point beside the picker must
  /// clear rather than clamp to the nearest end slot.
  func testNoHorizontalTolerance() {
    var interaction = makeInteraction(slots: threeReactions)
    _ = interaction.focus(at: CGPoint(x: 124, y: 220))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 99, y: 220)), .cleared)

    _ = interaction.focus(at: CGPoint(x: 124, y: 220))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 245, y: 220)), .cleared)
  }

  /// `CGRect.contains` is half-open, so the trailing edges are outside. Pinned
  /// because the hit area is built with `insetBy`, and a reader would otherwise
  /// have to know that to predict the boundary.
  func testHitAreaIsHalfOpen() {
    var interaction = makeInteraction(slots: threeReactions)
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 100, y: 188)), .moved(to: 0))
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 244, y: 220)), .cleared)
  }

  func testEmptySlotsNeverFocus() {
    var interaction = makeInteraction(slots: [])
    XCTAssertEqual(interaction.focus(at: CGPoint(x: 124, y: 220)), .unchanged)
  }
}

// MARK: - Release

final class ReleaseTests: XCTestCase {

  func testReleasingWithNoFocusCancels() {
    let interaction = makeInteraction(slots: threeReactions)
    XCTAssertEqual(interaction.release(), .cancel)
  }

  func testReleasingAfterLeavingThePickerCancels() {
    var interaction = makeInteraction(slots: threeReactions)
    _ = interaction.focus(at: CGPoint(x: 124, y: 220))
    _ = interaction.focus(at: CGPoint(x: 124, y: 400))
    XCTAssertEqual(interaction.release(), .cancel)
  }

  func testReleasingOnAReactionSelectsIt() {
    var interaction = makeInteraction(slots: threeReactions, selectedId: nil)
    _ = interaction.focus(at: CGPoint(x: 172, y: 220))
    XCTAssertEqual(interaction.release(), .select(reactionId: "b", at: 1))
  }

  /// Upsert with deselect (spec §5).
  func testReleasingOnTheCurrentSelectionClearsIt() {
    var interaction = makeInteraction(slots: threeReactions, selectedId: "b")
    _ = interaction.focus(at: CGPoint(x: 172, y: 220))
    XCTAssertEqual(interaction.release(), .deselect(at: 1))
  }

  func testReleasingOnADifferentReactionWhileOneIsSelectedReplacesIt() {
    var interaction = makeInteraction(slots: threeReactions, selectedId: "b")
    _ = interaction.focus(at: CGPoint(x: 220, y: 220))
    XCTAssertEqual(interaction.release(), .select(reactionId: "c", at: 2))
  }

  /// Releasing on the plus reports nothing — the interaction hands over to the
  /// system emoji picker instead.
  func testReleasingOnThePlusIsNotASelection() {
    var interaction = makeInteraction(
      slots: [.reaction(reaction("a")), .reaction(reaction("b")), .another(nil)]
    )
    _ = interaction.focus(at: CGPoint(x: 220, y: 220))
    XCTAssertEqual(interaction.release(), .another(at: 2))
  }

  /// The custom pick is selectable, and its id is the emoji itself.
  func testReleasingOnTheCustomPickSelectsTheEmoji() {
    var interaction = makeInteraction(
      slots: [.reaction(reaction("a")), .custom("🎉"), .another(nil)]
    )
    _ = interaction.focus(at: CGPoint(x: 172, y: 220))
    XCTAssertEqual(interaction.release(), .select(reactionId: "🎉", at: 1))
  }

  func testReleasingOnTheCurrentCustomPickClearsIt() {
    var interaction = makeInteraction(
      slots: [.reaction(reaction("a")), .custom("🎉"), .another(nil)],
      selectedId: "🎉"
    )
    _ = interaction.focus(at: CGPoint(x: 172, y: 220))
    XCTAssertEqual(interaction.release(), .deselect(at: 1))
  }

  /// The plus is the last slot whether or not a custom pick precedes it. This
  /// is the arithmetic that used to depend on two arrays differing in length by
  /// exactly one.
  func testThePlusStaysTheLastSlotWithACustomPickPresent() {
    var interaction = makeInteraction(
      slots: [.reaction(reaction("a")), .custom("🎉"), .another(nil)]
    )
    _ = interaction.focus(at: CGPoint(x: 220, y: 220))
    XCTAssertEqual(interaction.release(), .another(at: 2))
  }
}

// MARK: - Separator

final class SeparatorTests: XCTestCase {

  func testNoSeparatorWithoutTheAnotherReactionSection() {
    XCTAssertNil(makeInteraction(slots: threeReactions).separatorAfter)
  }

  func testSeparatorSitsBeforeTheAnotherReactionSection() {
    let interaction = makeInteraction(
      slots: [.reaction(reaction("a")), .reaction(reaction("b")), .another(nil)]
    )
    XCTAssertEqual(interaction.separatorAfter, 2)
  }

  func testTheCustomPickBelongsToTheAnotherReactionSection() {
    let interaction = makeInteraction(
      slots: [.reaction(reaction("a")), .custom("🎉"), .another(nil)]
    )
    XCTAssertEqual(interaction.separatorAfter, 1)
  }

  /// Nothing on the left of the divider means nothing to divide.
  func testNoSeparatorWhenThereAreNoReactions() {
    XCTAssertNil(makeInteraction(slots: [.another(nil)]).separatorAfter)
    XCTAssertNil(makeInteraction(slots: [.custom("🎉"), .another(nil)]).separatorAfter)
  }
}
