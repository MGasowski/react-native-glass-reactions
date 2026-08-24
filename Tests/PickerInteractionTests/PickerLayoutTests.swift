import CoreGraphics
import XCTest

@testable import PickerInteraction

/// A 300×800 container — plenty of room on every side unless a case
/// deliberately pushes the trigger toward an edge.
private let container = CGSize(width: 300, height: 800)
private let pill = CGSize(width: 100, height: 40)
private let verticalGap: CGFloat = 8
private let edgeMargin: CGFloat = 12

private func frame(
  triggerX: CGFloat, triggerY: CGFloat, triggerWidth: CGFloat = 40,
  pillSize: CGSize = pill, containerSize: CGSize = container
) -> CGRect {
  PickerLayout.frame(
    trigger: CGRect(x: triggerX, y: triggerY, width: triggerWidth, height: 40),
    pillSize: pillSize,
    containerSize: containerSize,
    verticalGap: verticalGap,
    edgeMargin: edgeMargin
  )
}

final class PickerLayoutTests: XCTestCase {

  /// With room on every side, the pill centres over the trigger and sits
  /// `verticalGap` above it — no clamp engaged.
  func testCentresOverTheTriggerWithRoomToSpare() {
    // trigger: x 100–140 (midX 120), y 200–230 (minY 200)
    let result = frame(triggerX: 100, triggerY: 200)
    XCTAssertEqual(result.origin.x, 70, accuracy: 0.001)   // 120 - 100/2
    XCTAssertEqual(result.origin.y, 152, accuracy: 0.001)  // 200 - 40 - 8
    XCTAssertEqual(result.size, pill)
  }

  /// Centering reads the trigger's midpoint, not just its left edge — an
  /// asymmetric trigger rect must still centre correctly.
  func testCentersUsingTheTriggersMidpointNotItsOrigin() {
    let result = frame(triggerX: 50, triggerY: 200, triggerWidth: 80)
    // midX = 50 + 80/2 = 90
    XCTAssertEqual(result.origin.x, 40, accuracy: 0.001)   // 90 - 100/2
  }

  func testClampsToTheLeftEdge() {
    // midX = 10 + 20 = 30 -> raw x = -20, clamped to edgeMargin
    let result = frame(triggerX: 10, triggerY: 200, triggerWidth: 40)
    XCTAssertEqual(result.origin.x, edgeMargin, accuracy: 0.001)
  }

  func testClampsToTheRightEdge() {
    // midX = 270 + 20 = 290 -> raw x = 240, max allowed = 300-100-12 = 188
    let result = frame(triggerX: 270, triggerY: 200, triggerWidth: 40)
    XCTAssertEqual(result.origin.x, 188, accuracy: 0.001)
  }

  /// When the pill is wider than the container, the naive upper bound
  /// (`containerWidth - pillWidth - edgeMargin`) goes negative. The clamp
  /// must not crash or invert; it collapses to the left margin.
  func testCollapsesToTheLeftMarginWhenThePillIsWiderThanTheContainer() {
    let wide = CGSize(width: 100, height: 40)
    let narrowContainer = CGSize(width: 80, height: 800)

    let leaningLeft = frame(triggerX: -200, triggerY: 200, pillSize: wide, containerSize: narrowContainer)
    let leaningRight = frame(triggerX: 500, triggerY: 200, pillSize: wide, containerSize: narrowContainer)

    XCTAssertEqual(leaningLeft.origin.x, edgeMargin, accuracy: 0.001)
    XCTAssertEqual(leaningRight.origin.x, edgeMargin, accuracy: 0.001)
  }

  func testClampsToTheTopEdgeWhenThereIsNoRoomAbove() {
    // minY = 10 -> raw y = 10 - 40 - 8 = -38, clamped to edgeMargin
    let result = frame(triggerX: 100, triggerY: 10)
    XCTAssertEqual(result.origin.y, edgeMargin, accuracy: 0.001)
  }

  /// There is deliberately no lower bound on y — the pill is always anchored
  /// above the trigger that opened it, so it can never run off the bottom.
  func testHasNoLowerBoundOnVerticalPosition() {
    let result = frame(triggerX: 100, triggerY: 790)
    XCTAssertEqual(result.origin.y, 790 - 40 - 8, accuracy: 0.001)
  }

  /// The returned frame's size is always the requested pill size, whether or
  /// not either axis clamped.
  func testReturnedSizeIsAlwaysThePillSize() {
    let clamped = frame(triggerX: 10, triggerY: 10)
    XCTAssertEqual(clamped.size, pill)
  }
}
