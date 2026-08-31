package com.margelo.nitro.glassreactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirrors `Tests/PickerInteractionTests/PickerLayoutTests.swift` case for
 * case. When one side changes, the other should change with it.
 */

/**
 * A 300x800 safe rect at the window's origin — plenty of room unless a case
 * shrinks it or pushes the press toward an edge.
 */
private val safeArea = PickerFrame(0f, 0f, 300f, 800f)
private val pill = Size(100f, 40f)
private const val GAP_ABOVE = 44f
private const val GAP_BELOW = 24f
private const val EDGE_MARGIN = 12f

/**
 * The trigger's top is deliberately not a parameter: it no longer feeds the
 * vertical placement at all, and the one case that cares about that —
 * `vertical placement follows the touch not the trigger` — builds its own rect.
 */
private fun frame(
    touchY: Float,
    touchX: Float = 120f,
    triggerX: Float = 100f,
    triggerWidth: Float = 40f,
    pillSize: Size = pill,
    container: PickerFrame = safeArea
): PickerFrame = PickerLayout.frame(
    touch = PickerPoint(touchX, touchY),
    trigger = PickerFrame(
        left = triggerX,
        top = 200f,
        right = triggerX + triggerWidth,
        bottom = 240f
    ),
    pillSize = pillSize,
    containerBounds = container,
    gapAbove = GAP_ABOVE,
    gapBelow = GAP_BELOW,
    edgeMargin = EDGE_MARGIN
)

private const val EPSILON = 0.001f

class PickerLayoutTest {

    /**
     * With room on every side, the pill centres over the trigger and sits
     * [GAP_ABOVE] above the press — no clamp engaged, no flip.
     */
    @Test
    fun `sits above the touch with room to spare`() {
        // trigger: x 100-140 (midX 120); touch at y 200
        val result = frame(touchY = 200f)
        assertEquals(70f, result.left, EPSILON) // 120 - 100/2
        assertEquals(116f, result.top, EPSILON) // 200 - 44 - 40
        assertEquals(pill.width, result.right - result.left, EPSILON)
        assertEquals(pill.height, result.bottom - result.top, EPSILON)
    }

    /**
     * The whole point of the change: on a tall trigger the pill tracks the
     * finger, not the trigger's top edge, so it lands the same distance from
     * the thumb whatever was pressed.
     */
    @Test
    fun `vertical placement follows the touch not the trigger`() {
        // A 300dp-tall trigger spanning y 100-400, pressed near its bottom.
        val result = PickerLayout.frame(
            touch = PickerPoint(120f, 380f),
            trigger = PickerFrame(left = 100f, top = 100f, right = 140f, bottom = 400f),
            pillSize = pill,
            containerBounds = safeArea,
            gapAbove = GAP_ABOVE,
            gapBelow = GAP_BELOW,
            edgeMargin = EDGE_MARGIN
        )
        // Anchored to the press (380 - 44 - 40), not to the trigger's top (100).
        assertEquals(296f, result.top, EPSILON)
    }

    /**
     * Horizontal placement is the other way round: the trigger decides, not
     * the finger, so the pill does not wander with where in a row you pressed.
     */
    @Test
    fun `horizontal placement follows the trigger not the touch`() {
        val left = frame(touchY = 200f, touchX = 102f)
        val right = frame(touchY = 200f, touchX = 138f)
        assertEquals(left.left, right.left, EPSILON)
        assertEquals(70f, left.left, EPSILON)
    }

    /**
     * Centering reads the trigger's midpoint, not just its left edge — an
     * asymmetric trigger rect must still centre correctly.
     */
    @Test
    fun `centers using the triggers midpoint not its origin`() {
        val result = frame(touchY = 200f, triggerX = 50f, triggerWidth = 80f)
        // midX = 50 + 80/2 = 90
        assertEquals(40f, result.left, EPSILON) // 90 - 100/2
    }

    @Test
    fun `clamps to the left edge`() {
        // midX = 10 + 20 = 30 -> raw x = -20, clamped to EDGE_MARGIN
        val result = frame(touchY = 200f, triggerX = 10f)
        assertEquals(EDGE_MARGIN, result.left, EPSILON)
    }

