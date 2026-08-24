import { useEffect, useRef, type RefObject } from 'react';
import { findNodeHandle } from 'react-native';
import { host } from './host';
import {
  isSameTriggerPayload,
  triggerPayload,
  type TriggerContent,
} from './payload';
import type { NativeTriggerPayload } from './reactions-host.nitro';
import type { ReactionId } from './types';

/**
 * Callbacks are held in a module-level registry keyed by trigger id rather than
 * being sent across the bridge per trigger. Registration must never cause a
 * render — a `useState` here would turn every list-cell recycle into a render
 * of the whole tree (spec §6.5).
 */
export interface TriggerListeners {
  readonly onSelect: (reactionId: ReactionId | null) => void;
  readonly onSelectAnother?: (emoji: string) => void;
  readonly onOpen?: () => void;
  readonly onClose?: () => void;
}

const listeners = new Map<string, TriggerListeners>();

let wired = false;

/**
 * Routes the host's four callbacks into the registry. Called once, lazily: the
 * host is a process-wide singleton, so there is exactly one set of callbacks to
 * install no matter how many triggers exist.
 */
export function wireCallbacksOnce(): void {
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

/**
 * Owns one trigger's relationship with the native host: its listeners, its
 * payload, and its teardown.
 *
 * Split into two effects along the only line that matters — the first owns
 * whether the trigger *exists* natively, the second owns *what it says*. The
 * second deliberately has no dependency array: it runs after every render and
 * decides for itself whether anything changed, which is both cheaper than
 * stringifying the payload into a dependency key and honest, where a hand-
 * maintained key list is a claim the compiler cannot check.
 *
 * React runs effects in declaration order, so the listener is always installed
 * before the first payload is sent, and `lastSent` is what tells the second
 * effect that it is the first send.
 */
export function useTriggerRegistration(
  triggerId: string,
  viewRef: RefObject<unknown>,
  content: TriggerContent,
  listenersRef: RefObject<TriggerListeners>,
  disabled: boolean
): void {
  const lastSent = useRef<NativeTriggerPayload | null>(null);

  useEffect(() => {
    if (disabled) return;

    listeners.set(triggerId, {
      onSelect: (id) => listenersRef.current.onSelect(id),
      onSelectAnother: (emoji) => listenersRef.current.onSelectAnother?.(emoji),
      onOpen: () => listenersRef.current.onOpen?.(),
      onClose: () => listenersRef.current.onClose?.(),
    });

    return () => {
      listeners.delete(triggerId);
      host.unregisterTrigger(triggerId);
      // Forces a full send if this trigger comes back — the host no longer
      // knows anything about it.
      lastSent.current = null;
    };
  }, [triggerId, disabled, listenersRef]);

  useEffect(() => {
    if (disabled) return;

    const payload = triggerPayload(content);
    const previous = lastSent.current;
    if (previous != null && isSameTriggerPayload(previous, payload)) return;

    const tag = findNodeHandle(viewRef.current as never);
    if (tag == null) return;

    host.syncTrigger(triggerId, tag, payload);
    lastSent.current = payload;
  });
}
