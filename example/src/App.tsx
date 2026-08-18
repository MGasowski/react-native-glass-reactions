import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import {
  ReactionsPickerHost,
  ReactionTrigger,
  type ReactionId,
  type ReactionItem,
} from 'react-native-glass-reactions';

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
  { id: 'laugh', emoji: '😂', accessibilityLabel: 'Laugh' },
];

const ROWS = Array.from({ length: 1000 }, (_, index) => index);

const EMOJI_BY_ID: Record<string, string> = Object.fromEntries(
  REACTIONS.map((reaction) => [reaction.id, reaction.emoji])
);

function Row({
  index,
  selected,
  onSelect,
}: {
  readonly index: number;
  readonly selected?: ReactionId;
  readonly onSelect: (index: number, id: ReactionId | null) => void;
}) {
  const handleSelect = useCallback(
    (id: ReactionId | null) => onSelect(index, id),
    [index, onSelect]
  );

  return (
    <ReactionTrigger
      items={REACTIONS}
      selected={selected}
      onSelect={handleSelect}
      style={styles.row}
    >
      <View style={styles.rowInner}>
        <Text style={styles.rowTitle}>Review #{index + 1}</Text>
        <Text style={styles.rowBody}>Long-press to score. Drag to choose.</Text>
      </View>
      {/* testID maps to accessibilityIdentifier on iOS and the label carries
          the current selection, so the on-device UI test can assert that a
          selection actually round-tripped through JS rather than just that
          the row still exists. */}
      <View
        style={styles.badge}
        accessible
        testID={`score-${index + 1}`}
        accessibilityLabel={selected ?? 'none'}
      >
        <Text style={styles.badgeText}>
          {selected ? EMOJI_BY_ID[selected] : '–'}
        </Text>
      </View>
    </ReactionTrigger>
  );
}

export default function App() {
  const [scores, setScores] = useState<Record<number, ReactionId>>({});

  const handleSelect = useCallback((index: number, id: ReactionId | null) => {
    setScores((previous) => {
      const next = { ...previous };
      if (id === null) {
        delete next[index];
      } else {
        next[index] = id;
      }
      return next;
    });
  }, []);

  return (
    <View style={styles.container}>
      {/* Required at the root. Renders nothing; installs the one recognizer. */}
      <ReactionsPickerHost />

      <FlatList
        data={ROWS}
        keyExtractor={(item) => String(item)}
        renderItem={({ item }) => (
          <Row index={item} selected={scores[item]} onSelect={handleSelect} />
        )}
        contentInsetAdjustmentBehavior="automatic"
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#101014',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 18,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#2A2A31',
  },
  rowInner: {
    flex: 1,
  },
  rowTitle: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  rowBody: {
    color: '#8E8E98',
    fontSize: 13,
    marginTop: 2,
  },
  badge: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#1E1E25',
  },
  badgeText: {
    fontSize: 16,
    color: '#8E8E98',
  },
});
