package com.margelo.nitro.glassreactions

import android.app.Activity
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
import com.facebook.react.bridge.LifecycleEventListener
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
    var selectedId: String?,
    /**
     * Per-trigger override for the "another reaction" plus item; null inherits
     * the host-wide setting.
     */
    var anotherReaction: Boolean?,
    /** The custom emoji previously picked through "another reaction", if any. */
    var anotherSelected: String?,
    /**
     * Per-trigger appearance for the "another reaction" item; null inherits the
     * host-wide one. Replaces it outright rather than merging into it.
     */
    var anotherAppearance: NativeAnotherReaction?
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
    private var onSelectAnother: ((String, String) -> Unit)? = null
    private var onOpen: ((String) -> Unit)? = null
    private var onClose: ((String) -> Unit)? = null

    private var renderMode = ReactionRenderMode.AUTO
    private var longPressMs = 200L
    private var anotherReactionEnabled = true

    /**
     * Host-wide appearance for the "another reaction" item; null keeps the
     * built-in chrome.
     */
    private var anotherReactionAppearance: NativeAnotherReaction? = null

    /** Owns the emoji-picker dialog opened by the trailing plus item. */
    private val emojiSheet = AnotherReactionSheet()

    /** Pooled, not rebuilt — detached between interactions (spec §6.5). */
    private var picker: ReactionsPillView? = null
    private var overlay: FrameLayout? = null

    private var originalCallback: Window.Callback? = null
    private var lifecycleListener: LifecycleEventListener? = null
    private var wrappedActivity: Activity? = null

    // Active interaction

    /**
     * The rules of the press currently in flight, or null when none is. Every
     * question about focus and release goes here; the host only reacts to the
     * answers. Null is the whole of "no interaction" — there is no separate
     * focused index that can outlive it.
     */
    private var interaction: PickerInteraction? = null
    private var pendingTrigger: Pair<String, View>? = null
    private var downX = 0f
    private var downY = 0f
    private var touchSlop = 0

    /** Tolerance around the picker before the selection is cleared. */
    private var focusTolerancePx = 0

    /** Gap between the top of the trigger and the bottom of the picker. */
    private var verticalGapPx = 0

    /** How close the picker may sit to the edge of the screen. */
    private var edgeMarginPx = 0

    private val openRunnable = Runnable { openPicker() }

    override val isLiquidGlassSupported: Boolean
        // Android has no Liquid Glass at all (spec §4.5).
        get() = false

    override fun activate(
        renderMode: ReactionRenderMode,
        longPressDurationMs: Double,
        anotherReactionEnabled: Boolean,
        anotherReactionAppearance: NativeAnotherReaction?
    ) {
        this.renderMode = renderMode
        this.longPressMs = longPressDurationMs.toLong()
        this.anotherReactionEnabled = anotherReactionEnabled
        this.anotherReactionAppearance = anotherReactionAppearance
        main.post { install() }
    }

    override fun deactivate() {
        main.post {
            main.removeCallbacks(openRunnable)
            emojiSheet.dismiss()
            cancelInteraction()
            wrappedActivity?.window?.callback = originalCallback
            originalCallback = null
            wrappedActivity = null
            lifecycleListener?.let {
                NitroModules.applicationContext?.removeLifecycleEventListener(it)
            }
            lifecycleListener = null
            overlay?.let { (it.parent as? ViewGroup)?.removeView(it) }
            overlay = null
            picker = null
        }
    }

    override fun syncTrigger(
        triggerId: String,
        viewTag: Double,
        payload: NativeTriggerPayload
    ) {
        val tag = viewTag.toInt()
        main.post {
            // A trigger's tag cannot change without a remount, which
            // unregisters first — but the tag index is the only thing that
            // would silently rot if it ever did, so the stale entry goes rather
            // than being assumed absent.
            registrations[triggerId]?.let {
                if (it.viewTag != tag) triggerIdByTag.remove(it.viewTag)
            }

            registrations[triggerId] = TriggerRegistration(
                viewTag = tag,
                items = payload.items,
                selectedId = payload.selectedId,
                anotherReaction = payload.anotherReaction,
                anotherSelected = payload.anotherSelected,
                anotherAppearance = payload.anotherReactionAppearance
            )
            triggerIdByTag[tag] = triggerId
        }
    }

    override fun unregisterTrigger(triggerId: String) {
        main.post {
            registrations.remove(triggerId)?.let { triggerIdByTag.remove(it.viewTag) }
            // A row recycled or scrolled away mid-interaction dismisses without
            // selection rather than leaving the picker anchored to nothing.
            if (interaction?.triggerId == triggerId) cancelInteraction()
        }
    }

    override fun setOnSelect(callback: (String, String?) -> Unit) {
        onSelect = callback
    }

    override fun setOnSelectAnother(callback: (String, String) -> Unit) {
        onSelectAnother = callback
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
    /**
     * Installs on the next host resume if there is no Activity yet.
     *
     * `activate` runs when the JS host mounts, which is not ordered against the
     * Activity being current: on a cold start, and reliably after a bundle
     * reload, `currentActivity` is still null when the posted `install` runs.
     * The old code returned there and nothing retried, so the window callback
     * was never wrapped and no long-press could ever open the picker for the
     * rest of the process. It failed silently — no crash, no log, just a
     * picker that never appeared.
     *
     * Registered once and left in place: `install` is idempotent, and a resume
     * is also the moment a *new* Activity would need wrapping.
     */
    private fun installOnNextResume() {
        if (lifecycleListener != null) return
        val context = NitroModules.applicationContext ?: return
        val listener = object : LifecycleEventListener {
            override fun onHostResume() = install()
            override fun onHostPause() = Unit
            override fun onHostDestroy() = Unit
        }
        lifecycleListener = listener
        context.addLifecycleEventListener(listener)
    }

    private fun install() {
        if (originalCallback != null) return
        val activity = currentActivity()
        if (activity == null) {
            installOnNextResume()
            return
        }
        val window = activity.window
        if (window == null) {
            installOnNextResume()
            return
        }

        touchSlop = ViewConfiguration.get(activity).scaledTouchSlop
        focusTolerancePx = (12 * activity.resources.displayMetrics.density).toInt()
        // Distinct from `focusTolerancePx`, even though both happened to read
        // 12 before this: one is how far a finger may stray and still count
        // as pointing at a slot, the other is how close the picker may sit to
        // the screen edge. `verticalGapPx` used to be the same value as
        // `edgeMarginPx` too — a single `margin` doing both jobs — which put
        // the pill 4dp further from the trigger on Android than iOS's
        // matching 8pt/12pt split. See PickerLayout.
        verticalGapPx = (8 * activity.resources.displayMetrics.density).toInt()
        edgeMarginPx = (12 * activity.resources.displayMetrics.density).toInt()
        originalCallback = window.callback
        wrappedActivity = activity
        window.callback = TouchInterceptor(window.callback, ::handleTouch)

        // Warmed once, off the critical path.
        if (picker == null) picker = ReactionsPillView(activity)
    }

    private fun ensureOverlay(activity: Activity): FrameLayout? {
        overlay?.let { return it }
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return null
        content.clipChildren = false
        content.clipToPadding = false
        val layer = FrameLayout(activity).apply {
            // Presentation surface only — touches keep flowing to the app, which
            // is where the single interception point is.
            isEnabled = false
            isClickable = false
            // The focused reaction scales past the picker's bounds, so neither
            // the overlay nor its padding may clip it. clipChildren on the
            // picker alone is not enough — the parent clips too.
            clipChildren = false
            clipToPadding = false
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
                if (interaction != null) {
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
                if (interaction != null) end() else pendingTrigger = null
            }

            MotionEvent.ACTION_CANCEL -> {
                main.removeCallbacks(openRunnable)
                pendingTrigger = null
                if (interaction != null) cancelInteraction()
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

        val slots = slotsFor(registration)

        // Ownership of the touch is now unambiguous: stop ancestors (the list)
        // from intercepting so opening never scrolls (spec §6.4).
        triggerView.parent?.requestDisallowInterceptTouchEvent(true)

        // The pill matches the surface it floats over, not the system theme.
        // Set before apply: the dashed-emoji glyph rasterises in this appearance.
        pill.setSurfaceAppearance(
            SurfaceAppearance.isDark(triggerView, currentActivity()?.window?.decorView)
        )
        // Drawn from the very list that will be hit-tested, in the same order,
        // so the row on screen and the row the rules reason about cannot
        // disagree.
        pill.apply(slots, registration.selectedId, renderMode)

        val unspecified = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        pill.measure(unspecified, unspecified)

        val width = pill.measuredWidth
        val height = pill.measuredHeight

        val location = IntArray(2)
        triggerView.getLocationOnScreen(location)
        val overlayLocation = IntArray(2)
        layer.getLocationOnScreen(overlayLocation)

        val metrics = activity.resources.displayMetrics
        // The overlay reports width/height 0 until it has been through a
        // layout pass, which it has not on the first open. Clamping against
        // that pins the picker to the left margin and — worse — puts the hit
        // rectangle somewhere the finger never goes, so nothing is ever
        // selected.
        val availableWidth = if (layer.width > 0) layer.width else metrics.widthPixels
        val availableHeight = if (layer.height > 0) layer.height else metrics.heightPixels

        // PickerLayout works in the overlay's own local space, so the trigger
        // is translated into it here — the one platform-specific step: iOS's
        // overlay is a full-screen UIWindow, so window space and overlay
        // space already coincide and no such translation exists there.
        val triggerLocal = PickerFrame(
            left = (location[0] - overlayLocation[0]).toFloat(),
            top = (location[1] - overlayLocation[1]).toFloat(),
            right = (location[0] - overlayLocation[0] + triggerView.width).toFloat(),
            bottom = (location[1] - overlayLocation[1] + triggerView.height).toFloat()
        )
        val localFrame = PickerLayout.frame(
            trigger = triggerLocal,
            pillSize = Size(width.toFloat(), height.toFloat()),
            containerSize = Size(availableWidth.toFloat(), availableHeight.toFloat()),
            verticalGap = verticalGapPx.toFloat(),
            edgeMargin = edgeMarginPx.toFloat()
        )
        val left = localFrame.left.toInt()
        val top = localFrame.top.toInt()

        // Explicit LayoutParams rather than a manual layout() call: FrameLayout
        // re-lays its children out on its own pass, and without params the
        // picker defaults to MATCH_PARENT and is stretched to fill the screen.
        val params = FrameLayout.LayoutParams(width, height).apply {
            leftMargin = left
            topMargin = top
        }
        pill.prepareForPresentation()
        if (pill.parent == null) layer.addView(pill, params) else pill.layoutParams = params
        pill.animateIn()

        // Everything the rules need, frozen at this instant — selectedId
        // included. The user is choosing against the pill just drawn, so that
        // is what the deselect comparison has to be made against; re-reading
        // the registry at release time would compare against something never
        // shown.
        //
        // PickerInteraction hit-tests against raw touch coordinates
        // (screen-absolute), unlike PickerLayout's overlay-local input, so
        // the overlay's screen offset is added back here.
        val screenLeft = localFrame.left + overlayLocation[0]
        val screenTop = localFrame.top + overlayLocation[1]
        interaction = PickerInteraction(
            triggerId = triggerId,
            slots = slots,
            selectedId = registration.selectedId,
            pickerFrame = PickerFrame(
                left = screenLeft,
                top = screenTop,
                right = screenLeft + width,
                bottom = screenTop + height
            ),
            tolerance = focusTolerancePx.toFloat(),
            geometry = pill
        )

        // No initial focus: the finger is still on the row that was pressed,
        // not on a reaction.
        pill.setFocusedIndex(null)
        pendingTrigger = null
        onOpen?.invoke(triggerId)
    }

    // MARK: Mapping

    /** The registration flattened into the one list the interaction reasons over. */
    private fun slotsFor(registration: TriggerRegistration): List<Slot> {
        val slots = registration.items.map {
            Slot.Reaction(
                Reaction(
                    id = it.id,
                    emoji = it.emoji,
                    symbolIos = it.symbolIos,
                    symbolAndroid = it.symbolAndroid,
                    symbolColor = it.symbolColor,
                    accessibilityLabel = it.accessibilityLabel
                )
            )
        }.toMutableList<Slot>()

        if (registration.anotherReaction ?: anotherReactionEnabled) {
            // The custom pick rides with the plus: both belong to the "another
            // reaction" section, so disabling the feature hides both.
            registration.anotherSelected?.takeIf { it.isNotEmpty() }?.let {
                slots.add(Slot.Custom(it))
            }
            slots.add(
                Slot.Another(
                    appearance(registration.anotherAppearance ?: anotherReactionAppearance)
                )
            )
        }
        return slots
    }

    /**
     * Maps the Nitro transport struct onto the interaction's own type. The
     * generated struct stops here and goes no further in.
     */
    private fun appearance(native: NativeAnotherReaction?): AnotherReactionAppearance? =
        native?.let {
            AnotherReactionAppearance(
                symbolIos = it.symbolIos,
                symbolAndroid = it.symbolAndroid,
                symbolColor = it.symbolColor,
                emoji = it.emoji,
                badge = it.badge,
                accessibilityLabel = it.accessibilityLabel
            )
        }

    // MARK: Focus and release

    private fun updateFocus(x: Float, y: Float) {
        when (val change = interaction?.focus(x, y) ?: return) {
            is FocusChange.Unchanged -> Unit
            is FocusChange.Moved -> {
                picker?.setFocusedIndex(change.to)
                // Same code path as the visual change, so they land together.
                picker?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            }

            is FocusChange.Cleared -> picker?.setFocusedIndex(null)
        }
    }

    private fun end() {
        val current = interaction ?: return
        val triggerId = current.triggerId
        val outcome = current.release()

        when (outcome) {
            is Outcome.Select -> onSelect?.invoke(triggerId, outcome.reactionId)
            is Outcome.Deselect -> onSelect?.invoke(triggerId, null)
            // Releasing on the plus is not a selection: the celebration still
            // plays, but the interaction hands over to the emoji picker below.
            is Outcome.Another, is Outcome.Cancel -> Unit
        }

        finish(outcome.celebratedIndex)

        if (outcome is Outcome.Another) {
            currentActivity()?.let { activity ->
                emojiSheet.present(activity) { emoji ->
                    onSelectAnother?.invoke(triggerId, emoji)
                }
            }
        }
    }

    /**
     * A press that never released: the gesture was cancelled, the row was
     * recycled out from under it, or the host was deactivated. There is no
     * outcome because there was no release — the interaction is simply dropped.
     */
    private fun cancelInteraction() {
        if (interaction == null) return
        finish(null)
    }

    private fun finish(celebratedIndex: Int?) {
        val triggerId = interaction?.triggerId ?: return
        interaction = null

        val pill = picker
        // Teardown is bound to animation-end, not touch-up: onSelect has fired
        // above, and detaching now would cut the collapse off (spec §4.3).
        // Detached, not deallocated: detaching is what removes the per-frame
        // cost; deallocating would only re-buy construction (spec §6.5).
        val teardown: () -> Unit = { (pill?.parent as? ViewGroup)?.removeView(pill) }

        if (celebratedIndex != null && pill != null) {
            // A firmer confirm than the per-item tick.
            pill.performHapticFeedback(
                if (android.os.Build.VERSION.SDK_INT >= 30)
                    HapticFeedbackConstants.CONFIRM
                else
                    HapticFeedbackConstants.KEYBOARD_TAP
            )

            pill.animateSelection(celebratedIndex, teardown)
        } else {
            pill?.setFocusedIndex(null)
            pill?.animateOut(teardown)
        }

        onClose?.invoke(triggerId)
    }
}

/**
 * The slot the celebration plays on. It plays whether the release committed a
 * new selection, cleared the existing one, or opened the emoji picker — either
 * way the user chose that slot. `Cancel` chose nothing, and the sealed type is
 * what makes "celebrate at no index" unrepresentable.
 */
private val Outcome.celebratedIndex: Int?
    get() = when (this) {
        is Outcome.Select -> at
        is Outcome.Deselect -> at
        is Outcome.Another -> at
        is Outcome.Cancel -> null
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
