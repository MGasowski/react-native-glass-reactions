package com.margelo.nitro.glassreactions

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.content.res.Configuration
import android.provider.Settings
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
     * The divider between the consumer's reactions and the "another reaction"
     * section (custom pick + plus): a hairline with a gap either side. Extra
     * width it adds over a normal inter-item gap.
     */
    const val SEPARATOR_LINE_DP = 1f
    const val SEPARATOR_GAP_DP = 8f

    /**
     * How far the chosen reaction overshoots past the focus scale when picked,
     * before it flies down to the trigger. The one moment a raster is shown
     * above MAX_FOCUS_SCALE — mid-motion, for a fraction of a second, where
     * softening is invisible.
     */
    const val SELECTION_POP_SCALE = 1.9f
}

/**
 * Whether the surface behind a view is dark.
 *
 * The picker sits above arbitrary app content, so the system theme says
 * nothing about what is actually behind it — the pixels decide instead:
 * walking view background colours is defeated by React Native's view
 * flattening (the painted colour often lives on no ancestor at all), so the
 * trigger's on-screen region is software-drawn squashed into a handful of
 * pixels and averaged. One tiny render per open, at gesture-begin — never on
 * the scroll or focus path.
 *
 * Named and placed to mirror `SurfaceAppearance` in `ios/ReactionsPillView.swift`
 * — the pill's file is where both platforms define it, even though the host is
 * what calls it. `decor` is passed in explicitly rather than resolved here: a
 * `View` has no path to its owning `Window` without an `Activity` reference,
 * which is the host's to look up, not this object's.
 */
