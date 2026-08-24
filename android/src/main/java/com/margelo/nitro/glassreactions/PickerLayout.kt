package com.margelo.nitro.glassreactions

/**
 * A plain width/height pair. Kotlin has no built-in equivalent to `CGSize`;
 * this exists only so [PickerLayout] can mirror iOS's signature rather than
 * taking two bare floats for pill size and two more for container size.
 */
data class Size(val width: Float, val height: Float)

/**
 * Where the pill goes, given a trigger and a container to fit inside.
 *
 * The one job here — clamp a proposed origin into a container — was
 * previously inline in `openPicker()`, the same method that also does
 * hit-testing, scroll-disabling and surface sampling. It is pure arithmetic
 * and was never reachable without a real window, so it was also the one piece
 * of geometry in the interaction path with no test coverage.
 *
 * `trigger` and `containerSize` must already be in the *container's own*
 * local coordinate space — `(0, 0)` at the container's top-left, same units
 * as `containerSize`. On iOS that is free: the overlay is a `UIWindow`
 * covering the full screen, so window space and overlay space already
 * coincide. Android's container is a `FrameLayout` whose on-screen origin is
 * not guaranteed to be `(0, 0)` (status bar insets and the like), so the
 * adapter does a `getLocationOnScreen` subtraction before calling in — that
 * translation is a platform-specific concern and stays adapter-side rather
 * than migrating into this module, which would otherwise need an iOS branch
 * that does nothing.
 *
 * Mirrors `PickerLayout` in `ios/PickerLayout.swift`. When one side changes,
 * the other should change with it.
 */
object PickerLayout {

    /**
     * The frame the pill should be given.
     *
     * `verticalGap` and `edgeMargin` are parameters rather than constants this
     * module owns, mirroring how `PickerInteraction` takes `tolerance` rather
     * than hardcoding it: the actual values are each adapter's to decide, this
     * module only knows the rule for applying them.
     */
    fun frame(
        trigger: PickerFrame,
        pillSize: Size,
        containerSize: Size,
        verticalGap: Float,
        edgeMargin: Float
    ): PickerFrame {
        val triggerMidX = (trigger.left + trigger.right) / 2f
        var left = triggerMidX - pillSize.width / 2f
        var top = trigger.top - pillSize.height - verticalGap

        // The upper bound is itself floored at `edgeMargin`: when the pill is
        // wider than the container, `containerSize.width - pillSize.width -
        // edgeMargin` goes negative, and clamping `left` into a range whose
        // upper bound is below its lower bound would be undefined. Flooring
        // the upper bound collapses the range to a single point at the left
        // margin instead.
        val maxLeft = (containerSize.width - pillSize.width - edgeMargin)
            .coerceAtLeast(edgeMargin)
        left = left.coerceIn(edgeMargin, maxLeft)

        // No upper bound on top: nothing below the pill needs protecting from
        // the pill running off the *bottom* of the container, since it is
        // always anchored above the trigger that opened it.
        top = top.coerceAtLeast(edgeMargin)

        return PickerFrame(
            left = left,
            top = top,
            right = left + pillSize.width,
            bottom = top + pillSize.height
        )
    }
}
