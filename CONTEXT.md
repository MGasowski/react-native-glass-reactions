# Domain language

The words this codebase uses, and where each one lives. The full reasoning is in
[`reactions-picker-spec.md`](reactions-picker-spec.md) — comments cite it as
"spec §6.5". This file exists so you can recover a term without reading a
section to find it.

Only terms that are load-bearing in the code are listed. If you name a new
concept, add it here.

## The picker

**Trigger** — the consumer's own view that a long-press opens the picker over.
Rendered by `ReactionTrigger`, which wraps children in a plain `View` and
registers that view's tag natively. It owns no appearance.

**Host** — the process-wide singleton that owns the one gesture recognizer and
the trigger registry. `HybridReactionsHost` on both platforms; `ReactionsPickerHost`
is its React-side switch. There is exactly one, which is what makes "only one
picker can exist" structural rather than a matter of where components are placed.

**Pill** — the floating capsule that appears above the trigger: glass on iOS 26,
blur below that, opaque under Reduce Transparency. `ReactionsPillView`. It is the
layout authority — it owns slot positions and is therefore what hit-testing asks.

**Overlay** — the window (iOS) or full-screen layer (Android) the pill is
presented in. A presentation surface only: it never takes touches.

**Layout** (positioning) — where the pill goes within the overlay: centred above
the trigger, sitting `verticalGap` above it, clamped so it never crosses
`edgeMargin` from the overlay's edges. `PickerLayout`. Pure and mirrored, like
`PickerInteraction`; takes the trigger and overlay already in the overlay's own
local coordinate space, so the one genuinely platform-specific step — Android's
`getLocationOnScreen` translation, which iOS's full-screen `UIWindow` overlay
never needs — stays in the host rather than in this module.

## Content

**Slot** — one position in an open picker. Either a *reaction*, the *custom
pick*, or the *another reaction* plus. There is exactly one slot list per
interaction; drawing, hit-testing and selection reporting all index into it.

**Renderable** — a slot resolved down to what is actually drawn: an image, a
label, and whether it is a symbol. Derived from a slot, never built beside one.

**Resolution order** — the ranked list of ways a slot *could* be drawn — a
`Candidate` list from `ReactionResolution`, e.g. "try this symbol, else this
emoji, else the built-in glyph". Pure: it never asks whether a symbol name
actually rasterises, only what order to try. The adapter (the pill) draws the
first candidate that produces an image. Every order ends in an emoji or the
built-in glyph, neither of which can fail to draw, so a slot never blanks.

**Render mode** — `auto` prefers a platform symbol where one is supplied and
resolves, `emoji` forces emoji everywhere and skips every symbol candidate,
including chrome's. Android has no symbol rasteriser of its own yet
(`symbolsSupported = false` in `ReactionResolution`), so its resolution order
never offers one regardless of mode — a capability gap, not the mode being
ignored.

**Another reaction** — the trailing plus that opens the system emoji picker.
Chrome rather than content: it is never reported through `onSelect`, and
releasing on it hands over to the platform picker instead.

**Custom pick** — the emoji previously chosen through "another reaction",
rendered as one extra selectable slot. Its id is the emoji itself, because it
exists in no item list. It travels with the plus: turning the feature off hides
both.

**Separator** — the hairline dividing the consumer's reactions from the "another
reaction" section. Drawn only when both sides exist. It widens the slot it
precedes, which is why slots are not uniformly spaced.

**Surface appearance** — whether the pixels behind the trigger are dark. Sampled
directly (`SurfaceAppearance.isDark`) rather than read from the system theme:
the picker floats over arbitrary app content, so system light/dark says nothing
about what is actually behind it. Named and placed identically on both
platforms — beside the pill, even though the host is what calls it — because
that placement, not just the name, is what a maintainer has to find twice.

## Interaction

**Interaction** — one long-press, from open to release. `PickerInteraction` holds
its rules: which slot is focused, what a release means, where the divider goes.
Constructed from a snapshot at gesture-begin and dropped at dismissal; a
cancelled gesture produces no outcome because there was no release. It holds no
UIKit and no Android framework types, which is what lets it be tested directly.

**Focus** — the slot the finger is currently pointing at. Nothing is focused when
the picker opens: at that instant the finger is still on the trigger below.

**Focus tolerance** — vertical slack around the pill within which a slot still
counts as pointed at. There is deliberately no horizontal slack.

**Upsert with deselect** — picking the reaction that is already selected clears
it rather than re-selecting it. "Already selected" means what the pill was drawn
with, not what the registry holds at release time.

**Celebration** — the pop-and-fly animation played on the chosen slot at release.
It plays for a new selection, a cleared one, and the plus alike — the user chose
that slot either way. A cancelled interaction celebrates nothing.

**Warm / pooled** — the pill is built once, off the critical path, and hidden
rather than destroyed between interactions. Hidden layers are not composited, so
a scrolling list pays nothing, while a long-press never pays construction.
