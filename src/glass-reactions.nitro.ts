import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules';

/**
 * How reaction content is resolved at render time.
 *
 * - `auto`  — prefer a platform symbol where one is supplied and resolvable,
 *             fall back to `emoji` per item.
 * - `emoji` — force emoji everywhere and ignore symbols entirely.
 *
 * See spec §5. `emoji` is the guaranteed fallback, which is why it is
 * required on every item.
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
  accessibilityLabel: string;
}

export interface GlassReactionsProps extends HybridViewProps {
  items: NativeReactionItem[];
  renderMode: ReactionRenderMode;
  /** Currently selected reaction id, or undefined when nothing is selected. */
  selectedId?: string;
}

export interface GlassReactionsMethods extends HybridViewMethods {}

export type GlassReactions = HybridView<
  GlassReactionsProps,
  GlassReactionsMethods
>;