internal object SurfaceAppearance {
    fun isDark(view: View, decor: View?): Boolean {
        val nightFallback = (view.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        return try {
            if (decor == null) return nightFallback
            val width = view.width
            val height = view.height
            if (width < 1 || height < 1) return nightFallback

            val location = IntArray(2)
            view.getLocationInWindow(location)

            val sample = 4
            val bitmap = Bitmap.createBitmap(sample, sample, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.scale(sample.toFloat() / width, sample.toFloat() / height)
            canvas.translate(-location[0].toFloat(), -location[1].toFloat())
            decor.draw(canvas)

            var total = 0.0
            for (y in 0 until sample) {
                for (x in 0 until sample) {
                    val pixel = bitmap.getPixel(x, y)
                    total += (Color.red(pixel) + Color.green(pixel) + Color.blue(pixel)) /
                        (3.0 * 255.0)
                }
            }
            bitmap.recycle()
            total / (sample * sample) < 0.5
        } catch (_: Throwable) {
            nightFallback
        }
    }
}

/** A reaction resolved to what actually gets drawn. */
internal data class Renderable(
    val id: String,
    val bitmap: Bitmap?,
    val accessibilityLabel: String
)

/**
 * Implements [SlotGeometry] because it is the layout authority: the same
 * `slotCenterX` that positions the reactions is what the interaction hit-tests
 * against, so the two can never disagree about where a slot is.
 */
internal class ReactionsPillView(context: android.content.Context) :
    ViewGroup(context), SlotGeometry {

    private val density = context.resources.displayMetrics.density
    private val itemSize = dp(Metrics.ITEM_SIZE_DP)
    private val itemSpacing = dp(Metrics.ITEM_SPACING_DP)
    private val contentInset = dp(Metrics.CONTENT_INSET_DP)

    private val backdrop = View(context)
    private var renderables: List<Renderable> = emptyList()

    /**
     * The reaction views, tracked explicitly rather than recovered from child
     * indices — the child list is no longer items-only now that a separator
     * can be present.
     */
    private val itemViews = ArrayList<ImageView>()

    /** Index of the first item after the section divider; null for none. */
    private var separatorAfter: Int? = null

    private val separatorExtra: Int
        get() = dp(Metrics.SEPARATOR_GAP_DP) * 2 + dp(Metrics.SEPARATOR_LINE_DP)
            .coerceAtLeast(1) - itemSpacing

    private val separatorPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    /**
     * Whether the surface the pill floats over is dark. The picker sits above
     * arbitrary app content, so the system theme says nothing about what is
     * actually behind it — the host samples the trigger's backing colours and
     * sets this before each open. Null falls back to the system theme.
     */
    private var surfaceDark: Boolean? = null

    private val isDarkAppearance: Boolean
        get() = surfaceDark ?: ((context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES)

    fun setSurfaceAppearance(dark: Boolean) {
        if (surfaceDark == dark) return
        surfaceDark = dark
        applyBackdrop()
        invalidate()
    }

    init {
        clipChildren = false
        // The ViewGroup draws the separator hairline itself: a child view
        // would shift every index-based animation loop, a drawn line shifts
        // nothing.
        setWillNotDraw(false)
        addView(backdrop)
        applyBackdrop()
    }

    // MARK: Slot geometry

    /**
     * Centre of slot `index` in the pill's own coordinates. Single source of
     * truth for layout, hit-testing, and the selection flight vector — slots
     * are not uniform once the separator inserts its extra width.
     */
    fun slotCenterX(index: Int): Float {
        var x = contentInset + index * (itemSize + itemSpacing) + itemSize / 2f
        val after = separatorAfter
        if (after != null && index >= after) x += separatorExtra
        return x
    }

    /** The slot nearest the given local x, clamped to the row. */
    override fun slotIndex(localX: Float): Int? {
        if (renderables.isEmpty()) return null
        return renderables.indices.minByOrNull { abs(localX - slotCenterX(it)) }
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
        val night = isDarkAppearance

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

    private fun apply(items: List<Renderable>, selectedId: String?, separatorAfter: Int?) {
        renderables = items
        this.separatorAfter = separatorAfter

        // Drop every item view, then rebuild. Any springs bound to the
        // discarded views go with them.
        springs.values.forEach { it.cancel() }
        springs.clear()
        itemViews.forEach { removeView(it) }
        itemViews.clear()

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
            itemViews.add(imageView)
        }

        requestLayout()
        invalidate()
    }

    private fun baseAlpha(index: Int): Float = baseAlphas.getOrElse(index) { 1f }

    /**
     * Draws one row of slots.
     *
     * Renderables are *derived from* the interaction's slots rather than built
     * alongside them, which is what makes it impossible for the drawn row and
     * the hit-tested row to disagree about what sits at a given index.
     *
     * Resolving each slot is [ReactionResolver]'s job, not the pill's — the
     * pill only supplies what the resolver cannot know for itself: the pixel
     * side length reactions rasterise at, and the tint colour the "another
     * reaction" chrome bakes in for the current appearance.
     */
    fun apply(slots: List<Slot>, selectedId: String?, renderMode: ReactionRenderMode) {
        val side = (itemSize * Metrics.MAX_FOCUS_SCALE).toInt().coerceAtLeast(1)
        val tintColor = if (isDarkAppearance) {
            Color.WHITE
        } else {
            Color.argb(0xFF, 0x1C, 0x1C, 0x1E)
        }
        apply(
            slots.map { ReactionResolver.renderable(it, renderMode, side, tintColor) },
            selectedId,
            slots.separatorAfter
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
        itemViews.forEach { it.animate().cancel() }
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
            itemViews.forEachIndexed { index, view ->
                view.alpha = baseAlpha(index)
                view.scaleX = 1f; view.scaleY = 1f
                view.translationX = 0f; view.translationY = 0f
            }
            return
        }
        // Grows from the bottom edge, the side nearest the trigger.
        pivotY = (itemSize + contentInset * 2).toFloat()
        scaleX = 0.86f
        scaleY = 0.86f
        translationY = 0f
        itemViews.forEach { view ->
            // Each reaction starts small and below its resting place, so the
            // open reads as the row rising out of the trigger.
            view.alpha = 0f
            view.scaleX = 0.4f; view.scaleY = 0.4f
            view.translationX = 0f
            view.translationY = dp(10f).toFloat()
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

        itemViews.forEachIndexed { index, child ->
            child.animate()
                .alpha(baseAlpha(index))
                .setStartDelay(index * 30L)
                .setDuration(150)
                .start()
            // The rise and the settle run as springs from the start, staggered
            // to match the fade, so each reaction bounces up into place.
            postStaggered(index * 30L) {
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
     * The selection celebration — a stamp: everything that was not chosen
     * shrinks away, staggered outward from the choice; the chosen reaction
     * pops past its focus scale, then presses back down in place and fades —
     * like a stamp lifting off the row. No flight across the screen: the
     * consumer's own UI reflects the selection at the same moment, and an
     * emoji streaking from picker to row read as a glitch.
     */
    fun animateSelection(index: Int, completion: () -> Unit) {
        val chosen = itemViews.getOrNull(index)
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
        itemViews.forEachIndexed { itemIndex, child ->
            if (itemIndex == index) return@forEachIndexed
            child.animate()
                .alpha(0f)
                .scaleX(0.3f).scaleY(0.3f)
                .setStartDelay(abs(itemIndex - index) * 30L)
                .setDuration(160)
                .start()
        }
        // The divider is chrome like the capsule, so it leaves with it.
        separatorVisible = false
        invalidate()

        // The choice pops past its focus scale…
        chosen.elevation = 2f
        spring(chosen, SpringAnimation.SCALE_X, Metrics.SELECTION_POP_SCALE,
            damping = SpringForce.DAMPING_RATIO_HIGH_BOUNCY)
        spring(chosen, SpringAnimation.SCALE_Y, Metrics.SELECTION_POP_SCALE,
            damping = SpringForce.DAMPING_RATIO_HIGH_BOUNCY)

        // …then presses back down in place and fades, like a stamp lifting
        // off. Teardown is bound to the end of this leg, matching iOS (§4.3).
        postStaggered(180L) {
            spring(chosen, SpringAnimation.SCALE_X, 1f,
                damping = SpringForce.DAMPING_RATIO_NO_BOUNCY)
            spring(chosen, SpringAnimation.SCALE_Y, 1f,
                damping = SpringForce.DAMPING_RATIO_NO_BOUNCY)
            // Explicit zero delay: View.animate() reuses one animator per view,
            // and a stagger delay from the open cascade would otherwise leak
            // into this leg.
            chosen.animate()
                .alpha(0f)
                .setStartDelay(0)
                .setDuration(220)
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
        separatorVisible = true
        invalidate()
        itemViews.forEachIndexed { index, view ->
            view.alpha = baseAlpha(index)
            view.scaleX = 1f; view.scaleY = 1f
            view.translationX = 0f; view.translationY = 0f
            view.elevation = 0f
        }
    }

    /**
     * Highlights the reaction under the finger. Dock-style: the focused
     * reaction rises to full scale, its immediate neighbours partially follow
     * and step aside, and everything else settles back — so a drag across the
     * row reads as a travelling wave rather than a binary highlight.
     */
    fun setFocusedIndex(index: Int?) {
        itemViews.forEachIndexed { itemIndex, child ->
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
                return@forEachIndexed
            }
            // Scale and translation only — no layout pass per frame.
            spring(child, SpringAnimation.SCALE_X, scale)
            spring(child, SpringAnimation.SCALE_Y, scale)
            spring(child, SpringAnimation.TRANSLATION_X, shift)
            spring(child, SpringAnimation.TRANSLATION_Y, lift)
        }
    }

    /** Cleared during the selection celebration so the divider leaves with the capsule. */
    private var separatorVisible = true

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val count = renderables.size
        var width = if (count == 0) 0 else
            count * itemSize + max(0, count - 1) * itemSpacing + contentInset * 2
        if (count > 0 && separatorAfter != null) width += separatorExtra
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

        val y = (height - itemSize) / 2

        itemViews.forEachIndexed { index, view ->
            val left = (slotCenterX(index) - itemSize / 2f).toInt()
            view.layout(left, y, left + itemSize, y + itemSize)
        }
    }

    // dispatchDraw, not onDraw: children (the backdrop capsule included) paint
    // after onDraw and would cover the line.
    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        val after = separatorAfter ?: return
        if (!separatorVisible) return

        separatorPaint.color =
            if (isDarkAppearance) Color.argb(0x40, 0xFF, 0xFF, 0xFF)
            else Color.argb(0x40, 0x00, 0x00, 0x00)

        // Centred in the widened gap before the first "another reaction" slot.
        val lineWidth = dp(Metrics.SEPARATOR_LINE_DP).coerceAtLeast(1).toFloat()
        val lineX = slotCenterX(after) - itemSize / 2f -
            dp(Metrics.SEPARATOR_GAP_DP) - lineWidth / 2f
        val lineHeight = itemSize * 0.6f
        val top = (this.height - lineHeight) / 2f
        canvas.drawRoundRect(
            lineX - lineWidth / 2f, top, lineX + lineWidth / 2f, top + lineHeight,
            lineWidth / 2f, lineWidth / 2f, separatorPaint
        )
    }

}

/**
 * Draws the bitmaps a `Renderable` carries.
 *
 * Named and placed to mirror `ReactionRasteriser` in
 * `ios/ReactionsPillView.swift`. The two platforms genuinely differ here, not
 * just in name: iOS rasterises "another reaction" chrome as a template image
 * and leaves tinting to `UIImageView.tintColor` at display time, so its
 * rasteriser needs no colour at all. A plain Android `Bitmap` has no
 * equivalent — colour has to be baked in when the pixels are drawn — so `side`
 * and `color` are explicit parameters here where iOS's equivalents read from
 * `Metrics` and a template render mode instead. That is a real platform
 * difference, not a gap to close.
 */
private object ReactionRasteriser {

    /** Emoji are drawn once into a bitmap and reused (spec §6.5). */
    fun emoji(value: String, side: Int): Bitmap? {
        if (value.isEmpty()) return null

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

    /**
     * Chrome for the trailing "another reaction" item: a dashed emoji
     * silhouette, by default with a plus badge in the corner. Drawn rather than
     * taken from a font so weight, colour, and the knockout plus match the iOS
     * glyph.
     */
    fun anotherReaction(side: Int, color: Int, badge: Boolean = true): Bitmap {
        val s = side.toFloat()

        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Without the badge the glyph owns the whole tile: nothing has to be
        // left clear in the corner, so it is drawn larger and centred.
        val bodySize = s * if (badge) 0.70f else 0.84f
        val bodyLeft = if (badge) s * 0.10f else (s - bodySize) / 2f
        val bodyTop = if (badge) s * 0.06f else (s - bodySize) / 2f
        val bodyRect = RectF(bodyLeft, bodyTop, bodyLeft + bodySize, bodyTop + bodySize)
        val dash = DashPathEffect(floatArrayOf(s * 0.10f, s * 0.065f), 0f)
        val body = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = s * 0.055f
            strokeCap = Paint.Cap.ROUND
            pathEffect = dash
        }
        canvas.drawOval(bodyRect, body)

        val fillFace = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.FILL
        }
        val eyeR = bodySize * 0.055f
        val eyeY = bodyRect.top + bodySize * 0.38f
        val eyeSpread = bodySize * 0.13f
        canvas.drawCircle(bodyRect.centerX() - eyeSpread, eyeY, eyeR, fillFace)
        canvas.drawCircle(bodyRect.centerX() + eyeSpread, eyeY, eyeR, fillFace)

        // Solid smile: a dashed arc at this size collapses into specks.
        val smile = Paint(body).apply {
            pathEffect = null
            strokeWidth = s * 0.055f * 0.85f
        }
        val smileRect = RectF(
            bodyRect.centerX() - bodySize * 0.25f,
            bodyRect.centerY() - bodySize * 0.16f,
            bodyRect.centerX() + bodySize * 0.15f,
            bodyRect.centerY() + bodySize * 0.24f
        )
        canvas.drawArc(smileRect, 20f, 140f, false, smile)

        if (!badge) return bitmap

        val badgeSize = s * 0.38f
        val badgeRect = RectF(
            s - badgeSize - s * 0.03f,
            s - badgeSize - s * 0.03f,
            s - s * 0.03f,
            s - s * 0.03f
        )

        val clear = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
        }
        val knockoutPad = s * 0.05f
        canvas.drawOval(
            RectF(
                badgeRect.left - knockoutPad,
                badgeRect.top - knockoutPad,
                badgeRect.right + knockoutPad,
                badgeRect.bottom + knockoutPad
            ),
            clear
        )

        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.FILL
        }
        canvas.drawOval(badgeRect, fill)

        val plus = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
            style = Paint.Style.STROKE
            strokeWidth = badgeSize * 0.14f
            strokeCap = Paint.Cap.ROUND
        }
        val cx = badgeRect.centerX()
        val cy = badgeRect.centerY()
        val arm = badgeSize * 0.22f
        canvas.drawLine(cx - arm, cy, cx + arm, cy, plus)
        canvas.drawLine(cx, cy - arm, cx, cy + arm, plus)
        return bitmap
    }
}

/**
 * Turns a slot into a drawable, applying the fallback chain from
 * [ReactionResolution] — the pure decision — by walking it and drawing the
 * first candidate that actually rasterises. Named and placed to mirror
 * `ReactionResolver` in `ios/ReactionsPillView.swift`.
 *
 * On iOS this is called from the host, which resolves before handing the pill
 * a plain renderable list. On Android it is called from the pill's own
 * `apply`, which resolves internally — a call-site difference already present
 * before this refactor, kept as is: relocating *which side calls the
 * resolver* is a bigger, riskier change than naming the resolver itself, and
 * changes no observable behaviour either way.
 */
private object ReactionResolver {
    /**
     * Synthetic id carried by the trailing "another reaction" plus item.
     * Never reported through onSelect — releasing on it opens the picker.
     */
    const val ANOTHER_REACTION_ID = "__another_reaction__"

