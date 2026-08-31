# 2. The picker is anchored to the thumb, and flips when it will not fit

Date: 2026-08-31

## Status

Accepted.

## Context

`PickerLayout` placed the pill's bottom edge `verticalGap` (8pt) above the
*trigger's top edge*, centred on the trigger's midpoint, and floored the result
at `edgeMargin` from the container's top.

Two things are wrong with that in the hand.

A trigger is not a point. On a short chat row the trigger's top and the finger
are within 20pt of each other and the distinction never surfaces; on a 200pt
image bubble pressed near its bottom, the pill opens most of a screen away from
the thumb that opened it. The distance from the thumb — the thing the user
actually perceives — is a function of the trigger's height, which is the wrong
variable.

And the floor is not a fallback, it is a failure. A press near the top of the
screen produced a pill jammed against the container's top edge, overlapping the
trigger and the finger both. `edgeMargin` was also measured from the container's
own origin, and on iOS that container is a full-screen `UIWindow`, so the pill
could be clamped to a position underneath the status bar.

## Decision

The two axes are anchored to different things, on purpose.

- **Vertically the pill hangs off the touch point.** `bottom = touch.y -
  gapAbove`. The distance from the thumb is now constant regardless of what was
  pressed.
- **Horizontally it still centres on the trigger.** The thumb occludes nothing
  sideways, so a finger-relative x buys no visibility and costs positional
  stability — the pill would wander depending on where in a row you happened to
  press. The asymmetry is the point: the vertical anchor exists to solve
  occlusion, and there is no occlusion to solve on the other axis.

`containerSize: CGSize` became `containerBounds: CGRect` — the safe area, passed
in by the adapters (`bounds.inset(by: safeAreaInsets)` on iOS, window insets
resolved against the decor view on Android). The module already reasoned about
"the container I must fit inside"; a rect is that container stated honestly
instead of assuming its origin is `(0, 0)`. Landscape cutouts are handled by the
same clamp without this module learning what a cutout is. `edgeMargin` survives
as the cosmetic gap applied *inside* that rect.

The vertical rule is **prefer above, flip only when the flip helps**: place
above; if that placement falls outside the safe rect *and* the below placement
fits inside it entirely, flip; otherwise keep the above placement and clamp.
The flipped pill is placed below the *touch*, not below the trigger, for the
same reason the above case is.

`gapAbove` (44) and `gapBelow` (24) are separate parameters. Measured from a
touch point rather than an edge, the gap has to absorb the finger: the reported
touch centre sits inside the contact patch and a thumb extends another 20–30pt
past it. Below the press the hand shadows the pill whatever the distance, so
that gap is smaller.

`frame()` returns a bare rect. Callers derive the direction with
`frame.minY >= touch.y` and set the pill's anchor point / pivot from it, so a
flipped pill grows downward out of its top edge instead of upward into the hand.

## Alternatives rejected

- **Keeping the trigger as the vertical anchor for short rows** (`min(touch.y,
  trigger.top)`). Reverts to the old behaviour for exactly the common case, so
  short and tall triggers would feel different from each other.
- **Anchoring the flipped pill below the trigger's bottom edge**, as iOS context
  menus do. It does not fix occlusion — the hand extends well past a chat row's
  bottom — and reintroduces the tall-trigger inconsistency the change exists to
  remove.
- **Flipping to whichever side has more room.** Introduces a discontinuity: the
  pill snaps sides as the finger crosses a midpoint. Preferring above means every
  case that works today keeps working identically, and the flip is a strict
  addition.
- **Returning `(frame, placement)` instead of a bare rect.** The direction is
  genuinely an output of this decision, and inferring it back out of the frame is
  recomputing the answer from the answer. It was rejected to keep the change
  inside `PickerLayout`; the seam to watch is that if `gapAbove`/`gapBelow` are
  ever tuned such that a below-placed pill can begin above the touch, the
  inference and the module will silently disagree. `minY >= touch.y` was chosen
  over a midpoint comparison specifically so the clamped fallback — which can
  straddle the finger — reads as *above* and keeps its existing motion.
- **A single gap used in both directions.** Simpler, but the two directions have
  genuinely different jobs; one value would be tuned for the case that fires
  99% of the time and merely tolerated in the other.
- **Inflating the touch into a "finger box" rect** and reusing the existing
  8pt-from-an-edge signature. To keep the trigger-centred x, the caller would
  have to build a rect with its x-span from the trigger and its y-span from the
  finger and pass it to a parameter named `trigger` — a lie in the type, to save
  one float.

## Consequences

- Placement above the fold is unchanged in feel but not in number: the pill is
  now 44pt from the finger rather than 8pt from the row's edge. Expect to tune
  both constants on device; they are private native constants
  (`Layout.gapAbove`/`gapBelow` on iOS, `gapAbovePx`/`gapBelowPx` on Android) and
  nothing in `src/` exposes them, so tuning is not an API change.
- The safe-rect switch fixes a pre-existing bug incidentally: on iOS the clamped
  fallback could previously place the pill under the status bar. That case now
  lands below it, which will read as a behaviour change nobody asked for.
- `prepareForPresentation` gained a `growingDownward` parameter on both
  platforms. The per-item cascade still rises regardless of direction; it was
  left alone deliberately.
- Android now reads window insets through the framework `WindowInsets` API with
  a version split at API 30, rather than adding `androidx.core` as a dependency
  for one call.
- Both `PickerLayout` test suites were rewritten rather than extended: three
  cases encoded the old contract outright. Literal parity between the suites is
  maintained by hand, as ADR 0001 requires.
