<img src="assets/banner.png" alt="react-native-glass-reactions — fully native reactions picker for React Native" width="100%">

<p align="center">
  <a href="https://www.npmjs.com/package/react-native-glass-reactions"><img alt="npm version" src="https://img.shields.io/npm/v/react-native-glass-reactions?style=flat-square"></a>
  <a href="https://www.npmjs.com/package/react-native-glass-reactions"><img alt="npm downloads" src="https://img.shields.io/npm/dm/react-native-glass-reactions?style=flat-square"></a>
  <a href="https://github.com/MGasowski/react-native-glass-reactions/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/MGasowski/react-native-glass-reactions/ci.yml?branch=main&style=flat-square"></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/npm/l/react-native-glass-reactions?style=flat-square"></a>
  <br>
  <img alt="platforms" src="https://img.shields.io/badge/platforms-iOS%20%7C%20Android-lightgrey?style=flat-square">
  <img alt="React Native" src="https://img.shields.io/badge/React%20Native-0.80%2B-61DAFB?style=flat-square&logo=react&logoColor=white">
  <img alt="New Architecture" src="https://img.shields.io/badge/New%20Architecture-required-blue?style=flat-square">
  <img alt="Xcode" src="https://img.shields.io/badge/Xcode-26%2B-147EFB?style=flat-square&logo=xcode&logoColor=white">
</p>

An Instagram-style reactions picker rendered as a **fully native view** — Swift on iOS, Kotlin on Android. The long-press, drag and select interaction and every animation run natively. JavaScript is involved twice per interaction: once at mount, once at selection.

On iOS 26 the picker is drawn with the system **Liquid Glass** material. On older iOS and on Android it degrades to a defined flat surface. It never crashes and never fails a build on an unsupported OS.

<table>
<tr>
<td align="center" width="33%"><b>iOS 26 — Liquid Glass</b></td>
<td align="center" width="33%"><b>iOS — glass off</b></td>
<td align="center" width="33%"><b>Android</b></td>
</tr>
<tr>
<td><img src="assets/demo-ios-glass.gif" alt="Liquid Glass picker on iOS 26" width="100%"></td>
<td><img src="assets/demo-ios-fallback.gif" alt="Opaque fallback picker under Reduce Transparency" width="100%"></td>
<td><img src="assets/demo-android.gif" alt="Flat translucent picker on Android" width="100%"></td>
</tr>
<tr>
<td align="center"><sub>Translucent capsule — the artwork behind it shows through</sub></td>
<td align="center"><sub>Opaque capsule, under Reduce Transparency — same coloured symbols</sub></td>
<td align="center"><sub>Flat translucent capsule, emoji everywhere</sub></td>
</tr>
</table>

Same gesture and the same JavaScript in all three: long-press, drag across the row, release. Only the capsule material and the reaction rendering differ per platform.

> **Requirements — read before installing.**
> **Xcode 26+** is required to build the iOS side. A consumer on an older Xcode gets a *compile failure*, not a graceful degrade.
> Also required: **React Native 0.80+**, the **New Architecture**, and `react-native-nitro-modules`.
> **Not supported in Expo Go** — you need a development build.

<img src="assets/install.png" alt="Install" width="100%">

```bash
npm install react-native-glass-reactions react-native-nitro-modules
```

Expo projects must add the config plugin. It is not optional decoration: iOS caps animation at 60 fps on ProMotion iPhones unless `CADisableMinimumFrameDurationOnPhone` is set, which puts the 120 fps target out of reach.

```json
{
  "expo": {
    "plugins": ["react-native-glass-reactions"]
  }
}
```

Bare projects should set that key in `Info.plist` themselves.

<img src="assets/usage.png" alt="Usage" width="100%">

Mount the host once near the root of your app, then wrap anything you want to be long-pressable.

```tsx
import {
  ReactionsPickerHost,
  ReactionTrigger,
  type ReactionItem,
} from 'react-native-glass-reactions';

const REACTIONS: readonly ReactionItem[] = [
  { id: 'like', emoji: '👍', symbol: { ios: 'hand.thumbsup.fill', color: '#4C8DFF' }, accessibilityLabel: 'Like' },
  { id: 'love', emoji: '❤️', symbol: { ios: 'heart.fill', color: '#FF6B6B' }, accessibilityLabel: 'Love' },
  { id: 'fire', emoji: '🔥', symbol: { ios: 'flame.fill', color: '#FF6B2C' }, accessibilityLabel: 'Fire' },
];

function App() {
  const [score, setScore] = useState<string | null>(null);

  return (
    <>
      <ReactionsPickerHost />

      <ReactionTrigger items={REACTIONS} selected={score ?? undefined} onSelect={setScore}>
        <YourRow />
      </ReactionTrigger>
    </>
  );
}
```