    @Test
    fun `clamps to the right edge`() {
        // midX = 270 + 20 = 290 -> raw x = 240, max allowed = 300-100-12 = 188
        val result = frame(touchY = 200f, triggerX = 270f)
        assertEquals(188f, result.left, EPSILON)
    }

    /**
     * When the pill is wider than the container, the naive upper bound
     * (`right - pillWidth - edgeMargin`) falls below the left margin. The
     * clamp must not crash or invert; it collapses to the left margin.
     */
    @Test
    fun `collapses to the left margin when the pill is wider than the container`() {
        val narrow = PickerFrame(0f, 0f, 80f, 800f)

        val leaningLeft = frame(touchY = 200f, triggerX = -200f, container = narrow)
        val leaningRight = frame(touchY = 200f, triggerX = 500f, container = narrow)

        assertEquals(EDGE_MARGIN, leaningLeft.left, EPSILON)
        assertEquals(EDGE_MARGIN, leaningRight.left, EPSILON)
    }

    /**
     * The flip: no room above the press, room below, so it goes below —
     * [GAP_BELOW] under the finger rather than jammed against the top edge.
     */
    @Test
    fun `flips below when there is no room above`() {
        // above = 40 - 44 - 40 = -44, outside the safe rect; below = 40 + 24 =
        // 64, whose bottom (104) is inside it.
        val result = frame(touchY = 40f)
        assertEquals(64f, result.top, EPSILON)
    }

    /**
     * The flip is conditional on the flipped placement *fitting*. When neither
     * side does, the pill falls back to above-and-clamped — exactly what it
     * did before the flip existed. It may then straddle the press, which is
     * why the callers' "did it flip" test is `top >= touch.y` and not a
     * midpoint comparison: this frame must read as above.
     */
    @Test
    fun `does not flip when below would also be clipped`() {
        val shallow = PickerFrame(0f, 0f, 300f, 100f)
        val result = frame(touchY = 40f, container = shallow)
        assertEquals(EDGE_MARGIN, result.top, EPSILON)
        assertTrue(result.top < 40f)
    }

    /**
     * The safe rect's top inset — the status bar — is what the flip is
     * measured against, not the window's origin. The same press flips here and
     * does not flip against a full-window rect.
     */
    @Test
    fun `the flip respects the safe rects top inset`() {
        val inset = PickerFrame(0f, 50f, 300f, 800f)
        // above = 100 - 44 - 40 = 16, which clears the window's top but not
        // the safe rect's (50 + 12 = 62).
        assertEquals(16f, frame(touchY = 100f).top, EPSILON)
        assertEquals(124f, frame(touchY = 100f, container = inset).top, EPSILON)
    }

    /**
     * Side insets — a landscape cutout — are honoured by the same clamp, with
     * [EDGE_MARGIN] applied inside the safe rect rather than from the window.
     */
    @Test
    fun `the clamp respects the safe rects side insets`() {
        val inset = PickerFrame(40f, 0f, 260f, 800f)
        assertEquals(52f, frame(touchY = 200f, triggerX = 10f, container = inset).left, EPSILON)
        assertEquals(148f, frame(touchY = 200f, triggerX = 270f, container = inset).left, EPSILON)
    }

    /**
     * There is deliberately no bottom clamp on the above-placement: the pill
     * hangs above the press, so the only thing the bottom edge decides is
     * whether a *flip* is allowed.
     */
    @Test
    fun `the above placement is never clamped against the bottom edge`() {
        val shortContainer = PickerFrame(0f, 0f, 300f, 700f)
        val result = frame(touchY = 780f, container = shortContainer)
        assertEquals(696f, result.top, EPSILON) // 780 - 44 - 40
    }

    /**
     * The returned frame's size is always the requested pill size, whether or
     * not either axis clamped or the placement flipped.
     */
    @Test
    fun `returned size is always the pill size`() {
        val result = frame(touchY = 10f, triggerX = 10f)
        assertEquals(pill.width, result.right - result.left, EPSILON)
        assertEquals(pill.height, result.bottom - result.top, EPSILON)
    }
}
