# Native Reactions Picker — Project Spec

**Status:** Draft v1
**Owner:** TBD
**Package (working name):** `react-native-glass-reactions`
**License:** MIT

---

## 1. Summary

A React Native view component that renders an Instagram-style reactions picker as a **fully native view**, implemented in Swift via Nitro Views on iOS and Kotlin on Android. The interaction (long-press → drag → select) and all animation run natively; JavaScript is involved only at mount and at selection.

On iOS 26+ the picker is rendered with the system Liquid Glass material as a single capsule behind the reactions. On older iOS and on Android, it degrades to a defined non-glass appearance.

Primary consumer use case: scoring reviews on a content platform, where the picker is attached to items inside a long virtualised list.

## 2. Goals

- 120 fps interaction on the oldest supported device, with no JS thread involvement during the gesture.
- Native iOS 26 Liquid Glass appearance.
- Correct gesture arbitration inside `FlatList` / `FlashList` / `ScrollView`.
- Zero required peer dependencies beyond `react-native-nitro-modules`.
- Clean degradation — never a crash, never a build failure, on unsupported OS versions.
- A public API small enough to stay stable across the 1.x line.

## 3. Non-goals

- No backend, no reaction persistence, no aggregation or ranking logic. The library emits a selection event; consumers own storage and scoring.
- No comment threads, feeds, or social primitives.
- No web support.
- No Reanimated integration in core (see §7.3 for the optional entry point).
- No custom animation curves exposed in 1.0. Ship one well-tuned feel; expose knobs only after real usage.

## 4. Architecture

### 4.1 Module type

Nitro **HybridObject** (`ReactionsHost`), chosen for direct Swift↔C++ interop without an Objective-C hop. This is a developer-experience decision, not a performance one — the JS↔native call cost is irrelevant at two calls per interaction.

**Revised:** this originally specified a Nitro *View*. The library now ships no React view managers at all. Since the host presents one pooled native view into its own overlay and triggers are plain RN views the consumer already renders (§4.3, §6.5), a hybrid view had no remaining caller and was removed — which also removes it from the published artifact.

**Hard requirements:** React Native 0.78+ and the New Architecture. Liquid Glass raises the practical floor to RN 0.80+.

### 4.2 Layer split

| Layer | Language | Responsibility |
|---|---|---|
| Spec | TypeScript (`*.nitro.ts`) | Prop and method declarations; source of truth for codegen |
| iOS | Swift | Glass rendering, gesture recognition, animation, haptics |
| Android | Kotlin | Fallback rendering, gesture handling, haptics |
| JS surface | TypeScript | Thin wrapper, platform capability flags, types |

### 4.3 Rendering strategy — single instance

The picker is **not** mounted per list row. Consumers mount one `<ReactionsPickerHost>` near the root; individual `<ReactionTrigger>` components register themselves and request the host to present over their frame.

This is the single most important architectural decision in the library. One glass layer alive at a time instead of N, no native view construction per row, no blur compositing cost while scrolling.

**Presentation is a portal, not a re-parent.** The host presents into a dedicated overlay window above the list (§4.4), so the picker is never clipped by row bounds and z-index never enters the picture. The React tree does not move — the trigger stays where it is and only reports its frame; it is the *native* presentation that is portalled.

**Exactly one picker exists at a time, and only during an interaction.** The picker is absent from the view hierarchy whenever no gesture is in flight. It is attached on long-press and detached when the interaction ends, so a scrolling list is never compositing glass. A second long-press arriving while a previous close is still animating cancels that teardown and reuses the instance rather than racing a second one into existence — the invariant is one picker, enforced by the host, not by consumer discipline.

Two lifecycle details that are easy to get wrong and are correctness, not polish:

- **Teardown is bound to animation-end, not touch-up.** `onSelect` fires at touch-up; the collapse animation runs after it. Detaching at touch-up would cut the animation off mid-flight.
- **A trigger whose row unmounts or scrolls away mid-interaction dismisses the picker without selection.** In a virtualised list this is a routine event, and it is a crash class if unhandled.

