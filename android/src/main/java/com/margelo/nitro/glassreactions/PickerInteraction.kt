package com.margelo.nitro.glassreactions

// MARK: - Inputs

/**
 * A reaction as the interaction policy sees it.
 *
 * Deliberately *not* `NativeReactionItem`. On Android that type is already a
 * clean data class, so this copy buys nothing locally — it exists so both
 * platforms present the same input shape, and so regenerating with nitrogen
 * cannot silently change the policy's inputs on one platform only. Its iOS
 * counterpart is a typealias onto a C++ struct and could not be used here at
 * all.
 */
data class Reaction(
    val id: String,
    val emoji: String,
    val symbolIos: String? = null,
    val symbolAndroid: String? = null,
    /**
     * Hex colour for the symbol. Carried for parity with iOS and unused in
     * 1.x, where Android renders emoji only and so has no symbol to colour.
     */
    val symbolColor: String? = null,
    val accessibilityLabel: String
)

/**
 * Appearance of the "another reaction" item, mapped off `NativeAnotherReaction`
 * for the same reason as [Reaction]. Every field is optional: an unset field
 * keeps the built-in default.
 */
data class AnotherReactionAppearance(
    val symbolIos: String? = null,
    val symbolAndroid: String? = null,
    /** Carried for parity with iOS; unused while Android renders emoji only. */
    val symbolColor: String? = null,
    val emoji: String? = null,
    val badge: Boolean? = null,
    val accessibilityLabel: String? = null
)

/**
 * One position in the open picker.
 *
 * This is the list — there is not a second one. Hit-testing, selection
 * reporting and drawing all index into these same slots, so "the plus is the
 * slot after the reactions" is a case, not arithmetic over two arrays that
 * happen to differ in length by one.
 */
sealed interface Slot {
    /**
     * One of the consumer's registered reactions. The payload type is
     * qualified because inside this scope the bare name resolves to this class.
     */
    data class Reaction(
        val reaction: com.margelo.nitro.glassreactions.Reaction
    ) : Slot

    /**
     * The emoji previously picked through "another reaction". Its id is the
     * emoji itself — it exists in no item list, so that is its only identity.
     */
    data class Custom(val emoji: String) : Slot

    /**
     * The trailing plus. Releasing here opens the system emoji picker rather
     * than reporting a selection.
     */
    data class Another(val appearance: AnotherReactionAppearance?) : Slot
}

/**
 * How slot centres are found. The pill owns this: slots are not uniform once
 * the section separator inserts its extra width, and the pill is the layout
 * authority that already has the numbers. `ReactionsPillView` implements it.
 */
fun interface SlotGeometry {
    fun slotIndex(localX: Float): Int?
}

/**
 * Where the picker is on screen.
 *
 * A plain data class rather than `android.graphics.Rect`: the framework Rect is
 * a stub on the JVM unit-test classpath and throws when touched, which would
 * put the whole point of this module out of reach. iOS uses `CGRect`, which has
 * no such problem — the one place the two files legitimately differ.
 *
 * Bounds are half-open on the trailing edges, matching `CGRect.contains`.
 */
data class PickerFrame(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
)

// MARK: - Outputs

/**
 * What a finger move did to the focus. Three named cases rather than an `Int?`,
 * because the rule that matters — a haptic fires when focus *lands* on a slot,
 * never when it leaves one — is then a case split rather than an `if next !=
 * null` the reader has to interpret.
 */
sealed interface FocusChange {
    data object Unchanged : FocusChange
    data class Moved(val to: Int) : FocusChange
    data object Cleared : FocusChange
}

/**
 * What releasing the finger meant. The index rides along so the host never has
 * to ask what was focused after the fact — and so "celebrate at no index" is
 * unrepresentable.
 */
sealed interface Outcome {
    /** Report this id through `onSelect`. */
    data class Select(val reactionId: String, val at: Int) : Outcome

