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
  { onSelect: SelectListener; onOpen?: () => void; onClose?: () => void }
>();

export function addTriggerListener(
  triggerId: string,
  entry: {
    onSelect: SelectListener;
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
}: ReactionsPickerHostProps) {
  const activeRef = useRef(false);

  useEffect(() => {
    wireCallbacksOnce();
    host.activate(renderMode, longPressDuration);
    activeRef.current = true;

    return () => {
      activeRef.current = false;
      host.deactivate();
    };
  }, [renderMode, longPressDuration]);

  return null;
}
