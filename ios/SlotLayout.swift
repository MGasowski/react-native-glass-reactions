import CoreGraphics

/// Where each slot sits along the row, and which one a point is nearest to.
///
/// Both were previously methods on `ReactionsPillView` — pure arithmetic over
/// `Metrics` and `separatorAfter`, but reachable only through the concrete
/// 800-plus-line view, which is also `SlotGeometry`'s only implementation.
/// `PickerInteraction.focus()` reaches that seam to hit-test; the view's own
/// `layoutSubviews` calls the same centring math to position image views and
/// the separator line. This module is the one thing both call into, so the
/// two can never independently drift.
enum SlotLayout {

  /// Centre of slot `index` in the row's own coordinates.
  ///
  /// Single source of truth for layout, hit-testing, and the selection flight
  /// vector — slots are not uniform once the separator inserts its extra
  /// width. `separatorExtra` is passed in pre-computed rather than derived
  /// here from its components (gap, line width, item spacing): that
  /// arithmetic is `Metrics`'s to own, same as `verticalGap`/`edgeMargin` are
  /// `PickerLayout`'s callers' to decide rather than this module's to know.
  static func centerX(
    at index: Int,
    itemSize: CGFloat,
    itemSpacing: CGFloat,
    contentInset: CGFloat,
    separatorAfter: Int?,
    separatorExtra: CGFloat
  ) -> CGFloat {
    var x = contentInset
      + CGFloat(index) * (itemSize + itemSpacing)
      + itemSize / 2
    if let separatorAfter, index >= separatorAfter {
      x += separatorExtra
    }
    return x
  }

  /// The slot nearest the given local x, clamped to the row. The caller has
  /// already checked the point is inside the row's (tolerance-inset) frame.
  static func nearestIndex(
    atLocalX x: CGFloat,
    count: Int,
    itemSize: CGFloat,
    itemSpacing: CGFloat,
    contentInset: CGFloat,
    separatorAfter: Int?,
    separatorExtra: CGFloat
  ) -> Int? {
    guard count > 0 else { return nil }
    var best = 0
    var bestDistance = CGFloat.greatestFiniteMagnitude
    for index in 0..<count {
      let center = centerX(
        at: index, itemSize: itemSize, itemSpacing: itemSpacing,
        contentInset: contentInset, separatorAfter: separatorAfter,
        separatorExtra: separatorExtra
      )
      let distance = abs(x - center)
      if distance < bestDistance {
        best = index
        bestDistance = distance
      }
    }
    return best
  }
}