### 4.4 iOS implementation notes

- Glass via `UIGlassEffect` on a single capsule behind the whole row.

  **Superseded:** this originally called for per-reaction glass pills inside a `UIGlassContainerEffect` so they would merge below a spacing threshold. The owner's design decision is one container for all reactions, matching Instagram and WhatsApp, so the per-item pills are gone. Revisit only if a future animation actually needs them — separate pills with nothing to animate read as visual noise.
- Animation via `UIViewPropertyAnimator` / `CASpringAnimation`. No Reanimated in the loop — two animation systems writing the same layer will fight.
- Haptics via `UIImpactFeedbackGenerator`, fired from the same code path that detects index change, so visual and tactile feedback are frame-aligned.
- Presentation in a dedicated overlay window or container above the list, so glass is never clipped by row bounds and z-index is a non-issue.

### 4.5 Android implementation notes

Decide the visual language **before** the props schema is finalised — retrofitting a second appearance model into an existing API is painful.

Baseline: a flat translucent capsule with a hairline border, light/dark aware. Spring animation via `SpringAnimation` (dynamic-animation). Haptics via `HapticFeedbackConstants`.

**Revised:** this originally specified a `RenderEffect` blur on API 31+. `View.setRenderEffect` blurs the view's *own* content, not what is painted behind it, so on a plain coloured backdrop it costs GPU time and renders nothing. Android has no true backdrop-blur primitive, so the fallback is an honest flat surface rather than an imitation of glass.

Reduced motion is exposed as the system animator duration scale being zero, not as a dedicated flag — a different check from the iOS one.

Material Symbols are deferred: `symbol.android` requires shipping the Material Symbols font in the AAR, so Android renders emoji only in 1.0. Since `emoji` is required on every item, this costs nothing at the call site.

## 5. Public API (draft)

```ts
type ReactionId = string;

interface ReactionSymbol {
  readonly ios: string;              // SF Symbol name, e.g. 'flame.fill'
  readonly android?: string;         // Material Symbol name; omit to use emoji on Android
}

interface ReactionItem {
  readonly id: ReactionId;
  readonly emoji: string;            // REQUIRED — the universal fallback
  readonly symbol?: ReactionSymbol;  // preferred when renderable and not disabled
  readonly accessibilityLabel: string;
}

interface ReactionTriggerProps {
  readonly items: readonly ReactionItem[];
  readonly selected?: ReactionId;
  readonly onSelect: (id: ReactionId | null) => void;   // null = deselect
  readonly onOpen?: () => void;
  readonly onClose?: () => void;
  readonly disabled?: boolean;
  readonly longPressDuration?: number;   // ms, default 200
}

interface ReactionsPickerHostProps {
  readonly renderMode?: 'auto' | 'emoji';   // default 'auto'
}
```

**Selection model (decided):** one reaction per user per item — upsert, not additive. `selected` is a single `ReactionId | undefined`; picking a different reaction replaces the current one, and picking the currently-selected reaction emits `null` (deselect). Multi-select is a possible post-1.0 addition; if it lands it arrives as a separate opt-in prop with a widened callback, not by changing the meaning of `selected`.

**Reaction content model (decided):** symbols preferred, emoji guaranteed.

`emoji` is **required on every item** and `symbol` is optional. This is deliberate and load-bearing: symbols and emoji are not interchangeable representations of each other — nothing lets the library derive 🔥 from `flame.fill` — so a fallback only exists if the item carries it. Making emoji mandatory is what turns `renderMode` into a safe global kill switch rather than a setting that can blank out the picker.

Resolution order per item under `renderMode: 'auto'`:

| Platform | Preferred | Falls back to |
|---|---|---|
| iOS | `symbol.ios`, if the symbol resolves at runtime | `emoji` |
| Android | `symbol.android`, if provided and resolvable | `emoji` |

`renderMode: 'emoji'` forces emoji everywhere and ignores `symbol` entirely — the escape hatch if symbol rendering proves problematic on either platform. It is a union rather than a boolean so a future `'symbol'` (force, no fallback) is additive.

