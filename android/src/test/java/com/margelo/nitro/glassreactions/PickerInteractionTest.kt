package com.margelo.nitro.glassreactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Mirrors `Tests/PickerInteractionTests/PickerInteractionTests.swift` case for
 * case. When one side changes, the other should change with it — that diff is
 * the parity check.
 */

/**
 * Uniform 48px slots. The pill's real geometry is not uniform once the
 * separator inserts its extra width, but that is the pill's rule to get right;
 * what is under test here is everything *around* the lookup.
 */
private class UniformSlots(val count: Int, val width: Float = 48f) : SlotGeometry {
    override fun slotIndex(localX: Float): Int? {
        if (count == 0) return null
        return ((localX / width).toInt()).coerceIn(0, count - 1)
    }
}

private fun reaction(id: String) =
    Reaction(id = id, emoji = "👍", accessibilityLabel = id)

/** A picker at (100, 200) sized 144×40 — three 48px slots. */
private val frame = PickerFrame(left = 100f, top = 200f, right = 244f, bottom = 240f)

private fun makeInteraction(
    slots: List<Slot>,
    selectedId: String? = null,
    tolerance: Float = 12f
) = PickerInteraction(
    triggerId = "trigger",
    slots = slots,
    selectedId = selectedId,
    pickerFrame = frame,
    tolerance = tolerance,
    geometry = UniformSlots(slots.size)
)

private val threeReactions: List<Slot> = listOf(
    Slot.Reaction(reaction("a")),
    Slot.Reaction(reaction("b")),
    Slot.Reaction(reaction("c"))
)

class FocusTest {

    /**
     * The picker opens under a finger that is on the row *below* it. Focusing
     * anything at that moment is what made a reaction look pre-selected the
     * instant the picker appeared.
     */
    @Test
    fun `starts with nothing focused`() {
        assertNull(makeInteraction(threeReactions).focusedIndex)
    }

    @Test
    fun `focuses the slot under the point`() {
        val interaction = makeInteraction(threeReactions)
        assertEquals(FocusChange.Moved(0), interaction.focus(124f, 220f))
        assertEquals(FocusChange.Moved(1), interaction.focus(172f, 220f))
        assertEquals(FocusChange.Moved(2), interaction.focus(220f, 220f))
    }

    /**
     * Moving within one slot must not report a change, or the per-item haptic
     * fires repeatedly while the finger sits still.
     */
    @Test
    fun `moving within a slot reports no change`() {
        val interaction = makeInteraction(threeReactions)
        assertEquals(FocusChange.Moved(0), interaction.focus(110f, 220f))
        assertEquals(FocusChange.Unchanged, interaction.focus(112f, 220f))
        assertEquals(FocusChange.Unchanged, interaction.focus(140f, 220f))
    }

    @Test
    fun `leaving the picker clears focus`() {
        val interaction = makeInteraction(threeReactions)
        interaction.focus(124f, 220f)
        assertEquals(FocusChange.Cleared, interaction.focus(124f, 400f))
        assertNull(interaction.focusedIndex)
    }

    @Test
    fun `staying outside reports no change`() {
        val interaction = makeInteraction(threeReactions)
        assertEquals(FocusChange.Unchanged, interaction.focus(124f, 400f))
    }

    /** Vertical slack keeps the selection from flickering at the edge. */
    @Test
    fun `tolerance extends focus vertically`() {
        val interaction = makeInteraction(threeReactions)
        // 11px below the bottom edge: still pointing at a reaction.
        assertEquals(FocusChange.Moved(0), interaction.focus(124f, 251f))
        // 13px below: past the slack.
        assertEquals(FocusChange.Cleared, interaction.focus(124f, 253f))
    }

    @Test
    fun `tolerance extends focus above the picker too`() {
        val interaction = makeInteraction(threeReactions)
        assertEquals(FocusChange.Moved(0), interaction.focus(124f, 190f))
        assertEquals(FocusChange.Cleared, interaction.focus(124f, 187f))
    }

    /**
     * There is deliberately no horizontal slack: a point beside the picker must
     * clear rather than clamp to the nearest end slot.
     */
    @Test
    fun `no horizontal tolerance`() {
        val interaction = makeInteraction(threeReactions)
        interaction.focus(124f, 220f)
        assertEquals(FocusChange.Cleared, interaction.focus(99f, 220f))

        interaction.focus(124f, 220f)
        assertEquals(FocusChange.Cleared, interaction.focus(245f, 220f))
    }

