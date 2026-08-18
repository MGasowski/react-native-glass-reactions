/**
 * Build-time switch for the §6.5 scale-gate A/B.
 *
 * A build-time constant rather than a runtime toggle on purpose: driving a
 * toggle from XCUITest proved unreliable (React Native merges an accessible
 * Pressable's subtree, and the state change did not surface), and more
 * importantly a flag means both arms run the *same* test through the *same*
 * code path. The only difference between the two builds is whether rows are
 * wrapped in a ReactionTrigger.
 *
 * The control build flips this to false; `yarn ab:control` / `yarn ab:restore`
 * do it mechanically.
 */
export const TRIGGERS_ENABLED = true;
