import { useEffect, useRef } from 'react';
import { host } from './host';
import type { ReactionId, ReactionRenderMode } from './types';

/**
 * Callbacks are held in a module-level registry keyed by trigger id rather than
 * being sent across the bridge per trigger. Registration must never cause a
 * render — a `useState` here would turn every list-cell recycle into a render
 * of the whole tree (spec §6.5).
 */
type SelectListener = (reactionId: ReactionId | null) => void;

const listeners = new Map<
  string,
  {
    onSelect: SelectListener;
    onSelectAnother?: (emoji: string) => void;
    onOpen?: () => void;
    onClose?: () => void;
  }
>();

export function addTriggerListener(
  triggerId: string,
  entry: {
    onSelect: SelectListener;
    onSelectAnother?: (emoji: string) => void;
    onOpen?: () => void;
    onClose?: () => void;
  }
): void {
  listeners.set(triggerId, entry);
}

export function removeTriggerListener(triggerId: string): void {
  listeners.delete(triggerId);
}

let wired = false;

function wireCallbacksOnce(): void {
  if (wired) return;
  wired = true;

  host.setOnSelect((triggerId, reactionId) => {
    listeners.get(triggerId)?.onSelect(reactionId ?? null);
  });
  host.setOnSelectAnother((triggerId, emoji) => {
    listeners.get(triggerId)?.onSelectAnother?.(emoji);
  });
  host.setOnOpen((triggerId) => {
    listeners.get(triggerId)?.onOpen?.();
  });
  host.setOnClose((triggerId) => {
    listeners.get(triggerId)?.onClose?.();
  });
}

export interface ReactionsPickerHostProps {
  /** Default `auto`. Set to `emoji` to disable symbol rendering everywhere. */
  readonly renderMode?: ReactionRenderMode;
  /** Milliseconds before the picker opens. Default 200. */
  readonly longPressDuration?: number;
  /**
   * Global switch for the "another reaction" plus item that opens the native
   * emoji picker. Default `true`. A trigger only shows the plus when this is
   * on, it supplies an `onSelectAnother` handler, and it does not opt out via
   * its own `anotherReactionEnabled` prop.
   */
  readonly anotherReactionEnabled?: boolean;
}

/**
 * Required at the root in 1.0. It renders nothing: its job is to install the
 * one gesture recognizer and warm the picker at a deterministic moment rather
 * than at first trigger mount, which could land mid-scroll (spec §6.5).
 *
 * Required rather than optional because a requirement can be relaxed in a minor
 * version, while making one mandatory later cannot be done without breaking
 * every consumer.
 */
export function ReactionsPickerHost({
  renderMode = 'auto',
  longPressDuration = 200,
  anotherReactionEnabled = true,
}: ReactionsPickerHostProps) {
  const activeRef = useRef(false);

  useEffect(() => {
    wireCallbacksOnce();
    host.activate(renderMode, longPressDuration, anotherReactionEnabled);
    activeRef.current = true;

    return () => {
      activeRef.current = false;
      host.deactivate();
    };
  }, [renderMode, longPressDuration, anotherReactionEnabled]);

  return null;
}