**Android does not get SF Symbols.** The SF Symbols set is licensed for Apple platforms and its font cannot be shipped in an Android artifact; `symbol.android` therefore names a *Material Symbol*, a different set with different names. Consumers who want symbols on both platforms configure both, and consumers who omit `symbol.android` get emoji on Android with no extra work. This is the reason `symbol` is a record with per-platform fields rather than a single string.

Symbols are monochrome and take a tint, where emoji carry their own color. The picker therefore owns a small tint treatment for symbol rendering (default and selected states); this is the one piece of appearance the library owns, and it is deliberately not consumer-themable in 1.0.

Exports:

- `ReactionsPickerHost` — root-level host, **required in 1.0** (see below).
- `ReactionTrigger` — per-item trigger; a transparent wrapper around consumer children (see below).
- `isLiquidGlassSupported: boolean` — runtime capability flag.
- `fadeIn` / `fadeOut` handled natively via a prop; **not** via consumer-side opacity (see §6.3).

**Host is required (decided).** The single-instance guarantee is enforced natively — the host is backed by a process-wide native singleton, not by React — so auto-hosting would be technically feasible. It is nonetheless required in 1.0 for one reason: **a requirement can be relaxed in a minor version, but never added back without breaking every consumer.** Shipping required-then-optional is a non-breaking path; shipping optional-then-required is not. The explicit host also gives a deterministic point to warm the glass container (§6.5) rather than warming it at first trigger mount, which may land mid-scroll. Revisit once the presentation target is settled at M2.

**Trigger is render-prop only (decided).** `ReactionTrigger` wraps consumer children and owns no appearance: no colors, sizes, typography, or theme API. This keeps the §5 surface small enough to hold still across 1.x, and it costs nothing at runtime — the plain wrapper `View` is the backing native view the host converts coordinates from at gesture-begin (§6.5), so it is a view the consumer was rendering anyway. Displaying the *selected* reaction after an interaction is the consumer's job, rendered from the `selected` value they already own per §3. The example app ships a complete styled trigger as a copyable recipe; the library does not.

Design rules: no `any`, all props `readonly`, discriminated unions over boolean soup, TypeScript strict mode on.

## 6. Implementation constraints

### 6.1 Build-time (highest risk)

Liquid Glass symbols come from the iOS 26 SDK. A consumer on an older Xcode gets a **compile failure**, not a graceful degrade.

- Guard glass code with compiler-version checks so the library still builds on older toolchains.
- Guard usage at runtime with `@available(iOS 26.0, *)` **and** a runtime API-availability check — some iOS 26 builds shipped without the API and crashed.
- Keep the deployment target low (iOS 15) so the package installs broadly.
- State the Xcode 26 requirement in the first paragraph of the README.

### 6.2 Distribution

Not supported in Expo Go. Requires a development build. An Expo config plugin must ship with 1.0 or Expo adoption will not happen.

The plugin is not merely a convenience: it must set `CADisableMinimumFrameDurationOnPhone` in `Info.plist`, without which iOS caps animation at 60 fps on ProMotion iPhones and the 120 fps goal in §2 is unreachable. Bare consumers must set it themselves, and the README must say so.

### 6.3 Known platform traps

- Setting `opacity: 0` on a glass view **or any ancestor** disables the effect entirely. Consumers must not fade the picker with Reanimated/Animated opacity — expose a native fade instead and document this loudly.
- Rounded corners + masking + blur triggers offscreen rendering. Verify with "Color Offscreen-Rendered Yellow" before release.
- Glass rendering has regressed across iOS point releases historically. Pin a device/OS test matrix and re-verify each iOS minor.
- Respect **Reduce Transparency** and **Reduce Motion** accessibility settings.
- **Simulator runtimes can ship unable to render emoji at all** — every emoji draws as `.notdef`, through any API, including plain React Native `<Text>`. Observed on iOS 26.3.1 (23D8133); correct on 26.5 (23F77). Before debugging emoji rendering in this library, render the same string through RN `<Text>` as a control: if that is boxes too, the runtime is at fault and the native code is fine. Verify emoji on a known-good runtime or a device, never on a single simulator.

