import XCTest

/// On-device UI tests for the reactions picker.
///
/// These exist because Maestro cannot express the interaction the library is
/// built around: `longPressOn` presses *and releases*, which ends the gesture
/// before a reaction can be dragged to. XCUITest's
/// `press(forDuration:thenDragTo:)` is a single continuous press → hold → drag
/// → release, which is exactly the gesture under test.
///
/// They also give the profiling pass something to attach to: the §6.5
/// acceptance criteria are about frames during scrolling and during the
/// interaction, and both need the app actually being driven.
final class ReactionsUITests: XCTestCase {

  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
  }

  /// `.firstMatch` throughout: React Native's accessibility tree exposes the
  /// same label on more than one node, and an ambiguous query throws at
  /// resolution time rather than returning something usable.
  private func row(_ index: Int) -> XCUIElement {
    app.staticTexts.matching(identifier: "Review #\(index)").firstMatch
  }

  func testRowsRender() throws {
    XCTAssertTrue(row(1).waitForExistence(timeout: 30), "list did not render")
    XCTAssertTrue(row(5).exists)
  }

  /// The core interaction: long-press opens the picker, dragging moves the
  /// focus, releasing commits the reaction under the finger.
  ///
  /// The example's badge carries the current selection as its accessibility
  /// label, so this asserts the selection actually round-tripped through JS
  /// rather than merely that the row survived the gesture.
  func testLongPressDragSelects() throws {
    XCTAssertTrue(row(5).waitForExistence(timeout: 30))

    // React Native nests an accessible container inside the accessible view,
    // so the identifier resolves to more than one node; take the first rather
    // than letting the query fail to disambiguate.
    let badge = app.otherElements.matching(identifier: "score-5").firstMatch
    XCTAssertTrue(badge.waitForExistence(timeout: 10), "badge not found")
    XCTAssertEqual(badge.label, "none", "row started with a selection")

    let target = row(5)
    // The picker presents above the trigger, so the drag destination is up and
    // across from where the press started.
    let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
    let destination = target.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: -1.2))

    start.press(forDuration: 0.6, thenDragTo: destination)

    let selected = NSPredicate(format: "label != %@", "none")
    expectation(for: selected, evaluatedWith: badge)
    waitForExpectations(timeout: 10)

    XCTAssertNotEqual(badge.label, "none", "drag did not commit a reaction")
  }

  /// Spec §6.4's acceptance rule: a vertical drag that starts before the
  /// long-press threshold must scroll the list, not open the picker.
  func testSwipeStillScrolls() throws {
    XCTAssertTrue(row(1).waitForExistence(timeout: 30))

    app.swipeUp(velocity: .fast)
    app.swipeUp(velocity: .fast)

    XCTAssertFalse(
      app.buttons["Like"].exists,
      "scrolling opened the picker — arbitration regression (spec §6.4)"
    )
  }

  /// Drives sustained scrolling so a profiler attached to the process has
  /// something meaningful to measure (spec §6.5 scroll gate).
  func testSustainedScrollForProfiling() throws {
    XCTAssertTrue(row(1).waitForExistence(timeout: 30))

    for _ in 0..<40 {
      app.swipeUp(velocity: .fast)
    }
    for _ in 0..<40 {
      app.swipeDown(velocity: .fast)
    }
  }
}
