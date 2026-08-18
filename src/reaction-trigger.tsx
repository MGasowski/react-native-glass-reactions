import { useEffect, useId, useRef, type ComponentRef } from 'react';
import { findNodeHandle, View, type ViewProps } from 'react-native';
import { host } from './host';
import {
  addTriggerListener,
  removeTriggerListener,
} from './reactions-picker-host';
import type { ReactionId, ReactionItem } from './types';

export interface ReactionTriggerProps extends ViewProps {
  readonly items: readonly ReactionItem[];
  readonly selected?: ReactionId;
  /** `null` means the current selection was cleared. */
  readonly onSelect: (id: ReactionId | null) => void;
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
  onOpen,
  onClose,
  disabled = false,
  children,
  ...viewProps
}: ReactionTriggerProps) {
  const triggerId = useId();
  const viewRef = useRef<ComponentRef<typeof View>>(null);
  const registeredRef = useRef(false);

  // Held in a ref so the native registration never has to be redone just
  // because a callback identity changed between renders.
  const handlersRef = useRef({ onSelect, onOpen, onClose });
  handlersRef.current = { onSelect, onOpen, onClose };

  const nativeItems = items.map((item) => ({
    id: item.id,
    emoji: item.emoji,
    symbolIos: item.symbol?.ios,
    symbolAndroid: item.symbol?.android,
    accessibilityLabel: item.accessibilityLabel,
  }));

  useEffect(() => {
    if (disabled) return;

    const tag = findNodeHandle(viewRef.current);
    if (tag == null) return;

    addTriggerListener(triggerId, {
      onSelect: (id) => handlersRef.current.onSelect(id),
      onOpen: () => handlersRef.current.onOpen?.(),
      onClose: () => handlersRef.current.onClose?.(),
    });
    host.registerTrigger(triggerId, tag, nativeItems, selected);
    registeredRef.current = true;

    return () => {
      registeredRef.current = false;
      removeTriggerListener(triggerId);
      host.unregisterTrigger(triggerId);
    };
    // Registration depends on identity and enablement only; item and selection
    // changes are pushed through updateTrigger below rather than by
    // re-registering.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [triggerId, disabled]);

  useEffect(() => {
    if (!registeredRef.current) return;
    host.updateTrigger(triggerId, nativeItems, selected);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [triggerId, selected, JSON.stringify(nativeItems)]);

  return (
    <View ref={viewRef} collapsable={false} {...viewProps}>
      {children}
    </View>
  );
}
