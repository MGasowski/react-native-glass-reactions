import { useState } from 'react';
import { Image, StyleSheet, Text, View } from 'react-native';
import {
  isLiquidGlassSupported,
  ReactionsPicker,
  type ReactionId,
  type ReactionItem,
} from 'react-native-glass-reactions';

/**
 * Every item carries an emoji — the guaranteed fallback — and optionally a
 * symbol that is preferred where it resolves. See spec §5.
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
  {
    id: 'star',
    emoji: '⭐',
    symbol: { ios: 'star.fill' },
    accessibilityLabel: 'Star',
  },
  {
    id: 'laugh',
    emoji: '😂',
    accessibilityLabel: 'Laugh',
  },
];

export default function App() {
  const [selected] = useState<ReactionId | undefined>('fire');

  return (
    <View style={styles.container}>
      {/* Glass reads off whatever is behind it, so the backdrop is the point. */}
      <Image
        source={{ uri: 'https://picsum.photos/id/1043/800/1200' }}
        style={StyleSheet.absoluteFill}
      />

      <View style={styles.stack}>
        <Text style={styles.caption}>
          renderMode: auto {'—'} symbols where they resolve
        </Text>
        <ReactionsPicker
          items={REACTIONS}
          selected={selected}
          style={styles.picker}
        />

        <Text style={styles.caption}>renderMode: emoji {'—'} forced</Text>
        <ReactionsPicker
          items={REACTIONS}
          selected={selected}
          renderMode="emoji"
          style={styles.picker}
        />

        <Text style={styles.caption}>
          liquid glass expected: {String(isLiquidGlassSupported)}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stack: {
    alignItems: 'center',
    gap: 16,
  },
  // The native view does not report an intrinsic size to Yoga yet, so M1 needs
  // an explicit frame: 5 items x 40 + 4 gaps x 8 + 8 inset x 2 = 248 x 56.
  // Sizing stops being the consumer's problem at M2, when the host presents
  // the picker natively rather than through RN layout.
  picker: {
    width: 248,
    height: 56,
  },
  caption: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
    textShadowColor: 'rgba(0,0,0,0.6)',
    textShadowRadius: 4,
  },
});
