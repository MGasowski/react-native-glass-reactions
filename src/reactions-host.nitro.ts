import type { HybridObject } from 'react-native-nitro-modules';

/**
 * How reaction content is resolved at render time.
 *
 * - `auto`  — prefer a platform symbol where one is supplied and resolvable,
 *             fall back to `emoji` per item.
 * - `emoji` — force emoji everywhere and ignore symbols entirely.
 *
 * See spec §5. `emoji` is the guaranteed fallback, which is why it is required
 * on every item.
 */
export type ReactionRenderMode = 'auto' | 'emoji';

/**
 * Flattened form of the public `ReactionItem`. Nitro structs do not nest
 * optionals well, so the per-platform symbol names are flattened here rather
 * than carried as a nested `symbol` object.
 */
export interface NativeReactionItem {
  id: string;
  /** Required — the universal fallback (spec §5). */
  emoji: string;
  /** SF Symbol name, iOS only. */
  symbolIos?: string;
  /** Material Symbol name, Android only. */
  symbolAndroid?: string;
  /** `#RGB` / `#RRGGBB` / `#RRGGBBAA` colour for the symbol. */
  symbolColor?: string;
  accessibilityLabel: string;
}

/**
 * Flattened appearance of the trailing "another reaction" item. Every field is
 * optional: this whole struct is absent unless the consumer overrides the
 * built-in chrome, and each unset field keeps its native default.
 */
export interface NativeAnotherReaction {
  /** SF Symbol name, iOS only. */
  symbolIos?: string;
  /** Material Symbol name, Android only — unused in 1.x (emoji-only there). */
  symbolAndroid?: string;
  /** `#RGB` / `#RRGGBB` / `#RRGGBBAA` colour for the glyph and its badge. */
  symbolColor?: string;
  /** Fallback when no symbol renders, and the forced form under `emoji` mode. */
  emoji?: string;
  /** The corner plus badge. Default true. Only drawn over a symbol. */
  badge?: boolean;
  /** Default "Add another reaction". */
  accessibilityLabel?: string;
}

/**
 * Everything a trigger tells the host about itself, other than its identity and
 * its view tag.
 *
 * A struct rather than five more positional parameters, for the same reason
 * `NativeAnotherReaction` is one: the next optional field becomes a member here
 * instead of an eighth argument on a method that exists on two platforms.
 */
export interface NativeTriggerPayload {
  items: NativeReactionItem[];
  selectedId?: string;
  /** `undefined` inherits the host-wide setting. */
  anotherReaction?: boolean;
  /** The custom emoji previously picked through "another reaction". */
  anotherSelected?: string;
  /** Replaces the host-wide appearance outright rather than merging into it. */
  anotherReactionAppearance?: NativeAnotherReaction;
}

/**
 * Process-wide host singleton. This is what makes the single-picker guarantee
 * structural rather than a matter of consumer discipline (spec §4.3): the
 * instance lives here, not in the React tree, so no arrangement of components
 * can produce two.
 *
 * It also owns the one gesture recognizer. Triggers register the tag of the
 * plain RN view they already render; at gesture-begin the host hit-tests the
 * window and walks up to find a registered tag. Nothing native is constructed
 * per row and no frames are cached in JS, so scrolling costs nothing (§6.5).
 */
export interface ReactionsHost extends HybridObject<{
  ios: 'swift';
  android: 'kotlin';
}> {
  /** True when Liquid Glass will actually render — SDK, OS, and runtime API. */
  readonly isLiquidGlassSupported: boolean;

  /** Installs the recognizer and warms the picker off the critical path. */
  activate(
    renderMode: ReactionRenderMode,
    longPressDurationMs: number,
    anotherReactionEnabled: boolean,
    anotherReactionAppearance?: NativeAnotherReaction
  ): void;

  /** Tears down the recognizer and releases the pooled picker. */
  deactivate(): void;

  /**
   * Upserts a trigger: registers it if it is new, replaces its payload if it is
   * not. One method rather than a register/update pair, because the two differed
   * only in create-versus-mutate, and every caller had to know which of the
   * two it was in.
   */
  syncTrigger(
    triggerId: string,
    viewTag: number,
    payload: NativeTriggerPayload
  ): void;

  unregisterTrigger(triggerId: string): void;

  /**
   * `reactionId` is undefined when the interaction deselects or is cancelled.
   * Fires at touch-up; the collapse animation runs after it (spec §4.3).
   */
  setOnSelect(callback: (triggerId: string, reactionId?: string) => void): void;

  /**
   * Fires when the user picks an emoji through the "another reaction" plus
   * item's native emoji picker. The emoji is not one of the registered items,
   * so it is reported by value rather than by id.
   */
  setOnSelectAnother(
    callback: (triggerId: string, emoji: string) => void
  ): void;
  setOnOpen(callback: (triggerId: string) => void): void;
  setOnClose(callback: (triggerId: string) => void): void;
}
