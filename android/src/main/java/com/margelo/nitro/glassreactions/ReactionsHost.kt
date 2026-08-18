package com.margelo.nitro.glassreactions

import android.app.Activity
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewConfiguration
import android.view.Window
import android.widget.FrameLayout
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import kotlin.math.abs

/**
 * What the host knows about one registered trigger. No frame is stored: frames
 * go stale as soon as a list scrolls, so the live view is resolved at
 * gesture-begin instead (spec §6.5).
 */
private data class TriggerRegistration(
    val viewTag: Int,
    var items: Array<NativeReactionItem>,
    var selectedId: String?
) {
    override fun equals(other: Any?) = this === other
    override fun hashCode() = viewTag
}

@DoNotStrip
class HybridReactionsHost : HybridReactionsHostSpec() {

    private val main = Handler(Looper.getMainLooper())

    private val registrations = HashMap<String, TriggerRegistration>()
    private val triggerIdByTag = HashMap<Int, String>()

    private var onSelect: ((String, String?) -> Unit)? = null
    private var onOpen: ((String) -> Unit)? = null
    private var onClose: ((String) -> Unit)? = null

    private var renderMode = ReactionRenderMode.AUTO
    private var longPressMs = 200L

    /** Pooled, not rebuilt — detached between interactions (spec §6.5). */
    private var picker: ReactionsPillView? = null
    private var overlay: FrameLayout? = null

    private var originalCallback: Window.Callback? = null
    private var wrappedActivity: Activity? = null

    // Active interaction
    private var activeTriggerId: String? = null
    private var activeItems: Array<NativeReactionItem> = emptyArray()
    private var activeRect = Rect()
    private var focusedIndex: Int? = null
    private var pendingTrigger: Pair<String, View>? = null
    private var downX = 0f
    private var downY = 0f
    private var touchSlop = 0

    private val openRunnable = Runnable { openPicker() }

    override val isLiquidGlassSupported: Boolean
        // Android has no Liquid Glass at all (spec §4.5).
        get() = false

    override fun activate(renderMode: ReactionRenderMode, longPressDurationMs: Double) {
        this.renderMode = renderMode
        this.longPressMs = longPressDurationMs.toLong()
        main.post { install() }
    }

    override fun deactivate() {
        main.post {
            main.removeCallbacks(openRunnable)
            dismiss(null, cancelled = true)
            wrappedActivity?.window?.callback = originalCallback
            originalCallback = null
            wrappedActivity = null
            overlay?.let { (it.parent as? ViewGroup)?.removeView(it) }
            overlay = null
            picker = null
        }
    }

    override fun registerTrigger(
        triggerId: String,
        viewTag: Double,
        items: Array<NativeReactionItem>,
        selectedId: String?
    ) {
        val tag = viewTag.toInt()
        main.post {
            registrations[triggerId] = TriggerRegistration(tag, items, selectedId)
            triggerIdByTag[tag] = triggerId
        }
    }

    override fun updateTrigger(
        triggerId: String,
        items: Array<NativeReactionItem>,
        selectedId: String?
    ) {
        main.post {
            registrations[triggerId]?.let {
                it.items = items
                it.selectedId = selectedId
            }
        }
    }

    override fun unregisterTrigger(triggerId: String) {
        main.post {
            registrations.remove(triggerId)?.let { triggerIdByTag.remove(it.viewTag) }
            // A row recycled or scrolled away mid-interaction dismisses without
            // selection rather than leaving the picker anchored to nothing.
            if (activeTriggerId == triggerId) dismiss(null, cancelled = true)
        }
    }

    override fun setOnSelect(callback: (String, String?) -> Unit) {
        onSelect = callback
    }

    override fun setOnOpen(callback: (String) -> Unit) {
        onOpen = callback
    }

    override fun setOnClose(callback: (String) -> Unit) {
        onClose = callback
    }

    // MARK: Install

    private fun currentActivity(): Activity? =
        NitroModules.applicationContext?.currentActivity

    /**
     * Android has no global gesture recognizer, so the equivalent of installing
     * one recognizer on the window is wrapping the window callback and watching
     * `dispatchTouchEvent`. One interception point for the whole app; nothing
     * per row (spec §6.5).
     */
    private fun install() {
        if (originalCallback != null) return
        val activity = currentActivity() ?: return
        val window = activity.window ?: return

        touchSlop = ViewConfiguration.get(activity).scaledTouchSlop
        originalCallback = window.callback
        wrappedActivity = activity
        window.callback = TouchInterceptor(window.callback, ::handleTouch)

        // Warmed once, off the critical path.
        if (picker == null) picker = ReactionsPillView(activity)
    }