    /**
     * Report null through `onSelect` — the user picked what was already
     * selected, which clears it (spec §5).
     */
    data class Deselect(val at: Int) : Outcome

    /** Report nothing; hand over to the emoji picker. */
    data class Another(val at: Int) : Outcome

    /** Report nothing, celebrate nothing. */
    data object Cancel : Outcome
}

// MARK: - Interaction

/**
 * The rules of one long-press, from open to release.
 *
 * Everything here was previously smeared across `openPicker`, `indexAt`,
 * `updateFocus`, `end` and `dismiss` on the host, reachable only through a real
 * touch on a real device. It holds no Android framework types at all, which is
 * what lets it run as a plain JVM unit test.
 *
 * Its inputs are a frozen picture taken at gesture-begin. Nothing is re-read
 * from the registry afterwards: the user is choosing against the pill in front
 * of them, so the comparison that decides deselection has to use what that pill
 * was drawn from.
 *
 * Cancellation is not a method. A cancelled gesture, a recycled row or a
 * `deactivate` simply drops the interaction — there was no release, so there is
 * no outcome to produce.
 */
class PickerInteraction(
    val triggerId: String,
    val slots: List<Slot>,
    /**
     * What was selected when the picker opened. See the note above on why this
     * is a snapshot.
     */
    private val selectedId: String?,
    private val pickerFrame: PickerFrame,
    private val tolerance: Float,
    private val geometry: SlotGeometry
) {

    var focusedIndex: Int? = null
        private set

    /**
     * See [separatorAfter]. Exposed here so the rule has one home even though
     * the host needs it before an interaction exists.
     */
    val separatorAfter: Int?
        get() = slots.separatorAfter

    // MARK: Focus

    fun focus(x: Float, y: Float): FocusChange {
        val next = indexAt(x, y)
        if (next == focusedIndex) return FocusChange.Unchanged
        focusedIndex = next
        return next?.let { FocusChange.Moved(it) } ?: FocusChange.Cleared
    }

    /**
     * Which slot a point is pointing at, if any.
     *
     * The vertical slack is what stops the selection flickering at the edge;
     * the lack of horizontal slack is deliberate. The press that opens the
     * picker lands on the row *below* it, so generous slack here means a
     * reaction is selected before the finger has gone anywhere near one. This
     * was once 160px — roughly a centimetre — which selected reactions from far
     * below the picker.
     */
    private fun indexAt(x: Float, y: Float): Int? {
        if (slots.isEmpty()) return null
        if (x < pickerFrame.left || x >= pickerFrame.right) return null
        if (y < pickerFrame.top - tolerance) return null
        if (y >= pickerFrame.bottom + tolerance) return null
        return geometry.slotIndex(x - pickerFrame.left)
    }

    // MARK: Release

    fun release(): Outcome {
        val index = focusedIndex ?: return Outcome.Cancel
        if (index !in slots.indices) return Outcome.Cancel
        return when (val slot = slots[index]) {
            is Slot.Another -> Outcome.Another(index)
            is Slot.Reaction -> outcomeSelecting(slot.reaction.id, index)
            is Slot.Custom -> outcomeSelecting(slot.emoji, index)
        }
    }

    /**
     * Upsert with deselect: picking what is already selected clears it
     * (spec §5).
     */
    private fun outcomeSelecting(id: String, index: Int): Outcome =
        if (id == selectedId) Outcome.Deselect(index) else Outcome.Select(id, index)
}

/**
 * Index of the first slot in the "another reaction" section, or null when there
 * is no divider to draw.
 *
 * Derived from the slots rather than tracked beside them, so it cannot disagree
 * with what is on screen. Lives on the list because the host has to lay the
 * pill out — and therefore know the separator — before it has a frame to build
 * an interaction with.
 */
val List<Slot>.separatorAfter: Int?
    get() {
        val first = indexOfFirst { it !is Slot.Reaction }
        // Nothing on the left of the divider means nothing to divide.
        return if (first > 0) first else null
    }
