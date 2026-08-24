import { useId, useRef, type ComponentRef } from 'react';
import { View, type ViewProps } from 'react-native';
import {
  useTriggerRegistration,
  type TriggerListeners,
} from './trigger-registration';
import type {
  AnotherReactionAppearance,
  ReactionId,
  ReactionItem,
} from './types';

export interface ReactionTriggerProps extends ViewProps {
  readonly items: readonly ReactionItem[];
  readonly selected?: ReactionId;
  /** `null` means the current selection was cleared. */
  readonly onSelect: (id: ReactionId | null) => void;
  /**
   * Fires when the user picks an emoji through the "another reaction" plus
   * item's native emoji picker. The plus only renders on triggers that supply
   * this handler.
   */
  readonly onSelectAnother?: (emoji: string) => void;
  /**
   * The custom emoji previously picked through "another reaction", if any.
   * Rendered as one extra selectable item between the separator and the plus
   * (max one — pass the newest pick to replace it). Selecting it reports
   * through `onSelect` with the emoji string as the id.
   */
  readonly anotherSelected?: string;
  /**
   * Per-picker override for the "another reaction" plus item. Unset inherits
   * the `ReactionsPickerHost` global; `false` hides the plus on this trigger.
   */
  readonly anotherReactionEnabled?: boolean;
  /**
   * Per-picker appearance for the "another reaction" item. Unset inherits the
   * `ReactionsPickerHost` object; supplying one replaces it outright rather
   * than merging into it.
   */
  readonly anotherReactionAppearance?: AnotherReactionAppearance;
  readonly onOpen?: () => void;
  readonly onClose?: () => void;
  readonly disabled?: boolean;
}

/**
 * A transparent wrapper around whatever the consumer renders. It owns no
 * appearance at all — no colours, sizes, or theme API — which is what keeps the
 * public surface small enough to hold still across 1.x (spec §5).
 *
 * It is also the cheapest option: the plain `View` below is the backing native
 * view the host converts coordinates from at gesture-begin, so it is a view the
 * consumer was rendering anyway. No Nitro view, no gesture recognizer, and no
 * native object is constructed per row (spec §6.5).
 */
export function ReactionTrigger({
  items,
  selected,
  onSelect,
  onSelectAnother,
  anotherSelected,
  anotherReactionEnabled,
  anotherReactionAppearance,
  onOpen,
  onClose,
  disabled = false,
  children,
  ...viewProps
}: ReactionTriggerProps) {
  const triggerId = useId();
  const viewRef = useRef<ComponentRef<typeof View>>(null);

  // Held in a ref so the native registration never has to be redone just
  // because a callback identity changed between renders.
  const listenersRef = useRef<TriggerListeners>({
    onSelect,
    onSelectAnother,
    onOpen,
    onClose,
  });
  listenersRef.current = { onSelect, onSelectAnother, onOpen, onClose };

  useTriggerRegistration(
    triggerId,
    viewRef,
    {
      items,
      selected,
      // Without a handler there is nothing for a picked emoji to reach, so the
      // plus is forced off rather than rendered inert. Otherwise the explicit
      // prop wins, and `undefined` defers to the host's global setting.
      anotherReaction: onSelectAnother == null ? false : anotherReactionEnabled,
      anotherSelected,
      anotherReactionAppearance,
    },
    listenersRef,
    disabled
  );

  return (
    <View ref={viewRef} collapsable={false} {...viewProps}>
      {children}
    </View>
  );
}
