import XCTest

@testable import PickerInteraction

private func reaction(
  id: String = "a",
  emoji: String = "👍",
  symbolIos: String? = nil
) -> Reaction {
  Reaction(id: id, emoji: emoji, symbolIos: symbolIos, accessibilityLabel: id)
}

/// Every chain, over every input, must end somewhere that cannot fail to draw
/// — that is the property "the slot never blanks" actually rests on.
private func assertNeverBlanks(_ order: [Candidate], file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertFalse(order.isEmpty, "chain must never be empty", file: file, line: line)
  switch order.last! {
  case .emoji, .builtIn:
    break
  case .symbol, .anotherSymbol:
    XCTFail("chain must not end on an unverified symbol", file: file, line: line)
  }
}

// MARK: - Reaction slots

final class ItemResolutionTests: XCTestCase {

  func testAutoModePrefersASuppliedSymbol() {
    let order = ReactionResolution.resolutionOrder(
      for: .reaction(reaction(symbolIos: "heart.fill")),
      renderMode: .auto,
      symbolsSupported: true
    )
    XCTAssertEqual(order, [.symbol("heart.fill"), .emoji("👍")])
  }

  func testAutoModeWithNoSymbolFallsStraightToEmoji() {
    let order = ReactionResolution.resolutionOrder(
      for: .reaction(reaction()), renderMode: .auto, symbolsSupported: true
    )
    XCTAssertEqual(order, [.emoji("👍")])
  }

  /// The kill switch: emoji mode never offers a symbol candidate, regardless
  /// of what was supplied.
  func testEmojiModeSkipsTheSymbolEntirely() {
    let order = ReactionResolution.resolutionOrder(
      for: .reaction(reaction(symbolIos: "heart.fill")),
      renderMode: .emoji,
      symbolsSupported: true
    )
    XCTAssertEqual(order, [.emoji("👍")])
  }

  /// Android in 1.x: the platform has no symbol support at all, independent of
  /// render mode.
  func testUnsupportedPlatformNeverOffersASymbol() {
    let order = ReactionResolution.resolutionOrder(
      for: .reaction(reaction(symbolIos: "heart.fill")),
      renderMode: .auto,
      symbolsSupported: false
    )
    XCTAssertEqual(order, [.emoji("👍")])
  }

  func testEmptySymbolNameIsTreatedAsAbsent() {
    let order = ReactionResolution.resolutionOrder(
      for: .reaction(reaction(symbolIos: "")), renderMode: .auto, symbolsSupported: true
    )
    XCTAssertEqual(order, [.emoji("👍")])
  }

  func testNeverBlanksOverEveryCombination() {
    for symbol in [nil, "", "heart.fill"] {
      for mode: RenderMode in [.auto, .emoji] {
        for supported in [true, false] {
          assertNeverBlanks(
            ReactionResolution.resolutionOrder(
              for: .reaction(reaction(symbolIos: symbol)),
              renderMode: mode,
              symbolsSupported: supported
            )
          )
        }
      }
    }
  }
}

// MARK: - Custom pick

final class CustomPickResolutionTests: XCTestCase {

  /// The custom pick is a chosen emoji, not an item — it never offers a
  /// symbol, in any mode.
  func testIsAlwaysJustTheEmoji() {
    for mode: RenderMode in [.auto, .emoji] {
      let order = ReactionResolution.resolutionOrder(
        for: .custom("🎉"), renderMode: mode, symbolsSupported: true
      )
      XCTAssertEqual(order, [.emoji("🎉")])
    }
  }
}

// MARK: - Another reaction

final class AnotherReactionResolutionTests: XCTestCase {

  func testNoAppearanceFallsStraightToTheBuiltInGlyph() {
    let order = ReactionResolution.resolutionOrder(
      for: .another(nil), renderMode: .auto, symbolsSupported: true
    )
    XCTAssertEqual(order, [.builtIn(badge: true)])
  }

  func testAutoModePrefersASuppliedSymbolOverASuppliedEmoji() {
    let order = ReactionResolution.resolutionOrder(
      for: .another(
        AnotherReactionAppearance(symbolIos: "plus.circle", emoji: "➕")
      ),
      renderMode: .auto,
      symbolsSupported: true
    )
    XCTAssertEqual(
      order,
      [.anotherSymbol(name: "plus.circle", badge: true), .emoji("➕"), .builtIn(badge: true)]
    )
  }

  func testBadgeDefaultsTrueAndCarriesThroughEverySymbolCandidate() {
    let order = ReactionResolution.resolutionOrder(
      for: .another(AnotherReactionAppearance(symbolIos: "plus.circle", badge: false)),
      renderMode: .auto,
      symbolsSupported: true
    )
    XCTAssertEqual(
      order,
      [.anotherSymbol(name: "plus.circle", badge: false), .builtIn(badge: false)]
    )
  }

  /// The behaviour this candidate exists to fix: a supplied chrome symbol used
  /// to survive `renderMode: .emoji` whenever no override emoji was supplied,
  /// bypassing the kill switch. It no longer does.
  func testEmojiModeSkipsASuppliedSymbolEvenWithNoOverrideEmoji() {
    let order = ReactionResolution.resolutionOrder(
      for: .another(AnotherReactionAppearance(symbolIos: "plus.circle")),
      renderMode: .emoji,
      symbolsSupported: true
    )
    XCTAssertEqual(order, [.builtIn(badge: true)])
  }

  func testEmojiModeUsesTheOverrideEmojiWhenOneIsSupplied() {
    let order = ReactionResolution.resolutionOrder(
      for: .another(
        AnotherReactionAppearance(symbolIos: "plus.circle", emoji: "➕")
      ),
      renderMode: .emoji,
      symbolsSupported: true
    )
    XCTAssertEqual(order, [.emoji("➕"), .builtIn(badge: true)])
  }

  func testUnsupportedPlatformSkipsTheSymbolAndKeepsTheEmojiOverride() {
    let order = ReactionResolution.resolutionOrder(
      for: .another(
        AnotherReactionAppearance(symbolIos: "plus.circle", emoji: "➕")
      ),
      renderMode: .auto,
      symbolsSupported: false
    )
    XCTAssertEqual(order, [.emoji("➕"), .builtIn(badge: true)])
  }

  func testEmptyOverrideEmojiIsTreatedAsAbsent() {
    let order = ReactionResolution.resolutionOrder(
      for: .another(AnotherReactionAppearance(emoji: "")),
      renderMode: .auto,
      symbolsSupported: true
    )
    XCTAssertEqual(order, [.builtIn(badge: true)])
  }

  func testNeverBlanksOverEveryCombination() {
    let symbols: [String?] = [nil, "", "plus.circle"]
    let emojis: [String?] = [nil, "", "➕"]
    for symbol in symbols {
      for emoji in emojis {
        for badge in [true, false] {
          for mode: RenderMode in [.auto, .emoji] {
            for supported in [true, false] {
              assertNeverBlanks(
                ReactionResolution.resolutionOrder(
                  for: .another(
                    AnotherReactionAppearance(symbolIos: symbol, emoji: emoji, badge: badge)
                  ),
                  renderMode: mode,
                  symbolsSupported: supported
                )
              )
            }
          }
        }
      }
    }
  }
}
