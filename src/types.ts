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
export interface ReactionSymbol {
  readonly ios: string;
  readonly android?: string;
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
 * Resolution mirrors `ReactionItem` (spec §5): a symbol is preferred where one
 * is supplied and resolvable, `emoji` is the fallback, and `renderMode: 'emoji'`
 * forces `emoji` when one is supplied. When nothing renders, the built-in glyph
 * does — the item never blanks.
 */
export interface AnotherReactionAppearance {
  /**
   * Per-platform symbol name. `android` is accepted but ignored in 1.x, which
   * renders emoji only — supply `emoji` to customise Android.
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
