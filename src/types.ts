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
