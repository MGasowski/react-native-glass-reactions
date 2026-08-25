import { useCallback, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import {
  ReactionsPickerHost,
  ReactionTrigger,
  type ReactionId,
  type ReactionItem,
} from 'react-native-glass-reactions';

/**
 * A probe, not a demo.
 *
 * README's platform-traps section tells consumers: "Never fade the picker with
 * `opacity` from JavaScript. Setting `opacity: 0` on a glass view **or any
 * ancestor** disables the effect outright." Read as consumer advice that
 * implies fading a View in your own tree can kill the pill's glass.
 *
 * Two things in the source argue it cannot mean that:
 *
 *  1. ReactionsHost presents the pill into its own UIWindow at `.alert + 1`
 *     (ReactionsHost.swift, ensureOverlayWindow). The pill is therefore not a
 *     descendant of any View the consumer renders, and UIKit alpha does not
 *     propagate between sibling windows.
 *  2. ReactionsPillView's own comment (around the `alpha = 1` in the open
 *     path) describes the failure as the glass rendering "as a translucent
 *     grey snapshot **until the fade completes**" — a transient artefact while
 *     an alpha animation runs, not a permanent disabling.
 *
 * So the trap is most likely a note about the library's *internal* animation
 * choices that got written up as if it were a consumer-facing rule. This
 * screen settles it by observation rather than by reading.
 *
 * Method: long-press the card at each opacity and compare the pill against the
 * 1.0 case. The label under the card records what to look for.
 */

const REACTIONS: readonly ReactionItem[] = [
  {
    id: 'like',
    emoji: '👍',
    symbol: { ios: 'hand.thumbsup.fill' },
    accessibilityLabel: 'Like',
  },
  {
    id: 'love',
    emoji: '❤️',
    symbol: { ios: 'heart.fill' },
    accessibilityLabel: 'Love',
  },
  {
    id: 'fire',
    emoji: '🔥',
    symbol: { ios: 'flame.fill' },
    accessibilityLabel: 'Fire',
  },
];

/** 0.99 is the interesting one: enough to force a separate compositing pass,
 *  small enough that the card itself still looks opaque on camera. If the
 *  offscreen-buffer theory were right, 0.99 would break the glass as
 *  thoroughly as 0 does. */
const STEPS = [1, 0.99, 0.5, 0.05] as const;

export default function OpacityProbe() {
  const [opacity, setOpacity] = useState<number>(1);
  const [hostFaded, setHostFaded] = useState(false);
  const [selected, setSelected] = useState<ReactionId | undefined>();

  const handleSelect = useCallback(
    (id: ReactionId | null) => setSelected(id ?? undefined),
    []
  );

  return (
    <View style={styles.container}>
      {/* The host is wrapped so the second question can be asked too: does
          fading the *host's* ancestor reach the overlay window either? */}
      <View style={{ opacity: hostFaded ? 0.05 : 1 }}>
        <ReactionsPickerHost />
      </View>

      <Text style={styles.heading}>Ancestor opacity probe</Text>
      <Text style={styles.sub}>
        Long-press the card at each value. If glass survives, the README trap is
        about the library's own views, not yours.
      </Text>

      <View style={styles.steps}>
        {STEPS.map((step) => (
          <Pressable
            key={step}
            onPress={() => setOpacity(step)}
            style={[styles.step, opacity === step && styles.stepOn]}
          >
            <Text
              style={[styles.stepText, opacity === step && styles.stepTextOn]}
            >
              {step}
            </Text>
          </Pressable>
        ))}
      </View>

      <Pressable
        onPress={() => setHostFaded((value) => !value)}
        style={[styles.hostToggle, hostFaded && styles.hostToggleOn]}
      >
        <Text style={styles.stepText}>
          host ancestor opacity: {hostFaded ? '0.05' : '1'}
        </Text>
      </Pressable>

      {/* The subject. Three nested Views so the faded ancestor is genuinely an
          ancestor and not the trigger itself. */}
      <View style={{ opacity }}>
        <View style={styles.pad}>
          <View style={styles.pad}>
            <ReactionTrigger
              items={REACTIONS}
              selected={selected}
              onSelect={handleSelect}
              style={styles.card}
            >
              <View style={styles.swatchRow}>
                <View style={[styles.swatch, { backgroundColor: '#FF3B6B' }]} />
                <View style={[styles.swatch, { backgroundColor: '#FFB03B' }]} />
                <View style={[styles.swatch, { backgroundColor: '#00C2A8' }]} />
                <View style={[styles.swatch, { backgroundColor: '#7B2FF7' }]} />
              </View>
              <Text style={styles.cardText}>
                long-press me (ancestor opacity {opacity})
              </Text>
            </ReactionTrigger>
          </View>
        </View>
      </View>

      <Text style={styles.reading}>picked: {selected ?? 'none'}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0B0B0F',
    paddingTop: 90,
    paddingHorizontal: 20,
  },
  heading: {
    color: '#FFFFFF',
    fontSize: 22,
    fontWeight: '700',
  },
  sub: {
    color: '#9A9AA8',
    fontSize: 13,
    marginTop: 6,
    lineHeight: 18,
  },
  steps: {
    flexDirection: 'row',
    marginTop: 22,
    gap: 8,
  },
  step: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: '#1E1E25',
  },
  stepOn: {
    backgroundColor: '#0066FF',
  },
  stepText: {
    color: '#CFCFDA',
    fontSize: 15,
    fontWeight: '600',
  },
  stepTextOn: {
    color: '#FFFFFF',
  },
  hostToggle: {
    marginTop: 10,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: '#1E1E25',
    alignSelf: 'flex-start',
  },
  hostToggleOn: {
    backgroundColor: '#B14BFF',
  },
  pad: {
    padding: 6,
  },
  card: {
    marginTop: 30,
    borderRadius: 20,
    padding: 18,
    backgroundColor: '#15151C',
  },
  swatchRow: {
    flexDirection: 'row',
    gap: 8,
  },
  swatch: {
    flex: 1,
    height: 54,
    borderRadius: 12,
  },
  cardText: {
    color: '#CFCFDA',
    fontSize: 14,
    marginTop: 14,
  },
  reading: {
    color: '#6E6E7C',
    fontSize: 13,
    marginTop: 26,
  },
});