### 6.4 Gesture arbitration (hardest correctness problem)

Write and test this **before** the animation work — the animation is easy once ownership of the touch is unambiguous.

- **iOS:** implement `UIGestureRecognizerDelegate`; coordinate with the enclosing scroll view's `panGestureRecognizer`; define `shouldRecognizeSimultaneouslyWith` behaviour explicitly.
- **Android:** call `requestDisallowInterceptTouchEvent` on the parent once the long-press threshold is crossed; handle nested scrolling.
- Must coexist with `react-native-gesture-handler`, which most consumers use.
- Acceptance: opening the picker inside a scrolling `FlashList` never scrolls the list, and a vertical drag that starts before the threshold always scrolls.

### 6.5 Runtime performance (primary quality bar)

The library's cost is dominated by what it does when the picker is **closed** — that is the state a consumer's app spends ~100% of its time in, across every row of a long list. Budget: a screen containing 20 triggers must profile identically to the same screen with the triggers removed.

**Nothing per-row may be native.** §4.3 already bans a picker per row; this extends it to the trigger. A `ReactionTrigger` must not construct a Nitro view, a `UIVisualEffectView`, or a gesture recognizer of its own. N recognizers on N rows means N hit-test participants on every touch and N objects churned by cell recycling.

Instead, **one recognizer lives on the host**, installed above the list, and hit-tests against the registered trigger frames itself. This inverts §6.4 slightly — arbitration is negotiated once between the host's recognizer and the enclosing scroll view, not renegotiated per row — and it is the design that makes the 1k-row acceptance criterion in M5 achievable rather than merely survivable.

**Registration must not touch React state.** Triggers register into a mutable ref-backed registry on the host; registering or unregistering never triggers a re-render, of the host or of anything else. A `useState` in the registry path turns every cell recycle into a render of the whole list.

**JS must be off the scroll path.** Trigger frames are registered at layout time only. They go stale the instant the list scrolls, and the fix is *not* to push updates from JS — it is to resolve the trigger's frame natively at gesture-begin, converting from the trigger's backing view to window coordinates. Any design where scrolling produces JS work is an immediate regression, regardless of how cheap the per-event work looks.

**The picker is detached when closed, and pooled rather than deallocated.** Per §4.3, no picker is in the hierarchy between interactions — that is what guarantees zero blur compositing during scroll, which is the cost that actually matters. But *detached* and *deallocated* are different things, and the distinction is worth holding onto:

| State between interactions | GPU cost | Memory | Cost at next open |
|---|---|---|---|
| Attached, `isHidden = true` | none | one instance | none |
| Detached, instance pooled | none | one instance | re-attach only |
| Deallocated | none | none | full construction, on the critical path |

Detaching already buys the entire GPU saving; deallocating buys only the memory of a single view and charges full construction of the glass container to every long-press — landing directly on the latency-critical moment the user is waiting on. So: **detach on close, retain the instance in the host, warm it once at host mount off the critical path.** Never hidden via opacity (§6.3 — that disables the effect outright).

> *Open for the owner to overrule:* the stated preference was to destroy the picker on touch release. The lifecycle above is behaviourally identical from the consumer's point of view — one picker, absent while scrolling — and differs only in whether the host keeps the object around to reuse. Measure both in M3 before deciding, but the expectation is that true teardown shows up as first-frame jank on every open.

**Animate transforms, not geometry.** Animating `bounds`/`frame` on a blurred layer re-evaluates the effect every frame. Drive expand/collapse with transform and let `UIGlassContainerEffect` own the merge/separate geometry natively; do not hand-animate the union.

**Avoid offscreen passes.** Rounded corners plus a mask layer plus blur forces an offscreen render pass and will not hold 120 fps. Use layer `cornerRadius` with `cornerCurve = .continuous`; no `mask` layers, and never `shouldRasterize` on a blurred layer.