    private fun ensureOverlay(activity: Activity): FrameLayout? {
        overlay?.let { return it }
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return null
        val layer = FrameLayout(activity).apply {
            // Presentation surface only — touches keep flowing to the app, which
            // is where the single interception point is.
            isEnabled = false
            isClickable = false
        }
        content.addView(
            layer,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        overlay = layer
        return layer
    }

    // MARK: Touch handling

    private fun handleTouch(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX
                downY = event.rawY
                val activity = currentActivity() ?: return
                val root = activity.window?.decorView ?: return
                pendingTrigger = findTrigger(root, event.rawX.toInt(), event.rawY.toInt())
                if (pendingTrigger != null) {
                    main.postDelayed(openRunnable, longPressMs)
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (activeTriggerId != null) {
                    updateFocus(event.rawX, event.rawY)
                } else if (
                    abs(event.rawX - downX) > touchSlop ||
                    abs(event.rawY - downY) > touchSlop
                ) {
                    // Moved before the threshold: this is a scroll, not a press.
                    main.removeCallbacks(openRunnable)
                    pendingTrigger = null
                }
            }

            MotionEvent.ACTION_UP -> {
                main.removeCallbacks(openRunnable)
                if (activeTriggerId != null) end() else pendingTrigger = null
            }

            MotionEvent.ACTION_CANCEL -> {
                main.removeCallbacks(openRunnable)
                pendingTrigger = null
                if (activeTriggerId != null) dismiss(null, cancelled = true)
            }
        }
    }

    /**
     * Finds the innermost registered trigger under the point.
     *
     * Deliberately not "deepest view, then walk up": React Native renders a
     * full-screen DebuggingOverlay above all content in dev builds, so a naive
     * topmost-first hit test always lands there and never reaches the list.
     * Searching *for a trigger* during the descent means a subtree that
     * contains none simply falls through to the next sibling, which is correct
     * regardless of what overlays happen to be present.
     */
    private fun findTrigger(view: View, x: Int, y: Int): Pair<String, View>? {
        if (view.visibility != View.VISIBLE) return null
        if (!containsPoint(view, x, y)) return null

        if (view is ViewGroup) {
            for (index in view.childCount - 1 downTo 0) {
                findTrigger(view.getChildAt(index), x, y)?.let { return it }
            }
        }

        val triggerId = triggerIdByTag[view.id]
        if (triggerId != null && registrations.containsKey(triggerId)) {
            return triggerId to view
        }
        return null
    }

    private fun containsPoint(view: View, x: Int, y: Int): Boolean {
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        return x >= location[0] && x <= location[0] + view.width &&
            y >= location[1] && y <= location[1] + view.height
    }

    private fun openPicker() {
        val (triggerId, triggerView) = pendingTrigger ?: return
        val registration = registrations[triggerId] ?: return
        if (registration.items.isEmpty()) return
        val activity = currentActivity() ?: return
        val layer = ensureOverlay(activity) ?: return
        val pill = picker ?: return

        activeTriggerId = triggerId
        activeItems = registration.items

        // Ownership of the touch is now unambiguous: stop ancestors (the list)
        // from intercepting so opening never scrolls (spec §6.4).
        triggerView.parent?.requestDisallowInterceptTouchEvent(true)

        pill.applyItems(registration.items, registration.selectedId, renderMode)
        pill.measure(0, 0)

        val size = pill.measuredWidth to pill.measuredHeight
        val location = IntArray(2)
        triggerView.getLocationOnScreen(location)
        val overlayLocation = IntArray(2)
        layer.getLocationOnScreen(overlayLocation)

        val margin = (12 * activity.resources.displayMetrics.density).toInt()
        var left = location[0] + triggerView.width / 2 - size.first / 2 - overlayLocation[0]
        val top = (location[1] - overlayLocation[1] - size.second - margin).coerceAtLeast(margin)
        left = left.coerceIn(margin, (layer.width - size.first - margin).coerceAtLeast(margin))

        if (pill.parent == null) layer.addView(pill)
        pill.layout(left, top, left + size.first, top + size.second)
        activeRect.set(
            left + overlayLocation[0],
            top + overlayLocation[1],
            left + overlayLocation[0] + size.first,
            top + overlayLocation[1] + size.second
        )

        focusedIndex = null
        pendingTrigger = null
        onOpen?.invoke(triggerId)
    }

