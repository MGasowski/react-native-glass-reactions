import type { NativeAnotherReaction } from './reactions-host.nitro';
import type { AnotherReactionAppearance } from './types';

/**
 * Flattens the public appearance object into the struct the host takes. Nitro
 * structs do not nest optionals well, so `symbol` is split into its two
 * per-platform names here rather than carried across as a nested object — the
 * same shape `ReactionItem` is flattened into.
 */
export function toNativeAnotherReaction(
  appearance: AnotherReactionAppearance | undefined
): NativeAnotherReaction | undefined {
  if (appearance == null) return undefined;
  return {
    symbolIos: appearance.symbol?.ios,
    symbolAndroid: appearance.symbol?.android,
    emoji: appearance.emoji,
    badge: appearance.badge,
    accessibilityLabel: appearance.accessibilityLabel,
  };
}

/**
 * Stable key for an appearance, so a fresh object literal on every render does
 * not re-run the effects that push it native.
 */
export function anotherReactionKey(
  appearance: AnotherReactionAppearance | undefined
): string {
  return appearance == null
    ? ''
    : JSON.stringify(toNativeAnotherReaction(appearance));
}
