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

    fun apply(items: List<Renderable>, selectedId: String?) {
        renderables = items

        // Drop every child except the backdrop, then rebuild.
        while (childCount > 1) removeViewAt(1)

        items.forEach { renderable ->
            val imageView = ImageView(context).apply {
                setImageBitmap(renderable.bitmap)
                scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = renderable.accessibilityLabel
                alpha = if (selectedId != null && renderable.id != selectedId) 0.55f else 1f
            }
            addView(imageView)
        }

        requestLayout()
        invalidate()
    }

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

    private fun spring(
        view: View,
        property: DynamicAnimation.ViewProperty,
        target: Float,
        stiffness: Float = SpringForce.STIFFNESS_MEDIUM,
        damping: Float = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY
    ) {
        SpringAnimation(view, property).apply {
            this.spring = SpringForce(target)
                .setStiffness(stiffness)
                .setDampingRatio(damping)
        }.start()
    }

    /** Collapsed state, set before the picker is attached. */
    fun prepareForPresentation() {
        alpha = 0f
        if (reduceMotion) {
            scaleX = 1f
            scaleY = 1f
            for (position in 1 until childCount) {
                getChildAt(position).apply { alpha = 1f; scaleX = 1f; scaleY = 1f }
            }
            return
        }
        // Grows from the bottom edge, the side nearest the trigger.
        pivotY = (itemSize + contentInset * 2).toFloat()
        scaleX = 0.86f
        scaleY = 0.86f
        for (position in 1 until childCount) {
            getChildAt(position).apply { alpha = 0f; scaleX = 0.4f; scaleY = 0.4f }
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
                .alpha(1f)
                .setStartDelay((position - 1) * 25L)
                .setDuration(140)
                .withEndAction {
                    spring(child, SpringAnimation.SCALE_X, 1f)
                    spring(child, SpringAnimation.SCALE_Y, 1f)
                }
                .start()
        }
    }

    fun animateOut(completion: () -> Unit) {
        animate()
            .alpha(0f)
            .scaleX(if (reduceMotion) 1f else 0.92f)
            .scaleY(if (reduceMotion) 1f else 0.92f)
            .setDuration(180)
            .withEndAction {
                alpha = 1f
                scaleX = 1f
                scaleY = 1f
                completion()
            }
            .start()
    }

    /** Highlights the reaction under the finger. */
    fun setFocusedIndex(index: Int?) {
        for (position in 1 until childCount) {
            val child = getChildAt(position)
            val focused = position - 1 == index
            val scale = if (focused) Metrics.MAX_FOCUS_SCALE else 1f
            val lift = if (focused) -dp(Metrics.FOCUS_LIFT_DP).toFloat() else 0f

            if (reduceMotion) {
                child.scaleX = scale
                child.scaleY = scale
                child.translationY = lift
                continue
            }
            // Scale and translation only — no layout pass per frame.
            spring(child, SpringAnimation.SCALE_X, scale)
            spring(child, SpringAnimation.SCALE_Y, scale)
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
