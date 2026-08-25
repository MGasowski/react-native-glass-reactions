/**
 * Public type surface. This is the 1.x contract — see spec §5.
 */

export type ReactionId = string;

/**
 * Per-platform symbol names. SF Symbols are licensed for Apple platforms and
 * their font cannot ship in an Android artifact, so `android` names a Material
 * Symbol — a different set with different names. Omit `android` to render
 * emoji there.
 */
/**
 * What `ReactionSymbol.color` accepts: a hex string, or the keyword
 * `'multicolor'`.
 *
 * The union is written this way so `'multicolor'` autocompletes without the
 * type collapsing to it — `string & {}` keeps every hex string assignable.
 */
export type SymbolColorValue = 'multicolor' | (string & {});

export interface ReactionSymbol {
  readonly ios: string;
  readonly android?: string;
  /**
   * Colour for the symbol, as `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA` — or
   * `'multicolor'` for the palette Apple drew into the glyph itself, where the
   * symbol has one. Which symbols do is Apple's call and varies by OS version:
   * on iOS 26 `star.fill` comes back gold and `flame.fill` has no palette at
   * all. A symbol without one renders monochrome as usual rather than falling
   * back to the emoji — the named glyph is what was asked for, and its palette
   * was only the preference.
   *
   * `'multicolor'` is ignored on `AnotherReactionAppearance`, whose glyph is
   * composited with its badge into one bitmap that a palette cannot be baked
   * into safely. Hex colours work there.
   *
   * Symbols are monochrome glyphs with no colour of their own, so this is the
   * only way to give them one — an emoji fallback is unaffected either way,
   * since it carries its own colour. Anything unparseable is ignored and the
   * symbol keeps the library's own tint treatment.
   *
   * Either way, a coloured symbol keeps its colour whether or not it is the
   * selected reaction, exactly as an emoji does: selection is drawn as a tint,
   * and tinting over a supplied colour would throw that colour away. Leave
   * this unset for the monochrome symbol that tints on selection.
   *
   * iOS only in 1.x; Android renders emoji, which have no tint to change.
   */
  readonly color?: SymbolColorValue;
}

export interface ReactionItem {
  readonly id: ReactionId;
  /**
   * Required. This is the guaranteed fallback: symbols and emoji are not
   * derivable from one another, so a fallback only exists if the item carries
   * it. Requiring it is what makes `renderMode` a safe kill switch.
   */
  readonly emoji: string;
  /** Preferred over `emoji` when renderable and `renderMode` is `auto`. */
  readonly symbol?: ReactionSymbol;
  readonly accessibilityLabel: string;
}

/**
 * - `auto`  — prefer symbols where supplied and resolvable, else emoji.
 * - `emoji` — force emoji everywhere; the escape hatch if symbol rendering
 *             proves problematic on either platform.
 */
export type ReactionRenderMode = 'auto' | 'emoji';

/**
 * Appearance of the trailing "another reaction" item — the one that opens the
 * native emoji picker. It is chrome rather than content, so unlike
 * `ReactionItem` every field is optional: omitting the object keeps the built-in
 * dashed-emoji-with-a-plus glyph, and omitting a field keeps that field's
 * default.
 *
 * Resolution mirrors `ReactionItem` (spec §5): `symbol` is preferred over
 * `emoji` when supplied and resolvable, but only under `renderMode: 'auto'` —
 * `renderMode: 'emoji'` skips a supplied symbol exactly as it does for items,
 * so the kill switch has no exception for chrome. When nothing renders, the
 * built-in glyph does — the item never blanks.
 */
export interface AnotherReactionAppearance {
  /**
   * Per-platform symbol name, and optionally its colour. `android` is accepted
   * but ignored in 1.x, which renders emoji only — supply `emoji` to customise
   * Android. Ignored entirely under `renderMode: 'emoji'`, like
   * `ReactionItem.symbol`.
   *
   * `color` applies to the whole item, plus badge included — the badge is
   * drawn into the same image as the glyph, so the two cannot take different
   * colours or different treatments.
   */
  readonly symbol?: ReactionSymbol;
  /** Used when no symbol renders, and under `renderMode: 'emoji'`. */
  readonly emoji?: string;
  /**
   * The plus badge in the corner. Default `true`. Only drawn over a symbol: an
   * emoji is already a picked reaction visually, so badging it reads wrong.
   */
  readonly badge?: boolean;
  /** Default `"Add another reaction"`. Supply a localized string. */
  readonly accessibilityLabel?: string;
}