**Prepare haptics on open,** not on index change — an unprepared `UIImpactFeedbackGenerator` has first-fire latency that breaks the frame alignment §4.4 asks for.

**Cache rendered reactions.** Whatever §11.1 settles on, each reaction is rasterised once into a reusable layer/image at host warm-up. No text layout on open.

**ProMotion gate:** iOS caps animations at 60 fps on ProMotion iPhones unless `CADisableMinimumFrameDurationOnPhone` is set in `Info.plist`. The 120 fps goal in §2 is unreachable without it, so the Expo config plugin (§6.2) must set it and the README must state it for bare consumers.

**Acceptance:** profiled in Instruments on the oldest supported device — no dropped frames scrolling a 1k-row list with triggers present; no dropped frames across open/drag/select/close; zero "Color Offscreen-Rendered Yellow" regions during the interaction.

## 7. Animation & dependencies

### 7.1 Core has no animation peer dependency

Zero required peers is a major adoption advantage. All animation is native.

### 7.2 Consumer-side animation

`Animated.createAnimatedComponent(ReactionTrigger)` must work for standard transform styles on a wrapping view. Custom Nitro props driven per-frame from JS are **explicitly unsupported** in 1.0 — Nitro views use Nitro's own prop parsing, and per-frame prop writes are unexplored territory. Document what is supported and say nothing about the rest.

### 7.3 Optional Reanimated entry point (post-1.0)

If demanded, ship `react-native-glass-reactions/reanimated` exposing an open-progress shared value, with:

```json
"peerDependenciesMeta": { "react-native-reanimated": { "optional": true } }
```

## 8. Repository & OSS setup

### 8.1 Scaffolding

