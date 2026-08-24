import CoreGraphics
import XCTest

@testable import PickerInteraction

/// itemSize 40, itemSpacing 8, contentInset 8, separatorExtra 8 — round
/// numbers chosen so centres land on whole values and are easy to verify by
/// hand: stride 48 between ungapped slots, 56 across the separator.
private let itemSize: CGFloat = 40
private let itemSpacing: CGFloat = 8
private let contentInset: CGFloat = 8
private let separatorExtra: CGFloat = 8

private func centerX(
  at index: Int, separatorAfter: Int? = nil
) -> CGFloat {
  SlotLayout.centerX(
    at: index, itemSize: itemSize, itemSpacing: itemSpacing,
    contentInset: contentInset, separatorAfter: separatorAfter,
    separatorExtra: separatorExtra
  )
}

private func nearestIndex(
  atLocalX x: CGFloat, count: Int, separatorAfter: Int? = nil
) -> Int? {
  SlotLayout.nearestIndex(
    atLocalX: x, count: count, itemSize: itemSize, itemSpacing: itemSpacing,
    contentInset: contentInset, separatorAfter: separatorAfter,
    separatorExtra: separatorExtra
  )
}

final class SlotLayoutCenterXTests: XCTestCase {

  func testFirstSlotSitsAfterTheContentInset() {
    // 8 + 0*(48) + 20
    XCTAssertEqual(centerX(at: 0), 28, accuracy: 0.001)
  }

  func testStrideBetweenSlotsIsItemSizePlusSpacing() {
    XCTAssertEqual(centerX(at: 1), 76, accuracy: 0.001)   // 28 + 48
    XCTAssertEqual(centerX(at: 2), 124, accuracy: 0.001)  // 76 + 48
  }

  func testSlotsBeforeTheSeparatorAreUnaffected() {
    XCTAssertEqual(centerX(at: 2, separatorAfter: 3), 124, accuracy: 0.001)
  }

  /// `index >= separatorAfter`, so the boundary slot itself is already widened.
  func testTheSeparatorBoundarySlotIsWidened() {
    XCTAssertEqual(centerX(at: 3, separatorAfter: 3), 180, accuracy: 0.001)  // 172 + 8
  }

  /// The extra width is a flat offset applied once, not compounded per slot
  /// beyond the boundary — stride resumes at the normal 48 after it.
  func testExtraWidthDoesNotCompoundPastTheSeparator() {
    let third = centerX(at: 3, separatorAfter: 3)
    let fourth = centerX(at: 4, separatorAfter: 3)
    XCTAssertEqual(fourth - third, 48, accuracy: 0.001)
  }

  func testNoSeparatorMeansNoWidening() {
    XCTAssertEqual(centerX(at: 4, separatorAfter: nil), centerX(at: 4) )
  }
}

final class SlotLayoutNearestIndexTests: XCTestCase {

  func testReturnsTheSlotWhosePointIsExact() {
    XCTAssertEqual(nearestIndex(atLocalX: 124, count: 5), 2)
  }

  func testReturnsTheCloserOfTwoNeighboringSlots() {
    // centerX(1)=76, centerX(2)=124 — 110 is 14 from slot 2, 34 from slot 1.
    XCTAssertEqual(nearestIndex(atLocalX: 110, count: 5), 2)
  }

  /// Ties go to the lower index — a strict `<` comparison, first-found wins.
  func testTiesGoToTheLowerIndex() {
    // Exact midpoint of centerX(1)=76 and centerX(2)=124.
    XCTAssertEqual(nearestIndex(atLocalX: 100, count: 5), 1)
  }

  /// Always returns the nearest slot, however far outside the row the point
  /// is — the caller is responsible for deciding whether the point counts as
  /// "in range" at all (spec: the tolerance-inset frame check happens before
  /// this is reached).
  func testReturnsTheNearestSlotEvenFarOutsideTheRow() {
    XCTAssertEqual(nearestIndex(atLocalX: -1000, count: 5), 0)
    XCTAssertEqual(nearestIndex(atLocalX: 1000, count: 5), 4)
  }

  func testEmptyRowNeverMatches() {
    XCTAssertNil(nearestIndex(atLocalX: 50, count: 0))
  }

  /// The separator's widened gap shifts where "nearest" flips — the boundary
  /// is no longer exactly halfway between the two neighbouring slots.
  func testTheSeparatorsWidenedGapShiftsTheNearestBoundary() {
    // centerX(2, sep:3)=124, centerX(3, sep:3)=180 — the ungapped midpoint
    // would be 152; 153 is still closer to 180 than to 124 (27 vs 29).
    XCTAssertEqual(nearestIndex(atLocalX: 153, count: 5, separatorAfter: 3), 3)
  }
}
