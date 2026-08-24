package com.margelo.nitro.glassreactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Mirrors `Tests/PickerInteractionTests/SlotLayoutTests.swift` case for case.
 * When one side changes, the other should change with it.
 */

/**
 * itemSize 40, itemSpacing 8, contentInset 8, separatorExtra 8 — round
 * numbers chosen so centres land on whole values and are easy to verify by
 * hand: stride 48 between ungapped slots, 56 across the separator.
 */
private const val ITEM_SIZE = 40f
private const val ITEM_SPACING = 8f
private const val CONTENT_INSET = 8f
private const val SEPARATOR_EXTRA = 8f
private const val EPSILON = 0.001f

private fun centerX(index: Int, separatorAfter: Int? = null): Float =
    SlotLayout.centerX(
        index, ITEM_SIZE, ITEM_SPACING, CONTENT_INSET, separatorAfter, SEPARATOR_EXTRA
    )

private fun nearestIndex(atLocalX: Float, count: Int, separatorAfter: Int? = null): Int? =
    SlotLayout.nearestIndex(
        atLocalX, count, ITEM_SIZE, ITEM_SPACING, CONTENT_INSET, separatorAfter, SEPARATOR_EXTRA
    )

class SlotLayoutCenterXTest {

    @Test
    fun `first slot sits after the content inset`() {
        // 8 + 0*(48) + 20
        assertEquals(28f, centerX(0), EPSILON)
    }

    @Test
    fun `stride between slots is item size plus spacing`() {
        assertEquals(76f, centerX(1), EPSILON)   // 28 + 48
        assertEquals(124f, centerX(2), EPSILON)  // 76 + 48
    }

    @Test
    fun `slots before the separator are unaffected`() {
        assertEquals(124f, centerX(2, separatorAfter = 3), EPSILON)
    }

    /** `index >= separatorAfter`, so the boundary slot itself is already widened. */
    @Test
    fun `the separator boundary slot is widened`() {
        assertEquals(180f, centerX(3, separatorAfter = 3), EPSILON) // 172 + 8
    }

    /**
     * The extra width is a flat offset applied once, not compounded per slot
     * beyond the boundary — stride resumes at the normal 48 after it.
     */
    @Test
    fun `extra width does not compound past the separator`() {
        val third = centerX(3, separatorAfter = 3)
        val fourth = centerX(4, separatorAfter = 3)
        assertEquals(48f, fourth - third, EPSILON)
    }

    @Test
    fun `no separator means no widening`() {
        assertEquals(centerX(4, separatorAfter = null), centerX(4), EPSILON)
    }
}

class SlotLayoutNearestIndexTest {

    @Test
    fun `returns the slot whose point is exact`() {
        assertEquals(2, nearestIndex(atLocalX = 124f, count = 5))
    }

    @Test
    fun `returns the closer of two neighboring slots`() {
        // centerX(1)=76, centerX(2)=124 - 110 is 14 from slot 2, 34 from slot 1.
        assertEquals(2, nearestIndex(atLocalX = 110f, count = 5))
    }

    /** Ties go to the lower index — Kotlin's minByOrNull keeps the first minimum. */
    @Test
    fun `ties go to the lower index`() {
        // Exact midpoint of centerX(1)=76 and centerX(2)=124.
        assertEquals(1, nearestIndex(atLocalX = 100f, count = 5))
    }

    /**
     * Always returns the nearest slot, however far outside the row the point
     * is — the caller is responsible for deciding whether the point counts as
     * "in range" at all (the tolerance-inset frame check happens before this
     * is reached).
     */
    @Test
    fun `returns the nearest slot even far outside the row`() {
        assertEquals(0, nearestIndex(atLocalX = -1000f, count = 5))
        assertEquals(4, nearestIndex(atLocalX = 1000f, count = 5))
    }

    @Test
    fun `empty row never matches`() {
        assertNull(nearestIndex(atLocalX = 50f, count = 0))
    }

    /**
     * The separator's widened gap shifts where "nearest" flips — the boundary
     * is no longer exactly halfway between the two neighbouring slots.
     */
    @Test
    fun `the separators widened gap shifts the nearest boundary`() {
        // centerX(2, sep=3)=124, centerX(3, sep=3)=180 - the ungapped midpoint
        // would be 152; 153 is still closer to 180 than to 124 (27 vs 29).
        assertEquals(3, nearestIndex(atLocalX = 153f, count = 5, separatorAfter = 3))
    }
}