    private fun indexAt(x: Float, y: Float): Int? {
        if (activeItems.isEmpty()) return null
        val slack = 160
        if (x < activeRect.left || x > activeRect.right) return null
        if (y < activeRect.top - slack || y > activeRect.bottom + slack) return null
        val stride = activeRect.width().toFloat() / activeItems.size
        return ((x - activeRect.left) / stride).toInt().coerceIn(0, activeItems.size - 1)
    }

    private fun updateFocus(x: Float, y: Float) {
        val next = indexAt(x, y)
        if (next == focusedIndex) return
        focusedIndex = next
        picker?.setFocusedIndex(next)
        if (next != null) {
            // Same code path as the visual change, so they land together.
            picker?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        }
    }

    private fun end() {
        val triggerId = activeTriggerId ?: return
        val current = registrations[triggerId]?.selectedId
        val index = focusedIndex

        val selection = if (index != null && index < activeItems.size) {
            val candidate = activeItems[index].id
            // Upsert with deselect (spec §5).
            if (candidate == current) null else candidate
        } else {
            null
        }
        dismiss(selection, cancelled = index == null)
    }

    private fun dismiss(selected: String?, cancelled: Boolean) {
        val triggerId = activeTriggerId ?: return

        if (!cancelled) onSelect?.invoke(triggerId, selected)

        activeTriggerId = null
        activeItems = emptyArray()
        focusedIndex = null

        val pill = picker
        pill?.setFocusedIndex(null)
        // Detached, not deallocated: detaching is what removes the per-frame
        // cost; deallocating would only re-buy construction (spec §6.5).
        pill?.let { (it.parent as? ViewGroup)?.removeView(it) }

        onClose?.invoke(triggerId)
    }
}

/**
 * Delegates every Window.Callback member to the original and sniffs touches on
 * the way through. Deliberately non-consuming: the app's own views still see
 * every event, so normal scrolling is untouched.
 */
private class TouchInterceptor(
    private val delegate: Window.Callback?,
    private val observer: (MotionEvent) -> Unit
) : Window.Callback by (delegate ?: NoopCallback()) {

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        observer(event)
        return delegate?.dispatchTouchEvent(event) ?: false
    }
}

/** Only used if an activity somehow has no callback; never expected in practice. */
private class NoopCallback : Window.Callback {
    override fun dispatchKeyEvent(event: android.view.KeyEvent?) = false
    override fun dispatchKeyShortcutEvent(event: android.view.KeyEvent?) = false
    override fun dispatchTouchEvent(event: MotionEvent?) = false
    override fun dispatchTrackballEvent(event: MotionEvent?) = false
    override fun dispatchGenericMotionEvent(event: MotionEvent?) = false
    override fun dispatchPopulateAccessibilityEvent(
        event: android.view.accessibility.AccessibilityEvent?
    ) = false

    override fun onCreatePanelView(featureId: Int): View? = null
    override fun onCreatePanelMenu(featureId: Int, menu: android.view.Menu) = false
    override fun onPreparePanel(featureId: Int, view: View?, menu: android.view.Menu) = false
    override fun onMenuOpened(featureId: Int, menu: android.view.Menu) = false
    override fun onMenuItemSelected(featureId: Int, item: android.view.MenuItem) = false
    override fun onWindowAttributesChanged(attrs: android.view.WindowManager.LayoutParams?) {}
    override fun onContentChanged() {}
    override fun onWindowFocusChanged(hasFocus: Boolean) {}
    override fun onAttachedToWindow() {}
    override fun onDetachedFromWindow() {}
    override fun onPanelClosed(featureId: Int, menu: android.view.Menu) {}
    override fun onSearchRequested() = false
    override fun onSearchRequested(searchEvent: android.view.SearchEvent?) = false
    override fun onWindowStartingActionMode(
        callback: android.view.ActionMode.Callback?
    ): android.view.ActionMode? = null

    override fun onWindowStartingActionMode(
        callback: android.view.ActionMode.Callback?,
        type: Int
    ): android.view.ActionMode? = null

    override fun onActionModeStarted(mode: android.view.ActionMode?) {}
    override fun onActionModeFinished(mode: android.view.ActionMode?) {}
}