`ReactionTrigger` renders no appearance of its own — it wraps your children and nothing else. Showing the selected reaction afterwards is your job, from the `selected` value you already own.

<img src="assets/how-it-is-built.png" alt="How it is built" width="100%">

One picker exists at a time, process-wide, and only while a gesture is in flight. It is not mounted per row.

That is the load-bearing decision in the library. A trigger constructs no native view and no gesture recognizer; it registers the tag of the plain `View` it was already rendering. The host owns a single recognizer and resolves the live trigger view at gesture-begin, so no frames are cached in JavaScript and scrolling a long list costs exactly what it costs without the library.

<img src="assets/reaction-content.png" alt="Reaction content" width="100%">

Every item **must** carry an `emoji`. A `symbol` is optional and preferred where it resolves.

Symbols and emoji are not derivable from one another — nothing can produce 🔥 from `flame.fill` — so a fallback only exists if the item carries it. Requiring `emoji` is what makes `renderMode` a safe global kill switch rather than a setting that can blank the picker.

| Platform | Preferred | Falls back to |
| --- | --- | --- |
| iOS | `symbol.ios` (SF Symbol), if it resolves | `emoji` |
| Android | `symbol.android` (Material Symbol), if provided | `emoji` |

SF Symbols are licensed for Apple platforms and cannot ship in an Android artifact, which is why `symbol` is per-platform rather than a single name. Omit `symbol.android` and you get emoji there with no extra work.

Set `renderMode="emoji"` on the host to force emoji everywhere.

#### Colouring symbols

A symbol is a monochrome glyph, so it draws in `.label` unless you say otherwise. `symbol.color` says otherwise:

```tsx
{ id: 'love', emoji: '❤️', symbol: { ios: 'heart.fill', color: '#FF6B6B' }, accessibilityLabel: 'Love' }
```

Accepted forms are `#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA`, with the `#` optional. Anything else is ignored and the symbol stays `.label` — a typo leaves you with a legible glyph rather than a colour nobody chose.

There is one keyword besides a colour:

```tsx
{ id: 'fire', emoji: '🔥', symbol: { ios: 'flame.fill', color: 'multicolor' }, accessibilityLabel: 'Fire' }
```

`'multicolor'` asks SF Symbols for the palette Apple drew into the glyph itself, rather than a colour you picked. Whether a symbol *has* one is Apple's call and varies by OS version — on iOS 26, `star.fill` comes back gold while `flame.fill` has no palette at all. A symbol without one renders monochrome as usual rather than falling back to the emoji, since the glyph you named is what you asked for and its palette was only the preference. Check yours in the SF Symbols app under *Multicolor* before shipping it.

Two things `'multicolor'` does not do:

- **It is ignored on the ＋ item**, which composites its glyph and badge into one bitmap. A palette would be baked into that bitmap, including the monochrome fallback for a symbol that has none — freezing a colour that has to follow whatever surface the pill lands on. Hex colours work there; `'multicolor'` leaves it on the default glyph treatment.
- **It does not force colour onto a symbol that has no palette.** That glyph keeps the library's `.label` treatment, which stays legible on light and dark surfaces alike.

Two consequences worth knowing before you reach for either form:

- **A coloured or multicolor symbol no longer tints on selection.** Selection is drawn as a tint, and tinting over your colour would throw it away, so it holds its colours whether or not it is the current pick — exactly as an emoji does. If the pill is the only place you show what is selected, leave the colour off.
- **It does nothing on Android in 1.x**, which renders emoji only. The field is accepted there and ignored, like `symbol.android`.

Either form applies to the glyph, not to the emoji it falls back to — an emoji already carries its own.

<img src="assets/selection-model.png" alt="Selection model" width="100%">

One reaction per user per item — upsert, not additive. Picking a different reaction replaces the current one; picking the reaction that is already selected clears it and emits `null`.

### Another reaction

Give a trigger an `onSelectAnother` handler and the picker grows a trailing **＋** item. Releasing on it opens the **native emoji picker** — the system emoji keyboard on iOS, androidx's `EmojiPickerView` bottom sheet on Android — and the chosen emoji arrives in the handler as a string, not an id:

```tsx
<ReactionTrigger
  items={REACTIONS}
  selected={score ?? undefined}
  onSelect={setScore}
  onSelectAnother={(emoji) => addCustomReaction(emoji)}
  anotherSelected={lastCustomEmoji}
>
```