`npx create-react-native-library@latest`, Nitro module template (includes an example app; Nitro's own template omits one). Budget one day for template friction — there have been reported issues with freshly generated Nitro libraries failing the Android example build on duplicate dependency registration.

### 8.2 Repo layout

```
/src            TypeScript surface + *.nitro.ts specs
/nitrogen       generated bindings — COMMITTED
/ios            Swift implementation
/android        Kotlin implementation
/example        RN example app (bare + Expo dev-client instructions)
/plugin         Expo config plugin
/docs           usage docs, platform matrix, migration notes
/.github        CI workflows, issue templates, PR template
```

**Commit the generated Nitrogen bindings.** Consumers must never run the code generator. This is the difference between a library that installs cleanly and weekly "build fails" issues.

Note: Nitro expects Kotlin files under the `com.margelo` namespace. Accept it and document it; it will appear in the published Android artifact.

### 8.3 Tooling standards

- TypeScript strict mode, no `any`, `unknown` where genuinely unknown.
- ESLint + Prettier, enforced in CI.
- kebab-case filenames, PascalCase components.
- `StyleSheet.create` in the example app; no inline styles in JSX.
- Conventional commits + `release-it` (Bob template default — leave it alone and use it).
- SwiftLint and ktlint for the native side.

### 8.4 CI (GitHub Actions)

TypeScript tests catch almost nothing in a native library. CI must **compile the example app on both platforms on every PR**.

| Job | Purpose |
|---|---|
| `lint` | ESLint, Prettier, tsc `--noEmit`, SwiftLint, ktlint |
| `build-ios` | Build example on Xcode 26, min + latest supported RN |
| `build-android` | Build example, min + latest supported RN |
| `e2e` | Maestro flow: open picker, drag, select, dismiss |
| `release` | Tag-triggered npm publish with provenance |

Do not attempt a full RN version matrix. Pin a documented minimum and the latest, and support exactly those.

### 8.5 Versioning policy

- `react-native-nitro-modules` peer range: **pinned floor and ceiling**, never `"*"`. Nitro is pre-1.0 and ships frequently; expect to cut releases when it does.
- Semver strictly. The API in §5 is the 1.x contract.
- Maintain a support matrix table in the README: library version × RN version × Nitro version × min Xcode × min iOS.

### 8.6 Documentation

- README: what it looks like (GIF, recorded on device), requirements banner (Xcode 26+, RN 0.80+, New Arch, not Expo Go), install, minimal example, platform support table.
- Note that Expo Snack cannot run this; link a buildable example instead.
- `CONTRIBUTING.md` covering the Nitrogen regeneration workflow.
- Issue templates that require: RN version, Nitro version, Xcode version, iOS version, New Arch yes/no.
- `CODE_OF_CONDUCT.md`, `LICENSE` (MIT), `SECURITY.md`.

## 9. Milestones

| # | Milestone | Exit criteria | Status |
|---|---|---|---|
| M0 | Scaffold | Nitro template builds on both platforms in CI | **Done** — both example apps build locally; CI workflow present |
| M1 | Static glass view | Glass pill renders on iOS 26; plain view fallback elsewhere; no crash | **Done** — verified on iOS 26.5 and Android |
| M2 | Host + gesture arbitration | Single-instance host, portal presentation, trigger registration, one host-owned recognizer; opens and selects correctly inside a scrolling FlashList on both platforms | **Done** — verified on a 1000-row `FlatList` on both platforms; open, drag, select, deselect, and plain-scroll all correct. `FlashList` itself untested |
| M3 | Animation & haptics | Expand/collapse tuned; haptics frame-aligned; Reduce Motion respected; picker lifecycle (§6.5) measured pooled vs. deallocated; profiled clean in Instruments | **Partial** — springs, stagger, focus, haptics and Reduce Motion shipped. **Instruments pass and the pooled-vs-deallocated measurement are outstanding and need a real device** |
| M4 | Android parity | Defined fallback appearance and interaction shipped | **Done** — flat translucent capsule, light/dark aware, full interaction. Material Symbols deferred: emoji only on Android in 1.0 |
| M5 | Scale validation | 1k-row list scrolls indistinguishably from the same list without triggers; §6.5 acceptance gate met on the oldest supported device | **Blocked on hardware** — the 1000-row example exists and scrolls correctly, but simulator numbers do not establish the gate. Needs a device |
| M6 | OSS hardening | Config plugin, docs, E2E, support matrix, issue templates | **Partial** — config plugin, README + support matrix, SECURITY, CONTRIBUTING Nitrogen workflow, issue-template fields, and the glass-guard CI check are done. **E2E flow not written** |
| M7 | 1.0.0 | Published, provenance-signed, announcement written | Not started — publishing is the owner's call |

## 10. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Xcode < 26 breaks consumer builds | Critical — unusable for many | Compiler guards; documented requirement; CI asserts guard placement via `yarn check:glass-guards` — **not** a full old-toolchain build, which React Native's own pinned toolchain makes impractical |
| Glass regressions across iOS minors | High | Device/OS test matrix; re-verify each iOS release |
| Gesture conflicts inside lists | High — top support cost | Build first; E2E coverage; explicit RNGH interop test |
| Per-row cost degrades host app scroll | Critical — the failure consumers actually notice | §6.5: nothing native per row, no JS on the scroll path, ref-backed registration; Instruments gate on a 1k-row list |
| Nitro pre-1.0 breaking changes | Medium | Pinned peer range; track releases; changelog discipline |
| `com.margelo` namespace in artifact | Low | Documented, accepted |
| Android fallback disappoints | Medium | Set expectations in README; iOS-first positioning is explicit |

## 11. Open questions

1. Minimum supported RN — 0.80 (glass floor) or higher to reduce the test matrix? *Recommendation: 0.80; glass sets the floor anyway and going higher costs adoption for little test-matrix relief.*

Resolved, all in §5:

- Selection model — single-select upsert.
- Reaction content — SF/Material Symbols preferred, emoji required as guaranteed fallback, `renderMode` as kill switch.
- Host — required in 1.0, native singleton underneath, relaxable later.
- Trigger appearance — render-prop only, no theme API.

Rive/Lottie was considered and rejected for 1.0: it contradicts the zero-peer-dependency positioning in §7.1 and puts a second animation system in the loop, against §4.4.
