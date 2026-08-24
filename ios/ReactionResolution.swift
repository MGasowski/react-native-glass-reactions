// MARK: - Render mode

/// Mirrors the Nitro-generated `ReactionRenderMode`, copied for the same
/// reason `Reaction` is: the generated type is a C++-backed enum on iOS, and
/// pulling it into a pure module would tie resolution policy to whatever
/// nitrogen happens to produce. The host maps it at the boundary.
enum RenderMode: Equatable {
  case auto
  case emoji
}

// MARK: - Candidate

/// One drawable option in a resolution chain, matched 1:1 to the rasteriser
/// call it stands for.
///
/// Four cases rather than a shared `.symbol` case: an item's own symbol and
/// the "another reaction" chrome symbol are drawn by different rasterisers — a
/// plain glyph versus a composite with a corner badge — so collapsing them
/// would describe a call that isn't the one actually made.
enum Candidate: Equatable {
  /// An item's own SF Symbol / Material Symbol.
  case symbol(String)
  /// The "another reaction" chrome symbol, with its badge.
  case anotherSymbol(name: String, badge: Bool)
  case emoji(String)
  /// The built-in dashed-face glyph, with its badge.
  case builtIn(badge: Bool)
}

// MARK: - Resolution

/// Decides what a slot could be drawn as, in order — never what it looks like.
///
/// This returns a *chain*, not one resolved choice, because whether a supplied
/// symbol name actually resolves to an image is a question only the adapter's
/// rasteriser can answer (an unknown SF Symbol name rasterises to nothing, and
/// nothing in this module can know that in advance). The adapter draws the
/// first candidate that produces an image; this module decides only the order,
/// and guarantees the order always ends somewhere that cannot fail to draw.
enum ReactionResolution {

  /// The chain for one slot.
  ///
  /// `symbolsSupported` is what lets one function serve both platforms: iOS
  /// passes `true`, Android passes `false` in 1.x, where every symbol
  /// candidate is skipped and the chain degrades to emoji-or-built-in — the
  /// same behaviour Android's rasteriser always had, now expressed as data
  /// rather than as two implementations that happened to agree.
  ///
  /// Always ends in `.emoji` or `.builtIn`, neither of which can fail to
  /// rasterise, so a slot can never end up with nothing to draw (spec §5).
  static func resolutionOrder(
    for slot: Slot,
    renderMode: RenderMode,
    symbolsSupported: Bool
  ) -> [Candidate] {
    switch slot {
    case .reaction(let reaction):
      var order: [Candidate] = []
      if renderMode == .auto, symbolsSupported,
        let name = reaction.symbolIos, !name.isEmpty
      {
        order.append(.symbol(name))
      }
      order.append(.emoji(reaction.emoji))
      return order

    case .custom(let emoji):
      // The custom pick is a chosen emoji, not an item — it has no symbol of
      // its own to try.
      return [.emoji(emoji)]

    case .another(let appearance):
      let badge = appearance?.badge ?? true
      var order: [Candidate] = []
      // A supplied chrome symbol is skipped under `renderMode: .emoji` exactly
      // like an item's symbol would be. `renderMode` is documented as an
      // escape hatch for when symbol rendering misbehaves; an exception here
      // would mean the escape hatch does not always escape.
      if renderMode == .auto, symbolsSupported,
        let name = appearance?.symbolIos, !name.isEmpty
      {
        order.append(.anotherSymbol(name: name, badge: badge))
      }
      if let emoji = appearance?.emoji, !emoji.isEmpty {
        order.append(.emoji(emoji))
      }
      order.append(.builtIn(badge: badge))
      return order
    }
  }
}
