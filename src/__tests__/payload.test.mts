import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { NativeTriggerPayload } from '../reactions-host.nitro.ts';
import {
  isSameTriggerPayload,
  triggerPayload,
  type TriggerContent,
} from '../payload.ts';

/**
 * Covers the pure half of a trigger's native lifecycle: what its state
 * flattens to, and what counts as a change to it.
 *
 * The hook itself is not covered — that would mean adding a React renderer for
 * one `useEffect`, and the part carrying the correctness burden is here.
 */

const items = [
  { id: 'up', emoji: '👍', accessibilityLabel: 'Thumbs up' },
  {
    id: 'love',
    emoji: '❤️',
    symbol: { ios: 'heart.fill', android: 'favorite', color: '#FF6B6B' },
    accessibilityLabel: 'Love',
  },
];

const content: TriggerContent = { items, selected: 'up' };

describe('triggerPayload', () => {
  it('flattens per-platform symbol names', () => {
    const payload = triggerPayload(content);
    assert.deepEqual(payload.items[0], {
      id: 'up',
      emoji: '👍',
      symbolIos: undefined,
      symbolAndroid: undefined,
      symbolColor: undefined,
      accessibilityLabel: 'Thumbs up',
    });
    assert.equal(payload.items[1]?.symbolIos, 'heart.fill');
    assert.equal(payload.items[1]?.symbolAndroid, 'favorite');
    assert.equal(payload.items[1]?.symbolColor, '#FF6B6B');
  });

  it('carries the selection and the another-reaction fields', () => {
    const payload = triggerPayload({
      ...content,
      anotherReaction: true,
      anotherSelected: '🎉',
      anotherReactionAppearance: { emoji: '➕', badge: false },
    });
    assert.equal(payload.selectedId, 'up');
    assert.equal(payload.anotherReaction, true);
    assert.equal(payload.anotherSelected, '🎉');
    assert.equal(payload.anotherReactionAppearance?.emoji, '➕');
    assert.equal(payload.anotherReactionAppearance?.badge, false);
  });

  it('leaves an absent appearance absent rather than empty', () => {
    assert.equal(triggerPayload(content).anotherReactionAppearance, undefined);
  });
});

describe('isSameTriggerPayload', () => {
  /**
   * The case the whole design turns on: a list re-render hands every trigger
   * fresh object literals with identical content, and none of them may reach
   * the bridge (spec §6.5).
   */
  it('treats freshly built identical payloads as unchanged', () => {
    assert.equal(
      isSameTriggerPayload(triggerPayload(content), triggerPayload(content)),
      true
    );
  });

  it('notices a changed selection', () => {
    assert.equal(
      isSameTriggerPayload(
        triggerPayload(content),
        triggerPayload({ ...content, selected: 'love' })
      ),
      false
    );
  });

  /** Clearing a selection is a change, and `undefined` is a real value here. */
  it('notices a cleared selection', () => {
    assert.equal(
      isSameTriggerPayload(
        triggerPayload(content),
        triggerPayload({ ...content, selected: undefined })
      ),
      false
    );
  });

  it('notices added, removed, and reordered items', () => {
    const base = triggerPayload(content);
    assert.equal(
      isSameTriggerPayload(base, triggerPayload({ ...content, items: [items[0]!] })),
      false
    );
    assert.equal(
      isSameTriggerPayload(
        base,
        triggerPayload({ ...content, items: [items[1]!, items[0]!] })
      ),
      false
    );
  });

  it('notices an item changing only its emoji', () => {
    assert.equal(
      isSameTriggerPayload(
        triggerPayload(content),
        triggerPayload({
          ...content,
          items: [{ ...items[0]!, emoji: '👎' }, items[1]!],
        })
      ),
      false
    );
  });

  /** Labels are user-visible on the picker, so they are content, not metadata. */
  it('notices an item changing only its accessibility label', () => {
    assert.equal(
      isSameTriggerPayload(
        triggerPayload(content),
        triggerPayload({
          ...content,
          items: [{ ...items[0]!, accessibilityLabel: 'Approve' }, items[1]!],
        })
      ),
      false
    );
  });

  it('notices a symbol name changing on one platform only', () => {
    assert.equal(
      isSameTriggerPayload(
        triggerPayload(content),
        triggerPayload({
          ...content,
          items: [
            items[0]!,
            { ...items[1]!, symbol: { ios: 'heart', android: 'favorite' } },
          ],
        })
      ),
      false
    );
  });

  it('notices the another-reaction toggle and custom pick', () => {
    const base = triggerPayload(content);
    assert.equal(
      isSameTriggerPayload(
        base,
        triggerPayload({ ...content, anotherReaction: false })
      ),
      false
    );
    assert.equal(
      isSameTriggerPayload(
        base,
        triggerPayload({ ...content, anotherSelected: '🎉' })
      ),
      false
    );
  });

  it('distinguishes an absent appearance from a present one', () => {
    const withAppearance = triggerPayload({
      ...content,
      anotherReactionAppearance: { emoji: '➕' },
    });
    assert.equal(isSameTriggerPayload(triggerPayload(content), withAppearance), false);
    assert.equal(isSameTriggerPayload(withAppearance, triggerPayload(content)), false);
  });

  it('compares appearances field by field', () => {
    const badged = triggerPayload({
      ...content,
      anotherReactionAppearance: { symbol: { ios: 'plus' }, badge: true },
    });
    const unbadged = triggerPayload({
      ...content,
      anotherReactionAppearance: { symbol: { ios: 'plus' }, badge: false },
    });
    assert.equal(isSameTriggerPayload(badged, unbadged), false);
    assert.equal(
      isSameTriggerPayload(
        badged,
        triggerPayload({
          ...content,
          anotherReactionAppearance: { symbol: { ios: 'plus' }, badge: true },
        })
      ),
      true
    );
  });

  /**
   * A recolour changes nothing else about an item, so it is exactly the kind
   * of difference a field-by-field comparison can drop by omission.
   */
  it('notices a symbol recolour', () => {
    const recoloured = triggerPayload({
      ...content,
      items: [
        items[0]!,
        { ...items[1]!, symbol: { ...items[1]!.symbol!, color: '#4C8DFF' } },
      ],
    });
    assert.equal(isSameTriggerPayload(triggerPayload(content), recoloured), false);
  });

  /** Short-circuiting must not make a later difference invisible. */
  it('still notices a difference in the last item', () => {
    const a: NativeTriggerPayload = triggerPayload(content);
    const b: NativeTriggerPayload = triggerPayload({
      ...content,
      items: [items[0]!, { ...items[1]!, id: 'adore' }],
    });
    assert.equal(isSameTriggerPayload(a, b), false);
  });
});
