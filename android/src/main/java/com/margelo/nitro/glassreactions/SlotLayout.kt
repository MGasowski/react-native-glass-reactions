package com.margelo.nitro.glassreactions

import kotlin.math.abs

/**
 * Where each slot sits along the row, and which one a point is nearest to.
 *
 * Both were previously methods on [ReactionsPillView] — pure arithmetic over
 * `Metrics` and `separatorAfter`, but reachable only through the concrete
 * view, which is also [SlotGeometry]'s only implementation.
 * `PickerInteraction.focus()` reaches that seam to hit-test; the view's own
 * `onLayout`/`dispatchDraw` call the same centring math to position image
 * views and the separator line. This module is the one thing both call into,
 * so the two can never independently drift.
 *
 * Mirrors `SlotLayout` in `ios/SlotLayout.swift`. When one side changes, the
 * other should change with it.
 */
object SlotLayout {

    /**
     * Centre of slot [index] in the row's own coordinates.
     *
     * Single source of truth for layout, hit-testing, and the selection
     * flight vector — slots are not uniform once the separator inserts its
     * extra width. `separatorExtra` is passed in pre-computed rather than
     * derived here from its components (gap, line width, item spacing): that
     * arithmetic is `Metrics`'s to own, same as `verticalGap`/`edgeMargin` are
     * `PickerLayout`'s callers' to decide rather than this module's to know.
     */
    fun centerX(
        index: Int,
        itemSize: Float,
        itemSpacing: Float,
        contentInset: Float,
        separatorAfter: Int?,
        separatorExtra: Float
    ): Float {
        var x = contentInset + index * (itemSize + itemSpacing) + itemSize / 2f
        if (separatorAfter != null && index >= separatorAfter) x += separatorExtra
        return x
    }

    /**
     * The slot nearest the given local x, clamped to the row. The caller has
     * already checked the point is inside the row's (tolerance-inset) frame.
     */
    fun nearestIndex(
        atLocalX: Float,
        count: Int,
        itemSize: Float,
        itemSpacing: Float,
        contentInset: Float,
        separatorAfter: Int?,
        separatorExtra: Float
    ): Int? {
        if (count <= 0) return null
        return (0 until count).minByOrNull {
            abs(
                atLocalX - centerX(
                    it, itemSize, itemSpacing, contentInset, separatorAfter, separatorExtra
                )
            )
        }
    }
}
