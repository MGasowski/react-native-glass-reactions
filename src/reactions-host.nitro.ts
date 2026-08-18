import type { HybridObject } from 'react-native-nitro-modules';
import type {
  NativeReactionItem,
  ReactionRenderMode,
} from './glass-reactions.nitro';

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
  activate(renderMode: ReactionRenderMode, longPressDurationMs: number): void;

  /** Tears down the recognizer and releases the pooled picker. */
  deactivate(): void;

  registerTrigger(
    triggerId: string,
    viewTag: number,
    items: NativeReactionItem[],
    selectedId?: string
  ): void;

  updateTrigger(
    triggerId: string,
    items: NativeReactionItem[],
    selectedId?: string
  ): void;

  unregisterTrigger(triggerId: string): void;

  /**
   * `reactionId` is undefined when the interaction deselects or is cancelled.
   * Fires at touch-up; the collapse animation runs after it (spec §4.3).
   */
  setOnSelect(callback: (triggerId: string, reactionId?: string) => void): void;
  setOnOpen(callback: (triggerId: string) => void): void;
  setOnClose(callback: (triggerId: string) => void): void;
}
