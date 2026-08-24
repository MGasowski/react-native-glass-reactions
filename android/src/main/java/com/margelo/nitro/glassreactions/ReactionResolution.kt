package com.margelo.nitro.glassreactions

// MARK: - Render mode

/**
 * Mirrors the Nitro-generated `ReactionRenderMode`, copied for the same reason
 * `Reaction` is — see there. Android's generated enum happens to be a plain
 * Kotlin enum with no JNI calls in its own right, so it would in fact be safe
 * to use directly here; a private copy is kept anyway so both platforms' pure
 * modules have the same shape, and so a future nitrogen regeneration cannot
 * change what this module depends on.
 */
sealed interface RenderMode {
    data object Auto : RenderMode
    data object Emoji : RenderMode
}

// MARK: - Candidate

/**
 * One drawable option in a resolution chain, matched 1:1 to the rasteriser
 * call it stands for.
 *
 * Four cases rather than a shared `Symbol` case: an item's own symbol and the
 * "another reaction" chrome symbol are drawn by different rasterisers — a
 * plain glyph versus a composite with a corner badge — so collapsing them
 * would describe a call that isn't the one actually made.
 */
sealed interface Candidate {
    /** An item's own SF Symbol / Material Symbol. */
    data class Symbol(val name: String) : Candidate

    /** The "another reaction" chrome symbol, with its badge. */
    data class AnotherSymbol(val name: String, val badge: Boolean) : Candidate

    data class Emoji(val value: String) : Candidate

    /** The built-in dashed-face glyph, with its badge. */
    data class BuiltIn(val badge: Boolean) : Candidate
}

// MARK: - Resolution

/**
 * Decides what a slot could be drawn as, in order — never what it looks like.
 *
 * This returns a *chain*, not one resolved choice, because whether a supplied
 * symbol name actually resolves to an image is a question only the adapter's
 * rasteriser can answer. The adapter draws the first candidate that produces
 * an image; this module decides only the order, and guarantees the order
 * always ends somewhere that cannot fail to draw.
 *
 * Mirrors `ReactionResolution` in `ios/ReactionResolution.swift` case for
 * case. When one side changes, the other should change with it.
 */
object ReactionResolution {

    /**
     * The chain for one slot.
     *
     * `symbolsSupported` is what lets one function serve both platforms: iOS
     * passes true, Android passes false in 1.x — the platform has no symbol
     * rasteriser at all yet — where every symbol candidate is skipped and the
     * chain degrades to emoji-or-built-in, the same behaviour Android's
     * rasteriser always had, now expressed as data rather than as two
     * implementations that happened to agree.
     *
     * Always ends in [Candidate.Emoji] or [Candidate.BuiltIn], neither of
     * which can fail to rasterise, so a slot can never end up with nothing to
     * draw (spec §5).
     */
    fun resolutionOrder(
        slot: Slot,
        renderMode: RenderMode,
        symbolsSupported: Boolean
    ): List<Candidate> = when (slot) {
        is Slot.Reaction -> {
            val order = mutableListOf<Candidate>()
            val name = slot.reaction.symbolAndroid
            if (renderMode is RenderMode.Auto && symbolsSupported && !name.isNullOrEmpty()) {
                order.add(Candidate.Symbol(name))
            }
            order.add(Candidate.Emoji(slot.reaction.emoji))
            order
        }

        // The custom pick is a chosen emoji, not an item — it has no symbol of
        // its own to try.
        is Slot.Custom -> listOf(Candidate.Emoji(slot.emoji))

        is Slot.Another -> {
            val badge = slot.appearance?.badge ?: true
            val order = mutableListOf<Candidate>()
            // A supplied chrome symbol is skipped under RenderMode.Emoji
            // exactly like an item's symbol would be. renderMode is
            // documented as an escape hatch for when symbol rendering
            // misbehaves; an exception here would mean the escape hatch does
            // not always escape.
            val name = slot.appearance?.symbolAndroid
            if (renderMode is RenderMode.Auto && symbolsSupported && !name.isNullOrEmpty()) {
                order.add(Candidate.AnotherSymbol(name, badge))
            }
            val emoji = slot.appearance?.emoji?.takeIf { it.isNotEmpty() }
            if (emoji != null) {
                order.add(Candidate.Emoji(emoji))
            }
            order.add(Candidate.BuiltIn(badge))
            order
        }
    }
}
