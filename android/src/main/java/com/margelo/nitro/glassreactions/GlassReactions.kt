package com.margelo.nitro.glassreactions

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.content.res.Configuration
import android.provider.Settings
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.dynamicanimation.animation.DynamicAnimation
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.abs
import kotlin.math.max

/**
 * Android has no Liquid Glass and no backdrop-blur primitive. The defined
 * fallback is a flat translucent capsule (spec §4.5).
 */
private object Metrics {
    const val ITEM_SIZE_DP = 40f
    const val ITEM_SPACING_DP = 8f
    const val CONTENT_INSET_DP = 8f

    /**
     * Reactions are rasterised at the largest size they will ever be drawn at
     * and scaled down from there, never up. See spec §6.5.
     */
    const val MAX_FOCUS_SCALE = 1.6f

    /** How far the focused reaction rises. */
    const val FOCUS_LIFT_DP = 6f

    /**
     * Dock-style magnification: the reactions either side of the focused one
     * partially scale and step aside, so a drag across the row reads as a
     * travelling wave rather than a binary highlight. Below MAX_FOCUS_SCALE —
     * rasters are only ever scaled down (spec §6.5).
     */
    const val NEIGHBOR_SCALE = 1.18f
    const val NEIGHBOR_LIFT_DP = 2f
    const val NEIGHBOR_SHIFT_DP = 5f

    /**
     * How far the chosen reaction overshoots past the focus scale when picked,
     * before it flies down to the trigger. The one moment a raster is shown
     * above MAX_FOCUS_SCALE — mid-motion, for a fraction of a second, where
     * softening is invisible.
     */
    const val SELECTION_POP_SCALE = 1.9f
}

/** A reaction resolved to what actually gets drawn. */
internal data class Renderable(
    val id: String,
    val bitmap: Bitmap?,
    val accessibilityLabel: String
)

internal class ReactionsPillView(context: android.content.Context) : ViewGroup(context) {

    private val density = context.resources.displayMetrics.density
    private val itemSize = dp(Metrics.ITEM_SIZE_DP)
    private val itemSpacing = dp(Metrics.ITEM_SPACING_DP)
    private val contentInset = dp(Metrics.CONTENT_INSET_DP)

    private val backdrop = View(context)
    private var renderables: List<Renderable> = emptyList()

    init {
        clipChildren = false
        addView(backdrop)
        applyBackdrop()
    }

