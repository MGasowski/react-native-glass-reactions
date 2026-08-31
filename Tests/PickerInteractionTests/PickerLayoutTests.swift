import CoreGraphics
import XCTest

@testable import PickerInteraction

/// A 300×800 safe rect at the window's origin — plenty of room on every side
/// unless a case deliberately shrinks it or pushes the press toward an edge.
private let safeArea = CGRect(x: 0, y: 0, width: 300, height: 800)
private let pill = CGSize(width: 100, height: 40)
private let gapAbove: CGFloat = 44
private let gapBelow: CGFloat = 24
private let edgeMargin: CGFloat = 12

/// The trigger's y is deliberately not a parameter: it no longer feeds the
/// vertical placement at all, and the one case that cares about that
/// — `testVerticalPlacementFollowsTheTouchNotTheTrigger` — builds its own rect.
private func frame(
  touchY: CGFloat, touchX: CGFloat = 120,
  triggerX: CGFloat = 100, triggerWidth: CGFloat = 40,
  pillSize: CGSize = pill, container: CGRect = safeArea
) -> CGRect {
  PickerLayout.frame(
    touch: CGPoint(x: touchX, y: touchY),
    trigger: CGRect(x: triggerX, y: 200, width: triggerWidth, height: 40),
    pillSize: pillSize,
    containerBounds: container,
    gapAbove: gapAbove,
    gapBelow: gapBelow,
    edgeMargin: edgeMargin
  )
}

final class PickerLayoutTests: XCTestCase {

  /// With room on every side, the pill centres over the trigger and sits
  /// `gapAbove` above the press — no clamp engaged, no flip.
  func testSitsAboveTheTouchWithRoomToSpare() {
    // trigger: x 100–140 (midX 120); touch at y 200
    let result = frame(touchY: 200)
    XCTAssertEqual(result.origin.x, 70, accuracy: 0.001)   // 120 - 100/2
    XCTAssertEqual(result.origin.y, 116, accuracy: 0.001)  // 200 - 44 - 40
    XCTAssertEqual(result.size, pill)
  }

  /// The whole point of the change: on a tall trigger the pill tracks the
  /// finger, not the trigger's top edge, so it lands the same distance from
  /// the thumb whatever was pressed.
  func testVerticalPlacementFollowsTheTouchNotTheTrigger() {
    // A 300pt-tall trigger spanning y 100–400, pressed near its bottom.
    let result = PickerLayout.frame(
      touch: CGPoint(x: 120, y: 380),
      trigger: CGRect(x: 100, y: 100, width: 40, height: 300),
      pillSize: pill,
      containerBounds: safeArea,
      gapAbove: gapAbove,
      gapBelow: gapBelow,
      edgeMargin: edgeMargin
    )
    // Anchored to the press (380 - 44 - 40), not to the trigger's top (100).
    XCTAssertEqual(result.origin.y, 296, accuracy: 0.001)
  }

  /// Horizontal placement is the other way round: the trigger decides, not the
  /// finger, so the pill does not wander with where in a row you pressed.
  func testHorizontalPlacementFollowsTheTriggerNotTheTouch() {
    let left = frame(touchY: 200, touchX: 102)
    let right = frame(touchY: 200, touchX: 138)
    XCTAssertEqual(left.origin.x, right.origin.x, accuracy: 0.001)
    XCTAssertEqual(left.origin.x, 70, accuracy: 0.001)
  }

  /// Centering reads the trigger's midpoint, not just its left edge — an
  /// asymmetric trigger rect must still centre correctly.
  func testCentersUsingTheTriggersMidpointNotItsOrigin() {
    let result = frame(touchY: 200, triggerX: 50, triggerWidth: 80)
    // midX = 50 + 80/2 = 90
    XCTAssertEqual(result.origin.x, 40, accuracy: 0.001)   // 90 - 100/2
  }

  func testClampsToTheLeftEdge() {
    // midX = 10 + 20 = 30 -> raw x = -20, clamped to edgeMargin
    let result = frame(touchY: 200, triggerX: 10)
    XCTAssertEqual(result.origin.x, edgeMargin, accuracy: 0.001)
  }

