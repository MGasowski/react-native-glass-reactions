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
    // across from where the press started. It aims near the pill's middle: the
    // last slot is the "another reaction" plus, which opens the emoji keyboard
    // instead of committing, so a far-right destination would assert nothing.
    let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
    let destination = target.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: -1.2))

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

  private func scrollHard() {
    for _ in 0..<40 { app.swipeUp(velocity: .fast) }
    for _ in 0..<40 { app.swipeDown(velocity: .fast) }
  }

  /// Drives sustained scrolling so a profiler attached to the process has
  /// something meaningful to measure (spec §6.5 scroll gate).
  func testSustainedScrollForProfiling() throws {
    XCTAssertTrue(row(1).waitForExistence(timeout: 30))
    scrollHard()
  }

  /// The control half of the §6.5 gate: the identical list and row content with
  /// the triggers removed. Whatever appears in both runs is the list's own
  /// cost, not the library's — which is the only way to read a hitch or hang
  /// count as attributable.
  func testSustainedScrollWithoutTriggers() throws {
    XCTAssertTrue(row(1).waitForExistence(timeout: 30))

    // The identifier encodes the state rather than the label: React Native
    // merges an accessible Pressable's subtree, and a label change on the
    // container does not reliably surface to XCUITest. An identifier swap does.
    let on = app.buttons.matching(identifier: "triggers-on").firstMatch
    XCTAssertTrue(on.waitForExistence(timeout: 15), "toggle not found")
    on.tap()

    let off = app.buttons.matching(identifier: "triggers-off").firstMatch
    XCTAssertTrue(
      off.waitForExistence(timeout: 15),
      "toggle did not switch triggers off"
    )

    scrollHard()
  }

  /// Not an assertion: a driver.
  ///
  /// `simctl` and Maestro both press and release as one event, so neither can
  /// hold the picker open long enough to film it. This performs the real
  /// gesture slowly enough to record against, for the capture screen
  /// (`SCREEN = "demo"`). Run it with `simctl io recordVideo` in flight.
  ///
  /// It also serves as the only way to see the pill's resolved colours at all,
  /// which is what the surface-appearance work needed.
  func testCaptureDemoGesture() throws {
    // The shared setUp launches without arguments, which points the bundle at
    // 8081. Relaunch onto whichever port Metro is actually on.
    app.terminate()
    app.launchArguments += ["-RCT_jsLocation", "localhost:8082"]
    app.launch()

    let card = app.otherElements.matching(identifier: "card-2").firstMatch
    XCTAssertTrue(
      card.waitForExistence(timeout: 60),
      "demo card not found — is SCREEN set to 'demo' in demo-config.ts?"
    )

    // Starts low in the card and finishes up over the pill, crossing several
    // reactions on the way so the focus animation is in shot. `.slow` keeps
    // the traverse legible at 24fps.
    // card-2 rather than the first card: the pill opens *above* its trigger,
    // and above card-0 is the status bar. Two cards down puts it mid-screen.
    let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.60))
    let destination = card.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: -0.10))

    let badge = app.otherElements.matching(identifier: "badge-2").firstMatch
    XCTAssertTrue(badge.waitForExistence(timeout: 10))

    start.press(
      forDuration: 1.2,
      thenDragTo: destination,
      withVelocity: .slow,
      thenHoldForDuration: 1.2
    )

    // Without this the capture silently "passes" when the pan wins
    // arbitration and the list merely scrolls, which is what the taller card
    // geometry caused once already.
    let committed = NSPredicate(format: "label != %@", "none")
    expectation(for: committed, evaluatedWith: badge)
    waitForExpectations(timeout: 10)
  }
}
