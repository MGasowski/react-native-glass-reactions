import Foundation

/// A colour supplied by the consumer, parsed out of its hex string.
///
/// Pure, and deliberately not a `UIColor`: parsing is the part with rules worth
/// testing — how many digits, which ones repeat, what an unparseable string
/// does — and none of those rules need a colour space or a UIKit target. The
/// pill turns this into a `UIColor` at the point it tints a glyph, the same way
/// the host maps Nitro structs at its own boundary.
///
/// Components are 0...1, matching what `UIColor` takes.
struct SymbolColor: Equatable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double
}

extension SymbolColor {
  /// Parses `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`, with the leading `#`
  /// optional. Alpha defaults to opaque.
  ///
  /// Returns `nil` for anything else rather than substituting a colour: a
  /// typo'd string should leave the symbol at its default `.label`, which is
  /// always legible, instead of painting it some silently chosen fallback.
  init?(hex: String) {
    var digits = hex.trimmingCharacters(in: .whitespaces)
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.allSatisfy(\.isHexDigit) else { return nil }

    let channels: [String]
    switch digits.count {
    // Shorthand repeats each digit — `#f80` is `#ff8800`, not `#0f0800`.
    case 3, 4:
      channels = digits.map { String(repeating: $0, count: 2) }
    case 6, 8:
      channels = stride(from: 0, to: digits.count, by: 2).map { offset in
        let start = digits.index(digits.startIndex, offsetBy: offset)
        let end = digits.index(start, offsetBy: 2)
        return String(digits[start..<end])
      }
    default:
      return nil
    }

    let values = channels.compactMap { UInt8($0, radix: 16) }
    guard values.count == channels.count else { return nil }

    red = Double(values[0]) / 255
    green = Double(values[1]) / 255
    blue = Double(values[2]) / 255
    alpha = values.count == 4 ? Double(values[3]) / 255 : 1
  }
}

// MARK: - Paint

/// What a consumer's `symbol.color` asked for.
///
/// Three cases because they are three different rasteriser calls, not three
/// shades of one: `.multicolor` asks SF Symbols for the glyph's *own* palette
/// and must be drawn in original rendering mode, `.solid` draws the template
/// glyph and tints it, and `.default` leaves the library's own treatment
/// alone. Collapsing multicolor into "a colour" would describe a call that is
/// not the one made.
enum SymbolPaint: Equatable {
  /// No colour asked for, or one that could not be read. The library's tint
  /// treatment applies, including the change on selection.
  case `default`
  /// The symbol's built-in palette, as Apple drew it.
  case multicolor
  case solid(SymbolColor)

  /// The keyword that asks for the glyph's own palette. Not a colour, so it
  /// cannot collide with a hex string.
  static let multicolorKeyword = "multicolor"

  /// Reads the raw string off an item. `nil`, empty, and anything
  /// unrecognisable all mean `.default` — a typo leaves the symbol legible
  /// rather than painting it something nobody chose.
  init(_ value: String?) {
    guard let value else {
      self = .default
      return
    }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.lowercased() == Self.multicolorKeyword {
      self = .multicolor
    } else if let color = SymbolColor(hex: trimmed) {
      self = .solid(color)
    } else {
      self = .default
    }
  }
}