    /**
     * Default label for the "another reaction" item. English-only, which is
     * why `accessibilityLabel` is overridable.
     */
    const val ANOTHER_REACTION_LABEL = "Add another reaction"

    /**
     * Android renders emoji only in 1.0 (`symbolsSupported = false`), so in
     * practice the order never offers a symbol and this always draws an emoji
     * or the built-in glyph — but the walk itself does not know that, which is
     * what lets Android gain symbol support later by flipping one flag rather
     * than rewriting this function.
     */
    fun renderable(
        slot: Slot,
        renderMode: ReactionRenderMode,
        side: Int,
        tintColor: Int
    ): Renderable {
        val mode = if (renderMode == ReactionRenderMode.AUTO) RenderMode.Auto else RenderMode.Emoji
        val order = ReactionResolution.resolutionOrder(slot, mode, symbolsSupported = false)

        for (candidate in order) {
            val image = image(candidate, side, tintColor) ?: continue
            return Renderable(id(slot), image, label(slot))
        }

        // Unreached in practice: the chain always ends in Emoji or BuiltIn, and
        // NativeReactionItem.emoji is required, so only an empty custom pick
        // could get here.
        return Renderable(id(slot), null, label(slot))
    }

    private fun image(candidate: Candidate, side: Int, tintColor: Int): Bitmap? = when (candidate) {
        // Android has no symbol rasteriser in 1.0 — these are unreachable
        // while resolutionOrder is called with symbolsSupported = false, kept
        // exhaustive rather than throwing so a future symbol-supporting build
        // degrades gracefully to emoji instead of crashing.
        is Candidate.Symbol -> null
        is Candidate.AnotherSymbol -> null
        is Candidate.Emoji -> ReactionRasteriser.emoji(candidate.value, side)
        is Candidate.BuiltIn -> ReactionRasteriser.anotherReaction(side, tintColor, candidate.badge)
    }

    private fun id(slot: Slot): String = when (slot) {
        is Slot.Reaction -> slot.reaction.id
        // The custom pick's id is the emoji itself — it exists in no item
        // list, so the emoji is the only stable identity it has.
        is Slot.Custom -> slot.emoji
        is Slot.Another -> ANOTHER_REACTION_ID
    }

    private fun label(slot: Slot): String = when (slot) {
        is Slot.Reaction -> slot.reaction.accessibilityLabel
        is Slot.Custom -> slot.emoji
        is Slot.Another -> slot.appearance?.accessibilityLabel ?: ANOTHER_REACTION_LABEL
    }
}