    /**
     * Trailing edges are outside, matching `CGRect.contains` on iOS so the two
     * implementations agree to the pixel.
     */
    @Test
    fun `hit area is half open`() {
        val interaction = makeInteraction(threeReactions)
        assertEquals(FocusChange.Moved(0), interaction.focus(100f, 188f))
        assertEquals(FocusChange.Cleared, interaction.focus(244f, 220f))
    }

    @Test
    fun `empty slots never focus`() {
        val interaction = makeInteraction(emptyList())
        assertEquals(FocusChange.Unchanged, interaction.focus(124f, 220f))
    }
}

class ReleaseTest {

    @Test
    fun `releasing with no focus cancels`() {
        assertEquals(Outcome.Cancel, makeInteraction(threeReactions).release())
    }

    @Test
    fun `releasing after leaving the picker cancels`() {
        val interaction = makeInteraction(threeReactions)
        interaction.focus(124f, 220f)
        interaction.focus(124f, 400f)
        assertEquals(Outcome.Cancel, interaction.release())
    }

    @Test
    fun `releasing on a reaction selects it`() {
        val interaction = makeInteraction(threeReactions, selectedId = null)
        interaction.focus(172f, 220f)
        assertEquals(Outcome.Select("b", 1), interaction.release())
    }

    /** Upsert with deselect (spec §5). */
    @Test
    fun `releasing on the current selection clears it`() {
        val interaction = makeInteraction(threeReactions, selectedId = "b")
        interaction.focus(172f, 220f)
        assertEquals(Outcome.Deselect(1), interaction.release())
    }

    @Test
    fun `releasing on a different reaction while one is selected replaces it`() {
        val interaction = makeInteraction(threeReactions, selectedId = "b")
        interaction.focus(220f, 220f)
        assertEquals(Outcome.Select("c", 2), interaction.release())
    }

    /**
     * Releasing on the plus reports nothing — the interaction hands over to the
     * system emoji picker instead.
     */
    @Test
    fun `releasing on the plus is not a selection`() {
        val interaction = makeInteraction(
            listOf(Slot.Reaction(reaction("a")), Slot.Reaction(reaction("b")), Slot.Another(null))
        )
        interaction.focus(220f, 220f)
        assertEquals(Outcome.Another(2), interaction.release())
    }

    /** The custom pick is selectable, and its id is the emoji itself. */
    @Test
    fun `releasing on the custom pick selects the emoji`() {
        val interaction = makeInteraction(
            listOf(Slot.Reaction(reaction("a")), Slot.Custom("🎉"), Slot.Another(null))
        )
        interaction.focus(172f, 220f)
        assertEquals(Outcome.Select("🎉", 1), interaction.release())
    }

    @Test
    fun `releasing on the current custom pick clears it`() {
        val interaction = makeInteraction(
            listOf(Slot.Reaction(reaction("a")), Slot.Custom("🎉"), Slot.Another(null)),
            selectedId = "🎉"
        )
        interaction.focus(172f, 220f)
        assertEquals(Outcome.Deselect(1), interaction.release())
    }

    /**
     * The plus is the last slot whether or not a custom pick precedes it. This
     * is the arithmetic that used to depend on two arrays differing in length
     * by exactly one.
     */
    @Test
    fun `the plus stays the last slot with a custom pick present`() {
        val interaction = makeInteraction(
            listOf(Slot.Reaction(reaction("a")), Slot.Custom("🎉"), Slot.Another(null))
        )
        interaction.focus(220f, 220f)
        assertEquals(Outcome.Another(2), interaction.release())
    }
}

class SeparatorTest {

    @Test
    fun `no separator without the another reaction section`() {
        assertNull(makeInteraction(threeReactions).separatorAfter)
    }

    @Test
    fun `separator sits before the another reaction section`() {
        val interaction = makeInteraction(
            listOf(Slot.Reaction(reaction("a")), Slot.Reaction(reaction("b")), Slot.Another(null))
        )
        assertEquals(2, interaction.separatorAfter)
    }

    @Test
    fun `the custom pick belongs to the another reaction section`() {
        val interaction = makeInteraction(
            listOf(Slot.Reaction(reaction("a")), Slot.Custom("🎉"), Slot.Another(null))
        )
        assertEquals(1, interaction.separatorAfter)
    }

    /** Nothing on the left of the divider means nothing to divide. */
    @Test
    fun `no separator when there are no reactions`() {
        assertNull(makeInteraction(listOf(Slot.Another(null))).separatorAfter)
        assertNull(
            makeInteraction(listOf(Slot.Custom("🎉"), Slot.Another(null))).separatorAfter
        )
    }
}
