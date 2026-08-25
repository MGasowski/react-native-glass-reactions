import XCTest

@testable import PickerInteraction

private func color(_ hex: String) -> SymbolColor? { SymbolColor(hex: hex) }

final class SymbolColorTests: XCTestCase {

  func testParsesSixDigitHex() {
    XCTAssertEqual(
      color("#FF8800"),
      SymbolColor(red: 1, green: Double(0x88) / 255, blue: 0, alpha: 1)
    )
  }

  func testTheHashIsOptional() {
    XCTAssertEqual(color("FF8800"), color("#FF8800"))
  }

  func testCaseDoesNotMatter() {
    XCTAssertEqual(color("#ff8800"), color("#FF8800"))
  }

  /// The rule worth pinning down: shorthand *repeats* each digit, so `#f80`
  /// is `#ff8800`. Padding with a zero instead would darken every shorthand
  /// colour and the difference only shows up on device.
  func testShorthandRepeatsEachDigit() {
    XCTAssertEqual(color("#f80"), color("#ff8800"))
  }

  func testEightDigitHexCarriesAlpha() {
    XCTAssertEqual(color("#FF880080")?.alpha, Double(0x80) / 255)
    XCTAssertEqual(color("#FF880080")?.red, 1)
  }

  func testShorthandAlpha() {
    XCTAssertEqual(color("#f808"), color("#ff880088"))
  }

  func testAlphaDefaultsToOpaque() {
    XCTAssertEqual(color("#FF8800")?.alpha, 1)
  }

  /// Every rejection leaves the caller with `nil`, which is what makes an
  /// unparseable string fall back to the default tint rather than to a colour
  /// nobody asked for.
  func testRejectsWhatItCannotParse() {
    XCTAssertNil(color(""))
    XCTAssertNil(color("#"))
    XCTAssertNil(color("#FF888"))
    XCTAssertNil(color("#FF88000"))
    XCTAssertNil(color("#GG8800"))
    XCTAssertNil(color("powder red"))
    XCTAssertNil(color("rgb(255, 136, 0)"))
  }
}

// MARK: - Paint

final class SymbolPaintTests: XCTestCase {

  func testAColourIsSolid() {
    XCTAssertEqual(SymbolPaint("#FF8800"), .solid(SymbolColor(hex: "#FF8800")!))
  }

  func testTheKeywordAsksForTheGlyphsOwnPalette() {
    XCTAssertEqual(SymbolPaint("multicolor"), .multicolor)
    XCTAssertEqual(SymbolPaint("Multicolor"), .multicolor)
    XCTAssertEqual(SymbolPaint("  multicolor  "), .multicolor)
  }

  /// The keyword is a word, not a colour, so no hex string can ever mean it
  /// and no colour is lost to it.
  func testTheKeywordCannotCollideWithAColour() {
    XCTAssertNotEqual(SymbolPaint("#mult"), .multicolor)
  }

  /// Everything unreadable lands on the library's own treatment rather than
  /// on a colour nobody chose.
  func testAnythingElseIsTheDefaultTreatment() {
    XCTAssertEqual(SymbolPaint(nil), .default)
    XCTAssertEqual(SymbolPaint(""), .default)
    XCTAssertEqual(SymbolPaint("multi-color"), .default)
    XCTAssertEqual(SymbolPaint("gold"), .default)
  }
}