    private fun dp(value: Float): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics
        ).toInt()

    /**
     * A single opaque-ish capsule behind the whole row, matching the one-container
     * look on iOS.
     *
     * Deliberately not a RenderEffect blur: `View.setRenderEffect` blurs the
     * view's *own* content, not what is painted behind it, so applying it to a
     * plain coloured backdrop costs GPU time and changes nothing visible. Android
     * has no true backdrop-blur primitive, so the defined fallback (spec §4.5) is
     * a flat translucent surface rather than an imitation of glass.
     */
    private fun applyBackdrop() {
        val night = (context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

        val fill = if (night) {
            Color.argb(0xF0, 0x2C, 0x2C, 0x2E)
        } else {
            Color.argb(0xF0, 0xF2, 0xF2, 0xF2)
        }
        val stroke = if (night) {
            Color.argb(0x33, 0xFF, 0xFF, 0xFF)
        } else {
            Color.argb(0x1F, 0x00, 0x00, 0x00)
        }

        backdrop.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            setStroke(dp(1f).coerceAtLeast(1), stroke)
        }
        // No elevation on the backdrop: elevation reorders z within the parent,
        // so raising it paints the capsule over the reactions instead of behind
        // them. Child order alone puts the backdrop first.
    }

    /**
     * The resting alpha of each reaction: dimmed when another reaction is the
     * current selection. Kept so animations that temporarily change alpha (the
     * open cascade, the selection celebration) can settle back to it rather
     * than clobbering the dim.
     */
    private var baseAlphas: List<Float> = emptyList()

    fun apply(items: List<Renderable>, selectedId: String?) {
        renderables = items

        // Drop every child except the backdrop, then rebuild. Any springs bound
        // to the discarded views go with them.
        springs.values.forEach { it.cancel() }
        springs.clear()
        while (childCount > 1) removeViewAt(1)

        baseAlphas = items.map { renderable ->
            if (selectedId != null && renderable.id != selectedId) 0.55f else 1f
        }

        items.forEachIndexed { index, renderable ->
            val imageView = ImageView(context).apply {
                setImageBitmap(renderable.bitmap)
                scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = renderable.accessibilityLabel
                alpha = baseAlphas[index]
            }
            addView(imageView)
        }

        requestLayout()
        invalidate()
    }

    private fun baseAlpha(position: Int): Float =
        baseAlphas.getOrElse(position - 1) { 1f }

    /**
     * Resolution entry point shared with the host. Android renders emoji only in
     * 1.0 — `symbolAndroid` names a Material Symbol, which needs the Material
     * Symbols font shipped in the AAR. Because `emoji` is required on every item
     * (spec §5), falling back costs nothing and never blanks the picker.
     */
    fun applyItems(
        items: Array<NativeReactionItem>,
        selectedId: String?,
        @Suppress("UNUSED_PARAMETER") renderMode: ReactionRenderMode
    ) {
        apply(
            items.map { Renderable(it.id, rasteriseEmoji(it.emoji), it.accessibilityLabel) },
            selectedId
        )
    }

    /**
     * Reduced motion: Android exposes this as the system animator duration
     * scale being zero rather than a dedicated flag (spec §6.3).
     */
    private val reduceMotion: Boolean
        get() = Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f
        ) == 0f

    /**
     * One animation per (view, property), reused. Starting a fresh
     * SpringAnimation while another is still running on the same property
     * leaves two animations fighting, and an interrupted one parks the view at
     * a stale scale — which looks like a single reaction stuck smaller than its
     * neighbours.
     */
    private val springs = HashMap<Pair<Int, DynamicAnimation.ViewProperty>, SpringAnimation>()

    private fun spring(
        view: View,
        property: DynamicAnimation.ViewProperty,
        target: Float,
        stiffness: Float = SpringForce.STIFFNESS_MEDIUM,
        damping: Float = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY
    ) {
        val key = System.identityHashCode(view) to property
        val animation = springs.getOrPut(key) {
            SpringAnimation(view, property).apply {
                spring = SpringForce().setStiffness(stiffness).setDampingRatio(damping)
            }
        }
        // Retarget in place rather than cancelling and restarting. cancel()
        // leaves the value where it stopped and the next start jumps, which
        // reads as a pop; animateToFinalPosition carries the current position
        // and velocity into the new target.
        animation.spring.setStiffness(stiffness).setDampingRatio(damping)
        animation.animateToFinalPosition(target)
    }

    /**
     * Work scheduled with a delay for staggered animation. Tracked so a reopen
     * arriving mid-flight can cancel everything still pending before reusing
     * the views.
     */
    private val pendingRunnables = ArrayList<Runnable>()

    private fun postStaggered(delayMs: Long, action: () -> Unit) {
        val runnable = Runnable(action)
        pendingRunnables.add(runnable)
        postDelayed(runnable, delayMs)
    }

    private fun cancelInFlightAnimations() {
        pendingRunnables.forEach { removeCallbacks(it) }
        pendingRunnables.clear()
        animate().cancel()
        backdrop.animate().cancel()
        for (position in 1 until childCount) getChildAt(position).animate().cancel()
        springs.values.forEach { it.cancel() }
    }

    /** Collapsed state, set before the picker is attached. */
    fun prepareForPresentation() {
        // A reopen can land mid-celebration, with animations still in flight
        // and the backdrop faded. Stop everything and restore before collapsing.
        cancelInFlightAnimations()
        backdrop.alpha = 1f
        backdrop.scaleX = 1f
        backdrop.scaleY = 1f
        backdrop.translationY = 0f

        alpha = 0f
        if (reduceMotion) {
            scaleX = 1f
            scaleY = 1f
            translationY = 0f
            for (position in 1 until childCount) {
                getChildAt(position).apply {
                    alpha = baseAlpha(position)
                    scaleX = 1f; scaleY = 1f
                    translationX = 0f; translationY = 0f
                }
            }
            return
        }
        // Grows from the bottom edge, the side nearest the trigger.
        pivotY = (itemSize + contentInset * 2).toFloat()
        scaleX = 0.86f
        scaleY = 0.86f
        translationY = 0f
        for (position in 1 until childCount) {
            // Each reaction starts small and below its resting place, so the
            // open reads as the row rising out of the trigger.
            getChildAt(position).apply {
                alpha = 0f
                scaleX = 0.4f; scaleY = 0.4f
                translationX = 0f
                translationY = dp(10f).toFloat()
            }
        }
    }

    fun animateIn() {
        if (reduceMotion) {
            animate().alpha(1f).setDuration(150).start()
            return
        }
        animate().alpha(1f).setDuration(120).start()
        spring(this, SpringAnimation.SCALE_X, 1f)
        spring(this, SpringAnimation.SCALE_Y, 1f)

        for (position in 1 until childCount) {
            val child = getChildAt(position)
            child.animate()
                .alpha(baseAlpha(position))
                .setStartDelay((position - 1) * 30L)
                .setDuration(150)
                .start()
            // The rise and the settle run as springs from the start, staggered
            // to match the fade, so each reaction bounces up into place.
            postStaggered((position - 1) * 30L) {
                spring(child, SpringAnimation.SCALE_X, 1f)
                spring(child, SpringAnimation.SCALE_Y, 1f)
                spring(child, SpringAnimation.TRANSLATION_Y, 0f)
            }
        }
    }

    fun animateOut(completion: () -> Unit) {
        animate()
            .alpha(0f)
            .scaleX(if (reduceMotion) 1f else 0.9f)
            .scaleY(if (reduceMotion) 1f else 0.9f)
            // Sinks back toward the trigger it grew out of — the inverse of
            // the open — rather than shrinking in place.
            .translationY(if (reduceMotion) 0f else dp(6f).toFloat())
            .setDuration(200)
            .withEndAction {
                resetAfterDismissal()
                completion()
            }
            .start()
    }

    /**
     * The selection celebration: everything that was not chosen shrinks away,
     * staggered outward from the choice; the chosen reaction pops past its
     * focus scale, then shrinks and flies along (flightX, flightY) — the vector
     * from its resting position to the trigger — so the reaction reads as
     * landing on the row that was pressed.
     */
    fun animateSelection(index: Int, flightX: Float, flightY: Float, completion: () -> Unit) {
        val chosen = getChildAt(index + 1)
        if (reduceMotion || chosen == null) {
            animateOut(completion)
            return
        }

        // The capsule leaves first, sinking slightly as it fades.
        backdrop.animate()
            .alpha(0f)
            .scaleX(0.9f).scaleY(0.9f)
            .translationY(dp(4f).toFloat())
            .setStartDelay(0)
            .setDuration(250)
            .start()

        // Non-selected reactions shrink away in a wave spreading outward from
        // the choice, pulling the eye toward what was picked.
        for (position in 1 until childCount) {
            if (position == index + 1) continue
            val child = getChildAt(position)
            child.animate()
                .alpha(0f)
                .scaleX(0.3f).scaleY(0.3f)
                .setStartDelay(abs(position - 1 - index) * 30L)
                .setDuration(160)
                .start()
        }

        // The choice pops past its focus scale…
        chosen.elevation = 2f
        spring(chosen, SpringAnimation.SCALE_X, Metrics.SELECTION_POP_SCALE,
            damping = SpringForce.DAMPING_RATIO_HIGH_BOUNCY)
        spring(chosen, SpringAnimation.SCALE_Y, Metrics.SELECTION_POP_SCALE,
            damping = SpringForce.DAMPING_RATIO_HIGH_BOUNCY)

        // …then flies down to the trigger. Teardown is bound to the end of this
        // leg, matching iOS (spec §4.3).
        postStaggered(180L) {
            spring(chosen, SpringAnimation.SCALE_X, 0.2f,
                damping = SpringForce.DAMPING_RATIO_NO_BOUNCY)
            spring(chosen, SpringAnimation.SCALE_Y, 0.2f,
                damping = SpringForce.DAMPING_RATIO_NO_BOUNCY)
            spring(chosen, SpringAnimation.TRANSLATION_X, flightX,
                damping = SpringForce.DAMPING_RATIO_NO_BOUNCY)
            spring(chosen, SpringAnimation.TRANSLATION_Y, flightY,
                damping = SpringForce.DAMPING_RATIO_NO_BOUNCY)
            // Explicit zero delay: View.animate() reuses one animator per view,
            // and a stagger delay from the open cascade would otherwise leak
            // into this leg.
            chosen.animate()
                .alpha(0f)
                .setStartDelay(0)
                .setDuration(280)
                .withEndAction {
                    resetAfterDismissal()
                    completion()
                }
                .start()
        }
    }

    /**
     * Puts the pooled instance back to a clean resting state after teardown, so
     * the next open never inherits leftover transforms, alphas, or a faded
     * backdrop.
     */
    private fun resetAfterDismissal() {
        alpha = 1f
        scaleX = 1f
        scaleY = 1f
        translationY = 0f
        backdrop.alpha = 1f
        backdrop.scaleX = 1f
        backdrop.scaleY = 1f
        backdrop.translationY = 0f
        for (position in 1 until childCount) {
            getChildAt(position).apply {
                alpha = baseAlpha(position)
                scaleX = 1f; scaleY = 1f
                translationX = 0f; translationY = 0f
                elevation = 0f
            }
        }
    }

    /**
     * Highlights the reaction under the finger. Dock-style: the focused
     * reaction rises to full scale, its immediate neighbours partially follow
     * and step aside, and everything else settles back — so a drag across the
     * row reads as a travelling wave rather than a binary highlight.
     */
    fun setFocusedIndex(index: Int?) {
        for (position in 1 until childCount) {
            val child = getChildAt(position)
            val itemIndex = position - 1
            val focused = itemIndex == index
            val isNeighbor = index != null && abs(itemIndex - index) == 1

            val scale: Float
            val lift: Float
            var shift = 0f
            when {
                focused -> {
                    scale = Metrics.MAX_FOCUS_SCALE
                    lift = -dp(Metrics.FOCUS_LIFT_DP).toFloat()
                }
                isNeighbor -> {
                    scale = Metrics.NEIGHBOR_SCALE
                    lift = -dp(Metrics.NEIGHBOR_LIFT_DP).toFloat()
                    // Pushed away from the focused item so the magnified
                    // raster has room.
                    val direction = if (itemIndex < index!!) -1f else 1f
                    shift = direction * dp(Metrics.NEIGHBOR_SHIFT_DP).toFloat()
                }
                else -> {
                    scale = 1f
                    lift = 0f
                }
            }

            child.elevation = if (focused) 2f else if (isNeighbor) 1f else 0f

            if (reduceMotion) {
                child.scaleX = scale
                child.scaleY = scale
                child.translationX = shift
                child.translationY = lift
                continue
            }
            // Scale and translation only — no layout pass per frame.
            spring(child, SpringAnimation.SCALE_X, scale)
            spring(child, SpringAnimation.SCALE_Y, scale)
            spring(child, SpringAnimation.TRANSLATION_X, shift)
            spring(child, SpringAnimation.TRANSLATION_Y, lift)
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val count = renderables.size
        val width = if (count == 0) 0 else
            count * itemSize + max(0, count - 1) * itemSpacing + contentInset * 2
        val height = itemSize + contentInset * 2
        setMeasuredDimension(
            resolveSize(width, widthMeasureSpec),
            resolveSize(height, heightMeasureSpec)
        )
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val height = b - t
        val width = r - l

        backdrop.layout(0, 0, width, height)
        (backdrop.background as? GradientDrawable)?.cornerRadius = height / 2f

        var x = contentInset
        val y = (height - itemSize) / 2

        // Child 0 is the backdrop; reaction views follow in order.
        for (index in 1 until childCount) {
            getChildAt(index).layout(x, y, x + itemSize, y + itemSize)
            x += itemSize + itemSpacing
        }
    }

    /** Emoji are drawn once into a bitmap and reused (spec §6.5). */
    fun rasteriseEmoji(value: String): Bitmap? {
        if (value.isEmpty()) return null

        val side = (itemSize * Metrics.MAX_FOCUS_SCALE).toInt().coerceAtLeast(1)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = side * 0.82f
            textAlign = Paint.Align.CENTER
        }

        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val metrics = paint.fontMetrics
        val baseline = side / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(value, side / 2f, baseline, paint)
        return bitmap
    }
}
