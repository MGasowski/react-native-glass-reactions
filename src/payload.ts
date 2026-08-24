import type {
  NativeAnotherReaction,
  NativeTriggerPayload,
} from './reactions-host.nitro';
import type {
  AnotherReactionAppearance,
  ReactionId,
  ReactionItem,
} from './types';

/**
 * What a trigger and the host say to native, and what counts as a change to it.
 *
 * Deliberately free of runtime imports — no `react`, no `react-native`, and
 * above all no `./host`, which resolves the Nitro singleton at module scope and
 * would make importing this file impossible outside an app. That is what lets
 * the diffing rules be tested with `node --test` and nothing else.
 */

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

/** The props a trigger pushes native. */
export interface TriggerContent {
  readonly items: readonly ReactionItem[];
  readonly selected?: ReactionId;
  readonly anotherReaction?: boolean;
  readonly anotherSelected?: string;
  readonly anotherReactionAppearance?: AnotherReactionAppearance;
}

/**
 * Flattens the public props into the struct the host takes.
 *
 * Pure, and separated from the effect that sends it, because "what counts as
 * this trigger's state" is the part worth testing — the sending is one call.
 */
export function triggerPayload(content: TriggerContent): NativeTriggerPayload {
  return {
    items: content.items.map((item) => ({
      id: item.id,
      emoji: item.emoji,
      symbolIos: item.symbol?.ios,
      symbolAndroid: item.symbol?.android,
      accessibilityLabel: item.accessibilityLabel,
    })),
    selectedId: content.selected,
    anotherReaction: content.anotherReaction,
    anotherSelected: content.anotherSelected,
    anotherReactionAppearance: toNativeAnotherReaction(
      content.anotherReactionAppearance
    ),
  };
}

/**
 * Whether two payloads say the same thing.
 *
 * A field-by-field comparison rather than `JSON.stringify` on both sides: this
 * runs after every render of every trigger in a list, which is the one path the
 * library keeps free of avoidable work (spec §6.5). It also short-circuits on
 * the first difference, where stringifying always walks the whole structure
 * twice and allocates two strings to throw away.
 */
export function isSameTriggerPayload(
  a: NativeTriggerPayload,
  b: NativeTriggerPayload
): boolean {
  if (
    a.selectedId !== b.selectedId ||
    a.anotherReaction !== b.anotherReaction ||
    a.anotherSelected !== b.anotherSelected
  ) {
    return false;
  }

  const appearanceA = a.anotherReactionAppearance;
  const appearanceB = b.anotherReactionAppearance;
  if (appearanceA == null || appearanceB == null) {
    if (appearanceA !== appearanceB) return false;
  } else if (
    appearanceA.symbolIos !== appearanceB.symbolIos ||
    appearanceA.symbolAndroid !== appearanceB.symbolAndroid ||
    appearanceA.emoji !== appearanceB.emoji ||
    appearanceA.badge !== appearanceB.badge ||
    appearanceA.accessibilityLabel !== appearanceB.accessibilityLabel
  ) {
    return false;
  }

  if (a.items.length !== b.items.length) return false;
  for (let index = 0; index < a.items.length; index++) {
    const itemA = a.items[index]!;
    const itemB = b.items[index]!;
    if (
      itemA.id !== itemB.id ||
      itemA.emoji !== itemB.emoji ||
      itemA.symbolIos !== itemB.symbolIos ||
      itemA.symbolAndroid !== itemB.symbolAndroid ||
      itemA.accessibilityLabel !== itemB.accessibilityLabel
    ) {
      return false;
    }
  }

  return true;
}
