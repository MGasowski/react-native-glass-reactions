package com.margelo.nitro.glassreactions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

/**
 * Mirrors `Tests/PickerInteractionTests/ReactionResolutionTests.swift` case
 * for case. When one side changes, the other should change with it.
 */

private fun reaction(id: String = "a", emoji: String = "👍", symbolAndroid: String? = null) =
    Reaction(id = id, emoji = emoji, symbolAndroid = symbolAndroid, accessibilityLabel = id)

/**
 * Every chain, over every input, must end somewhere that cannot fail to draw
 * — that is the property "the slot never blanks" actually rests on.
 */
private fun assertNeverBlanks(order: List<Candidate>) {
    assertFalse("chain must never be empty", order.isEmpty())
    when (order.last()) {
        is Candidate.Emoji, is Candidate.BuiltIn -> Unit
        is Candidate.Symbol, is Candidate.AnotherSymbol ->
            fail("chain must not end on an unverified symbol")
    }
}

class ItemResolutionTest {

    @Test
    fun `auto mode prefers a supplied symbol`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Reaction(reaction(symbolAndroid = "favorite")),
            RenderMode.Auto,
            symbolsSupported = true
        )
        assertEquals(listOf(Candidate.Symbol("favorite"), Candidate.Emoji("👍")), order)
    }

    @Test
    fun `auto mode with no symbol falls straight to emoji`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Reaction(reaction()), RenderMode.Auto, symbolsSupported = true
        )
        assertEquals(listOf(Candidate.Emoji("👍")), order)
    }

    /** The kill switch: emoji mode never offers a symbol candidate. */
    @Test
    fun `emoji mode skips the symbol entirely`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Reaction(reaction(symbolAndroid = "favorite")),
            RenderMode.Emoji,
            symbolsSupported = true
        )
        assertEquals(listOf(Candidate.Emoji("👍")), order)
    }

    /** Android in 1.x: no symbol support at all, independent of render mode. */
    @Test
    fun `unsupported platform never offers a symbol`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Reaction(reaction(symbolAndroid = "favorite")),
            RenderMode.Auto,
            symbolsSupported = false
        )
        assertEquals(listOf(Candidate.Emoji("👍")), order)
    }

    @Test
    fun `empty symbol name is treated as absent`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Reaction(reaction(symbolAndroid = "")), RenderMode.Auto, symbolsSupported = true
        )
        assertEquals(listOf(Candidate.Emoji("👍")), order)
    }

    @Test
    fun `never blanks over every combination`() {
        for (symbol in listOf(null, "", "favorite")) {
            for (mode in listOf(RenderMode.Auto, RenderMode.Emoji)) {
                for (supported in listOf(true, false)) {
                    assertNeverBlanks(
                        ReactionResolution.resolutionOrder(
                            Slot.Reaction(reaction(symbolAndroid = symbol)), mode, supported
                        )
                    )
                }
            }
        }
    }
}

class CustomPickResolutionTest {

    /** The custom pick is a chosen emoji — never a symbol, in any mode. */
    @Test
    fun `is always just the emoji`() {
        for (mode in listOf(RenderMode.Auto, RenderMode.Emoji)) {
            val order = ReactionResolution.resolutionOrder(
                Slot.Custom("🎉"), mode, symbolsSupported = true
            )
            assertEquals(listOf(Candidate.Emoji("🎉")), order)
        }
    }
}

class AnotherReactionResolutionTest {

    @Test
    fun `no appearance falls straight to the built-in glyph`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Another(null), RenderMode.Auto, symbolsSupported = true
        )
        assertEquals(listOf(Candidate.BuiltIn(true)), order)
    }

    @Test
    fun `auto mode prefers a supplied symbol over a supplied emoji`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Another(AnotherReactionAppearance(symbolAndroid = "add", emoji = "➕")),
            RenderMode.Auto,
            symbolsSupported = true
        )
        assertEquals(
            listOf(Candidate.AnotherSymbol("add", true), Candidate.Emoji("➕"), Candidate.BuiltIn(true)),
            order
        )
    }

    @Test
    fun `badge default true carries through every symbol candidate`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Another(AnotherReactionAppearance(symbolAndroid = "add", badge = false)),
            RenderMode.Auto,
            symbolsSupported = true
        )
        assertEquals(
            listOf(Candidate.AnotherSymbol("add", false), Candidate.BuiltIn(false)),
            order
        )
    }

    /**
     * The behaviour this candidate exists to fix: a supplied chrome symbol
     * used to survive emoji mode whenever no override emoji was supplied,
     * bypassing the kill switch. It no longer does.
     */
    @Test
    fun `emoji mode skips a supplied symbol even with no override emoji`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Another(AnotherReactionAppearance(symbolAndroid = "add")),
            RenderMode.Emoji,
            symbolsSupported = true
        )
        assertEquals(listOf(Candidate.BuiltIn(true)), order)
    }

    @Test
    fun `emoji mode uses the override emoji when one is supplied`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Another(AnotherReactionAppearance(symbolAndroid = "add", emoji = "➕")),
            RenderMode.Emoji,
            symbolsSupported = true
        )
        assertEquals(listOf(Candidate.Emoji("➕"), Candidate.BuiltIn(true)), order)
    }

    @Test
    fun `unsupported platform skips the symbol and keeps the emoji override`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Another(AnotherReactionAppearance(symbolAndroid = "add", emoji = "➕")),
            RenderMode.Auto,
            symbolsSupported = false
        )
        assertEquals(listOf(Candidate.Emoji("➕"), Candidate.BuiltIn(true)), order)
    }

    @Test
    fun `empty override emoji is treated as absent`() {
        val order = ReactionResolution.resolutionOrder(
            Slot.Another(AnotherReactionAppearance(emoji = "")),
            RenderMode.Auto,
            symbolsSupported = true
        )
        assertEquals(listOf(Candidate.BuiltIn(true)), order)
    }

    @Test
    fun `never blanks over every combination`() {
        val symbols = listOf(null, "", "add")
        val emojis = listOf(null, "", "➕")
        for (symbol in symbols) {
            for (emoji in emojis) {
                for (badge in listOf(true, false)) {
                    for (mode in listOf(RenderMode.Auto, RenderMode.Emoji)) {
                        for (supported in listOf(true, false)) {
                            assertNeverBlanks(
                                ReactionResolution.resolutionOrder(
                                    Slot.Another(
                                        AnotherReactionAppearance(
                                            symbolAndroid = symbol, emoji = emoji, badge = badge
                                        )
                                    ),
                                    mode,
                                    supported
                                )
                            )
                        }
                    }
                }
            }
        }
    }
}
