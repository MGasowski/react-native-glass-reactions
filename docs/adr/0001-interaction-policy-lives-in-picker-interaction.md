# 1. Interaction policy lives in PickerInteraction; the hosts are adapters

Date: 2026-08-23

## Status

Accepted.

## Context

`HybridReactionsHost` did six jobs on each platform: the trigger registry,
gesture arbitration, surface sampling, anchoring geometry, the emoji-picker
handoff, and the rules of the interaction itself — which slot is focused, what a
release means, when a divider is drawn.

Those rules are where the change is. Four of the fixes in the run-up to 0.1.x
were focus and selection corrections (`d8dd2e7`, `982c937`, `b241472`,
`77fdc43`), and every one had to be found by pressing a real device, because the
rules could not be reached without a `UIWindow` and a live gesture. The rules
were also spread across five methods, so answering "what does releasing here do"
meant reading `begin`, `index(at:)`, `updateFocus`, `end` and `dismiss` in order
and holding the result in your head.

The slot list made this worse. It was built twice from the same conditions —
once as ids for reporting, once as renderables for drawing — with the two
deliberately differing in length by one, because `focusedIndex == activeItems.count`
was how "the user released on the plus" was detected. Nothing enforced that the
two constructions stayed in step.

## Decision

The rules move into `PickerInteraction`, one per platform, mirrored literally.

- It is a **per-interaction value**, constructed at gesture-begin and dropped at
  dismissal. The registry, the recognizer and the windows stay on the host. "No
  interaction" is the absence of the value, so a focused index cannot outlive the
  press it belongs to.
- It reasons over **one slot list**. `Slot` is `reaction` / `custom` / `another`,
  and renderables are *derived from* it rather than built beside it, so releasing
  on the plus is a case rather than arithmetic over two arrays.
- It answers `focus(at:) -> FocusChange` (`unchanged` / `moved` / `cleared`) and
  `release() -> Outcome` (`select` / `deselect` / `another` / `cancel`). The
  host switches on the answers and performs the effects; the interaction emits no
  intents and performs nothing.
- It **holds no framework types**. Inputs are its own `Reaction` and
  `AnotherReactionAppearance`; the hosts map the Nitro-generated structs at the
  boundary. This is not stylistic on iOS: `NativeReactionItem` there is a
  typealias onto a C++ struct, and carrying it inward would put the module behind
  CocoaPods and C++ interop.
- Slot *geometry* stays on the pill, reached through a one-method `SlotGeometry`
  seam. The pill positions the reactions; it must also be what decides which one
  a point is over.
- `selectedId` is **snapshotted** at gesture-begin like every other input. It was
  previously the one field re-read from the registry at release time, so a
  mid-press `updateTrigger` could make the deselect comparison disagree with the
  pill the user was looking at.

Two implementations rather than one shared C++ core: the host must stay native
regardless, there is no hand-written C++ in this repo, and enums with associated
values are the most awkward thing to carry across that boundary. The win is that
divergence becomes a readable diff between two small files. They are therefore
held to literal parity — same file name, type names, case names, method names,
and test cases in the same order.

## Consequences

- The rules are testable without a device: `swift test` on a package that
  compiles one file, and a plain JVM `testDebugUnitTest` on Android. 23 cases
  each, running in milliseconds, covering the tolerance rules, the no-double-tick
  rule, the plus slot, and upsert-with-deselect.
- Compiling `PickerInteraction.swift` for macOS is a purity guard in the spirit
  of `scripts/check-glass-guards.mjs`: a `UIKit` import or a Nitro type fails CI.
- Behaviour changed in one respect, deliberately — see the `selectedId` snapshot
  above. It is a changelog entry, not a silent side effect.
- Android's hit area became half-open on its trailing edges, matching
  `CGRect.contains`, so the two platforms now agree to the pixel.
- The hosts keep everything physical. They are adapters: touches in, interaction
  calls out, animations and haptics back.
- Parity is maintained by hand. A shared test-vector fixture both suites read
  would make it structural; that is worth revisiting if the two ever drift.