  func testClampsToTheRightEdge() {
    // midX = 270 + 20 = 290 -> raw x = 240, max allowed = 300-100-12 = 188
    let result = frame(touchY: 200, triggerX: 270)
    XCTAssertEqual(result.origin.x, 188, accuracy: 0.001)
  }

  /// When the pill is wider than the container, the naive upper bound
  /// (`maxX - pillWidth - edgeMargin`) falls below the left margin. The clamp
  /// must not crash or invert; it collapses to the left margin.
  func testCollapsesToTheLeftMarginWhenThePillIsWiderThanTheContainer() {
    let narrow = CGRect(x: 0, y: 0, width: 80, height: 800)

    let leaningLeft = frame(touchY: 200, triggerX: -200, container: narrow)
    let leaningRight = frame(touchY: 200, triggerX: 500, container: narrow)

    XCTAssertEqual(leaningLeft.origin.x, edgeMargin, accuracy: 0.001)
    XCTAssertEqual(leaningRight.origin.x, edgeMargin, accuracy: 0.001)
  }

  /// The flip: no room above the press, room below, so it goes below —
  /// `gapBelow` under the finger rather than jammed against the top edge.
  func testFlipsBelowWhenThereIsNoRoomAbove() {
    // above = 40 - 44 - 40 = -44, outside the safe rect; below = 40 + 24 = 64,
    // whose bottom (104) is inside it.
    let result = frame(touchY: 40)
    XCTAssertEqual(result.origin.y, 64, accuracy: 0.001)
  }

  /// The flip is conditional on the flipped placement *fitting*. When neither
  /// side does, the pill falls back to above-and-clamped — exactly what it did
  /// before the flip existed. It may then straddle the press, which is why the
  /// callers' "did it flip" test is `minY >= touch.y` and not a midpoint
  /// comparison: this frame must read as above.
  func testDoesNotFlipWhenBelowWouldAlsoBeClipped() {
    let shallow = CGRect(x: 0, y: 0, width: 300, height: 100)
    let result = frame(touchY: 40, container: shallow)
    XCTAssertEqual(result.origin.y, edgeMargin, accuracy: 0.001)
    XCTAssertLessThan(result.minY, 40)
  }

  /// The safe rect's top inset — the status bar — is what the flip is measured
  /// against, not the window's origin. The same press flips here and does not
  /// flip against a full-window rect.
  func testTheFlipRespectsTheSafeRectsTopInset() {
    let inset = CGRect(x: 0, y: 50, width: 300, height: 750)
    // above = 100 - 44 - 40 = 16, which clears the window's top but not the
    // safe rect's (50 + 12 = 62).
    XCTAssertEqual(frame(touchY: 100).origin.y, 16, accuracy: 0.001)
    XCTAssertEqual(frame(touchY: 100, container: inset).origin.y, 124, accuracy: 0.001)
  }

  /// Side insets — a landscape cutout — are honoured by the same clamp, with
  /// `edgeMargin` applied inside the safe rect rather than from the window.
  func testTheClampRespectsTheSafeRectsSideInsets() {
    let inset = CGRect(x: 40, y: 0, width: 220, height: 800)
    XCTAssertEqual(frame(touchY: 200, triggerX: 10, container: inset).origin.x, 52, accuracy: 0.001)
    XCTAssertEqual(frame(touchY: 200, triggerX: 270, container: inset).origin.x, 148, accuracy: 0.001)
  }

  /// There is deliberately no bottom clamp on the above-placement: the pill
  /// hangs above the press, so the only thing the bottom edge decides is
  /// whether a *flip* is allowed.
  func testTheAbovePlacementIsNeverClampedAgainstTheBottomEdge() {
    let shortContainer = CGRect(x: 0, y: 0, width: 300, height: 700)
    let result = frame(touchY: 780, container: shortContainer)
    XCTAssertEqual(result.origin.y, 696, accuracy: 0.001)  // 780 - 44 - 40
  }

  /// The returned frame's size is always the requested pill size, whether or
  /// not either axis clamped or the placement flipped.
  func testReturnedSizeIsAlwaysThePillSize() {
    XCTAssertEqual(frame(touchY: 10, triggerX: 10).size, pill)
  }
}
