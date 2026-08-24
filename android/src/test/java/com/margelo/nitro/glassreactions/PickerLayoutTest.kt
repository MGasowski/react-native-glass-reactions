package com.margelo.nitro.glassreactions

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Mirrors `Tests/PickerInteractionTests/PickerLayoutTests.swift` case for
 * case. When one side changes, the other should change with it.
 */

/** A 300×800 container — plenty of room unless a case pushes toward an edge. */
private val container = Size(300f, 800f)
private val pill = Size(100f, 40f)
private const val VERTICAL_GAP = 8f
private const val EDGE_MARGIN = 12f

private fun frame(
    triggerX: Float,
    triggerY: Float,
    triggerWidth: Float = 40f,
    pillSize: Size = pill,
    containerSize: Size = container
): PickerFrame = PickerLayout.frame(
    trigger = PickerFrame(
        left = triggerX,
        top = triggerY,
        right = triggerX + triggerWidth,
        bottom = triggerY + 40f
    ),
    pillSize = pillSize,
    containerSize = containerSize,
    verticalGap = VERTICAL_GAP,
    edgeMargin = EDGE_MARGIN
)

private const val EPSILON = 0.001f

class PickerLayoutTest {

    /**
     * With room on every side, the pill centres over the trigger and sits
     * [VERTICAL_GAP] above it — no clamp engaged.
     */
    @Test
    fun `centres over the trigger with room to spare`() {
        // trigger: x 100-140 (midX 120), y 200-230 (top 200)
        val result = frame(triggerX = 100f, triggerY = 200f)
        assertEquals(70f, result.left, EPSILON) // 120 - 100/2
        assertEquals(152f, result.top, EPSILON) // 200 - 40 - 8
        assertEquals(pill.width, result.right - result.left, EPSILON)
        assertEquals(pill.height, result.bottom - result.top, EPSILON)
    }

    /**
     * Centering reads the trigger's midpoint, not just its left edge — an
     * asymmetric trigger rect must still centre correctly.
     */
    @Test
    fun `centers using the triggers midpoint not its origin`() {
        val result = frame(triggerX = 50f, triggerY = 200f, triggerWidth = 80f)
        // midX = 50 + 80/2 = 90
        assertEquals(40f, result.left, EPSILON) // 90 - 100/2
    }

    @Test
    fun `clamps to the left edge`() {
        // midX = 10 + 20 = 30 -> raw x = -20, clamped to EDGE_MARGIN
        val result = frame(triggerX = 10f, triggerY = 200f, triggerWidth = 40f)
        assertEquals(EDGE_MARGIN, result.left, EPSILON)
    }

    @Test
    fun `clamps to the right edge`() {
        // midX = 270 + 20 = 290 -> raw x = 240, max allowed = 300-100-12 = 188
        val result = frame(triggerX = 270f, triggerY = 200f, triggerWidth = 40f)
        assertEquals(188f, result.left, EPSILON)
    }

    /**
     * When the pill is wider than the container, the naive upper bound
     * (`containerWidth - pillWidth - edgeMargin`) goes negative. The clamp
     * must not crash or invert; it collapses to the left margin.
     */
    @Test
    fun `collapses to the left margin when the pill is wider than the container`() {
        val wide = Size(100f, 40f)
        val narrowContainer = Size(80f, 800f)

        val leaningLeft = frame(
            triggerX = -200f, triggerY = 200f, pillSize = wide, containerSize = narrowContainer
        )
        val leaningRight = frame(
            triggerX = 500f, triggerY = 200f, pillSize = wide, containerSize = narrowContainer
        )

        assertEquals(EDGE_MARGIN, leaningLeft.left, EPSILON)
        assertEquals(EDGE_MARGIN, leaningRight.left, EPSILON)
    }

    @Test
    fun `clamps to the top edge when there is no room above`() {
        // top = 10 -> raw y = 10 - 40 - 8 = -38, clamped to EDGE_MARGIN
        val result = frame(triggerX = 100f, triggerY = 10f)
        assertEquals(EDGE_MARGIN, result.top, EPSILON)
    }

    /**
     * There is deliberately no lower bound on y — the pill is always anchored
     * above the trigger that opened it, so it can never run off the bottom.
     */
    @Test
    fun `has no lower bound on vertical position`() {
        val result = frame(triggerX = 100f, triggerY = 790f)
        assertEquals(790f - 40f - 8f, result.top, EPSILON)
    }

    /**
     * The returned frame's size is always the requested pill size, whether or
     * not either axis clamped.
     */
    @Test
    fun `returned size is always the pill size`() {
        val clamped = frame(triggerX = 10f, triggerY = 10f)
        assertEquals(pill.width, clamped.right - clamped.left, EPSILON)
        assertEquals(pill.height, clamped.bottom - clamped.top, EPSILON)
    }
}
