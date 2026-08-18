import { useMemo } from 'react';
import type { ViewProps } from 'react-native';
import { NativeGlassReactionsView } from './glass-reactions-view';
import type { NativeReactionItem } from './glass-reactions.nitro';
import type { ReactionId, ReactionItem, ReactionRenderMode } from './types';

export interface ReactionsPickerProps extends ViewProps {
  readonly items: readonly ReactionItem[];
  readonly selected?: ReactionId;
  readonly renderMode?: ReactionRenderMode;
}

/**
 * Static reactions surface (M1). Renders the glass pill on iOS 26 and the
 * defined fallback elsewhere; it does not yet handle gestures — that arrives
 * with the host at M2.
 */
export function ReactionsPicker({
  items,
  selected,
  renderMode = 'auto',
  ...viewProps
}: ReactionsPickerProps) {
  // The native struct is flat: Nitro does not carry nested optionals well, so
  // `symbol` is unpacked into per-platform fields at the boundary.
  const nativeItems = useMemo<NativeReactionItem[]>(
    () =>
      items.map((item) => ({
        id: item.id,
        emoji: item.emoji,
        symbolIos: item.symbol?.ios,
        symbolAndroid: item.symbol?.android,
        accessibilityLabel: item.accessibilityLabel,
      })),
    [items]
  );

  return (
    <NativeGlassReactionsView
      items={nativeItems}
      renderMode={renderMode}
      selectedId={selected}
      {...viewProps}
    />
  );
}
