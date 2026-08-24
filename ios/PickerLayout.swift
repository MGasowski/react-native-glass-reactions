import CoreGraphics

/// Where the pill goes, given a trigger and a container to fit inside.
///
/// The one job here — clamp a proposed origin into a container — was
/// previously inline in `begin()`, the same method that also does hit-testing,
/// scroll-disabling and surface sampling. It is pure arithmetic and was never
/// reachable without a real window, so it was also the one piece of geometry
/// in the interaction path with no test coverage.
///
/// `trigger` and `containerSize` must already be in the *container's own*
/// local coordinate space — `(0, 0)` at the container's top-left, same units
/// as `containerSize`. On iOS that is free: the overlay is a `UIWindow`
/// covering the full screen, so window space and overlay space already
/// coincide. Android's container is a `FrameLayout` whose on-screen origin is
/// not guaranteed to be `(0, 0)` (status bar insets and the like), so its
/// adapter does a `getLocationOnScreen` subtraction before calling in — that
/// translation is a platform-specific concern and stays adapter-side rather
/// than migrating into this module, which would otherwise need an iOS branch
/// that does nothing.
enum PickerLayout {

  /// The frame the pill should be given.
  ///
  /// `verticalGap` and `edgeMargin` are parameters rather than constants this
  /// module owns, mirroring how `PickerInteraction` takes `tolerance` rather
  /// than hardcoding it: the actual values are each adapter's to decide, this
  /// module only knows the rule for applying them.
  static func frame(
    trigger: CGRect,
    pillSize: CGSize,
    containerSize: CGSize,
    verticalGap: CGFloat,
    edgeMargin: CGFloat
  ) -> CGRect {
    var origin = CGPoint(
      x: trigger.midX - pillSize.width / 2,
      y: trigger.minY - pillSize.height - verticalGap
    )
    // The upper bound is itself floored at `edgeMargin`: when the pill is
    // wider than the container, `containerSize.width - pillSize.width -
    // edgeMargin` goes negative, and clamping origin.x into a range whose
    // upper bound is below its lower bound would be undefined. Flooring the
    // upper bound collapses the range to a single point at the left margin
    // instead.
    origin.x = min(
      max(edgeMargin, origin.x),
      max(edgeMargin, containerSize.width - pillSize.width - edgeMargin)
    )
    // No upper bound on y: nothing above the pill needs protecting from the
    // pill running off the *bottom* of the container, since it is always
    // anchored above the trigger that opened it.
    origin.y = max(edgeMargin, origin.y)
    return CGRect(origin: origin, size: pillSize)
  }
}