Pass the picked emoji back as `anotherSelected` and it becomes one extra selectable item in the picker, separated from your reactions by a hairline divider, just before the plus: `[your reactions] | [custom] [+]`. One custom slot exists at most — pass the newest pick to replace it. Selecting it reports through `onSelect` with the emoji string as the id, with the usual upsert-and-deselect semantics.

The plus renders only when there is somewhere for the pick to go — no handler, no plus. It can also be switched off explicitly:

- **Globally:** `<ReactionsPickerHost anotherReactionEnabled={false} />`
- **Per picker:** `<ReactionTrigger anotherReactionEnabled={false} … />` (overrides the global in either direction)

#### Customising the ＋ item

The default glyph is a dashed emoji with a plus badge, and its label is the English `"Add another reaction"`. Both are overridable — globally on the host, or per picker on the trigger:

```tsx
<ReactionsPickerHost
  anotherReactionAppearance={{
    symbol: { ios: 'plus.magnifyingglass' },
    emoji: '➕',
    badge: false,
    accessibilityLabel: t('reactions.addAnother'),
  }}
/>
```

| Field | Default | Notes |
| --- | --- | --- |
| `symbol` | dashed face (`face.dashed`, `circle.dashed` on iOS 15) | iOS only. `symbol.android` is accepted but ignored in 1.x — Android renders emoji only, exactly as it does for items. `symbol.color` takes a hex colour here and applies to the item including its plus badge: the two are drawn into one image and cannot take different colours. `'multicolor'` is ignored — see [Colouring symbols](#colouring-symbols). |
| `emoji` | — | Used when no symbol renders, and forced under `renderMode="emoji"`. The only way to change the Android glyph. |
| `badge` | `true` | The corner plus. Only drawn over a symbol: an emoji already reads as a picked reaction, so badging it reads wrong. |
| `accessibilityLabel` | `"Add another reaction"` | Supply a localized string. |

Every field is optional, and if nothing resolves the built-in glyph draws — the slot never blanks. A trigger's object **replaces** the host's rather than merging into it, so a per-picker override starts from the built-in defaults, not from the global object.

<p align="center">
  <img src="assets/demo-another-reaction.gif" alt="Dragging to the plus opens the system emoji keyboard; the picked emoji returns as a custom slot before the plus" width="300">
</p>

<p align="center"><sub>Drag to <b>＋</b> → system emoji keyboard → the pick lands on the row and joins the picker, after the divider.</sub></p>

<img src="assets/api.png" alt="API" width="100%">

| Export | What it is |
| --- | --- |
| `ReactionsPickerHost` | Required once at the root. Renders nothing. |
| `ReactionTrigger` | Per-item wrapper around your own children. |
| `isLiquidGlassSupported` | Runtime capability flag, backed by the native check. |

<img src="assets/support-matrix.png" alt="Support matrix" width="100%">

| Library | React Native | Nitro | Min Xcode | Min iOS | Min Android |
| --- | --- | --- | --- | --- | --- |
| 0.1.x – 0.3.x | 0.80 – 0.85 | 0.36.x | 26 | 15 (glass on 26+) | API 24 |

The `react-native-nitro-modules` peer range has a pinned floor **and** ceiling. Nitro is pre-1.0 and ships often; expect releases here when it moves.

<img src="assets/accessibility.png" alt="Accessibility" width="100%">

Reactions are exposed as buttons with their `accessibilityLabel`. **Reduce Transparency** replaces glass with an opaque surface, and **Reduce Motion** replaces every spring with a plain fade.

<img src="assets/known-platform-traps.png" alt="Known platform traps" width="100%">

- Never fade the picker with `opacity` from JavaScript. Setting `opacity: 0` on a glass view **or any ancestor** disables the effect outright.
- Glass rendering has regressed across iOS point releases before. Re-verify on each iOS minor.
- Some iOS simulator runtimes cannot render emoji at all — every emoji draws as a missing-glyph box through any API, including plain RN `<Text>`. Observed on iOS 26.3.1, correct on 26.5. Render an emoji through `<Text>` as a control before assuming the library is at fault.

<h2 align="center">☕ Buy me a coffee</h2>

<p align="center">If this library saved you a few hours of fighting UIKit, you can say thanks with a coffee.</p>

<table align="center">
<tr>
<td align="center"><a href="https://buycoffee.to/gasacz?coffeeSize=small">☕<br><b>€3</b><br><sub>small</sub></a></td>
<td align="center"><a href="https://buycoffee.to/gasacz?coffeeSize=medium">☕☕<br><b>€5</b><br><sub>medium</sub></a></td>
<td align="center"><a href="https://buycoffee.to/gasacz?coffeeSize=large">☕☕☕<br><b>€8</b><br><sub>large</sub></a></td>
</tr>
</table>

<img src="assets/license.png" alt="License" width="100%">

MIT
