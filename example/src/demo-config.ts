/**
 * Which screen the example renders.
 *
 * `bench` is the default and must stay the default: it is the screen the
 * Maestro flow and the XCUITest suite drive, and the one arm of the §6.5
 * scale-gate A/B. Its row text ("Review #N") and `score-N` testIDs are
 * assertion targets, so it is not free to restyle.
 *
 * The other two exist for capture and for answering a question the benchmark
 * screen cannot answer, and nothing automated depends on them.
 *
 * - `demo`    colourful content to record marketing GIFs against. Liquid Glass
 *             refracts what is behind it, so the near-black benchmark list is
 *             the worst possible backdrop for showing the effect off: glass and
 *             the opaque fallback are almost indistinguishable there.
 * - `opacity` a probe for the claim in README's platform-traps section, that
 *             setting `opacity: 0` on "a glass view or any ancestor" disables
 *             the effect. See OpacityProbe.tsx for what is actually in doubt.
 */
export type DemoScreen = 'bench' | 'demo' | 'opacity';

export const SCREEN: DemoScreen = 'bench';
