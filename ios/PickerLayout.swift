import CoreGraphics

/// Where the pill goes, given a press and a container to fit inside.
///
/// The one job here — place a pill relative to a press and keep it inside a
/// container — was previously inline in `begin()`, the same method that also
/// does hit-testing, scroll-disabling and surface sampling. It is pure
/// arithmetic and was never reachable without a real window, so it was also
/// the one piece of geometry in the interaction path with no test coverage.
///
/// The two axes are anchored to deliberately different things. Vertically the
/// pill hangs off the *touch point*, because the problem being solved is the
/// thumb covering the pill — and a press near the bottom of a tall bubble is
/// nowhere near that bubble's top edge. Horizontally it centres on the
/// *trigger*, because the thumb occludes nothing sideways: a finger-relative
/// x would only make the pill wander depending on where in a row you happened
/// to press.
///
/// `touch`, `trigger` and `containerBounds` must all be in the *container's
/// own* local coordinate space — same origin, same units. On iOS that is
/// free: the overlay is a `UIWindow` covering the full screen, so window space
/// and overlay space already coincide. Android's container is a `FrameLayout`
/// whose on-screen origin is not guaranteed to be `(0, 0)` (status bar insets
/// and the like), so its adapter does a `getLocationOnScreen` subtraction
/// before calling in — that translation is a platform-specific concern and
/// stays adapter-side rather than migrating into this module, which would
/// otherwise need an iOS branch that does nothing.
enum PickerLayout {

  /// The frame the pill should be given.
  ///
  /// `containerBounds` is a rect rather than a size because the region the
  /// pill must stay inside is not the whole window: it is the window minus
  /// the status bar, home indicator and any display cutout. Adapters pass the
  /// already-inset safe rect, which also handles a landscape notch without
  /// this module knowing what a notch is. `edgeMargin` is the cosmetic gap
  /// applied *inside* that rect.
  ///
  /// The gaps and the margin are parameters rather than constants this module
  /// owns, mirroring how `PickerInteraction` takes `tolerance` rather than
  /// hardcoding it: the actual values are each adapter's to decide, this
  /// module only knows the rule for applying them. `gapAbove` is the larger of
  /// the two — it has to clear the ~20–30pt of fingertip that extends past the
  /// reported touch centre, where `gapBelow` is under the hand regardless and
  /// spending screen on it buys nothing.
  ///
  /// The vertical rule: place above; if that would be clipped by the safe rect
  /// *and* the below placement fits inside it entirely, flip below; otherwise
  /// keep the above placement and clamp. Preferring above rather than
  /// whichever side has more room keeps the placement continuous — the pill
  /// never snaps sides as the finger crosses a midpoint — and means every
  /// case that fits above behaves identically to before the flip existed.
  static func frame(
    touch: CGPoint,
    trigger: CGRect,
    pillSize: CGSize,
    containerBounds: CGRect,
    gapAbove: CGFloat,
    gapBelow: CGFloat,
    edgeMargin: CGFloat
  ) -> CGRect {
    let minX = containerBounds.minX + edgeMargin
    let minY = containerBounds.minY + edgeMargin
    let maxY = containerBounds.maxY - edgeMargin

    // The upper bound is itself floored at `minX`: when the pill is wider than
    // the container, `containerBounds.maxX - pillSize.width - edgeMargin` goes
    // below the left margin, and clamping into a range whose upper bound is
    // beneath its lower bound would be undefined. Flooring the upper bound
    // collapses the range to a single point at the left margin instead.
    let x = min(
      max(minX, trigger.midX - pillSize.width / 2),
      max(minX, containerBounds.maxX - pillSize.width - edgeMargin)
    )

    let above = touch.y - gapAbove - pillSize.height
    let below = touch.y + gapBelow
    let y: CGFloat
    if above < minY && below + pillSize.height <= maxY {
      y = below
    } else {
      y = max(minY, above)
    }

    return CGRect(origin: CGPoint(x: x, y: y), size: pillSize)
  }
}
