package com.margelo.nitro.glassreactions

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import com.facebook.proguard.annotations.DoNotStrip
import com.facebook.react.uimanager.ThemedReactContext
import kotlin.math.max

/**
 * Android has no Liquid Glass. The defined fallback is a translucent surface
 * with a RenderEffect blur on API 31+, and a flat translucent surface below
 * that. See spec §4.5.
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
}

/** A reaction resolved to what actually gets drawn. */
private data class Renderable(
    val id: String,
    val bitmap: Bitmap?,
    val accessibilityLabel: String
)

private class ReactionsPillView(context: ThemedReactContext) : ViewGroup(context) {

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

    private fun applyBackdrop() {
        backdrop.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(Color.argb(0x2E, 0x80, 0x80, 0x80))
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            backdrop.setRenderEffect(
                RenderEffect.createBlurEffect(24f, 24f, Shader.TileMode.CLAMP)
            )
        }
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

@DoNotStrip
class HybridGlassReactions(val context: ThemedReactContext) : HybridGlassReactionsSpec() {

    private val pillView = ReactionsPillView(context)

    override val view: View = pillView

    private var _items: Array<NativeReactionItem> = emptyArray()
    override var items: Array<NativeReactionItem>
        get() = _items
        set(value) {
            _items = value
            resolve()
        }

    private var _renderMode: ReactionRenderMode = ReactionRenderMode.AUTO
    override var renderMode: ReactionRenderMode
        get() = _renderMode
        set(value) {
            _renderMode = value
            resolve()
        }

    private var _selectedId: String? = null
    override var selectedId: String?
        get() = _selectedId
        set(value) {
            _selectedId = value
            resolve()
        }

    /**
     * Android renders emoji only in 1.0. `symbolAndroid` names a Material
     * Symbol, which requires shipping the Material Symbols font in the AAR —
     * deferred rather than dropped. Because `emoji` is required on every item
     * (spec §5), falling back costs nothing and never blanks the picker.
     */
    private fun resolve() {
        val renderables = _items.map { item ->
            Renderable(
                id = item.id,
                bitmap = pillView.rasteriseEmoji(item.emoji),
                accessibilityLabel = item.accessibilityLabel
            )
        }
        pillView.apply(renderables, _selectedId)
    }
}
