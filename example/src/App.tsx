import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { TRIGGERS_ENABLED } from './ab-config';
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
  custom,
  onSelect,
  onSelectAnother,
  triggersEnabled,
}: {
  readonly index: number;
  readonly selected?: ReactionId;
  readonly custom?: string;
  readonly onSelect: (index: number, id: ReactionId | null) => void;
  readonly onSelectAnother: (index: number, emoji: string) => void;
  readonly triggersEnabled: boolean;
}) {
  const handleSelect = useCallback(
    (id: ReactionId | null) => onSelect(index, id),
    [index, onSelect]
  );

  // The example scores by emoji when the pick comes from the native emoji
  // picker; a real app would likely create a reaction record instead.
  const handleSelectAnother = useCallback(
    (emoji: string) => onSelectAnother(index, emoji),
    [index, onSelectAnother]
  );

  const content = (
    <>
      <View style={styles.rowInner}>
        <Text style={styles.rowTitle}>Review #{index + 1}</Text>
        <Text style={styles.rowBody}>Long-press to score. Drag to choose.</Text>
      </View>
      <View
        style={styles.badge}
        accessible
        testID={`score-${index + 1}`}
        accessibilityLabel={selected ?? 'none'}
      >
        <Text style={styles.badgeText}>
          {/* Custom picks from "another reaction" arrive as the emoji itself,
              so an id with no entry in the map is displayed as-is. */}
          {selected ? (EMOJI_BY_ID[selected] ?? selected) : '–'}
        </Text>
      </View>
    </>
  );

  // The A/B for the §6.5 scale gate: the same list, same row content, with the
  // triggers removed. Anything that shows up in both is the list's cost, not
  // the library's.
  if (!triggersEnabled) {
    return <View style={styles.row}>{content}</View>;
  }

  return (
    <ReactionTrigger
      items={REACTIONS}
      selected={selected}
      onSelect={handleSelect}
      onSelectAnother={handleSelectAnother}
      anotherSelected={custom}
      style={styles.row}
    >
      {content}
    </ReactionTrigger>
  );
}

export default function App() {
  const [scores, setScores] = useState<Record<number, ReactionId>>({});
  // The last custom emoji picked per row: shown in the picker after the
  // separator, replaced by the next pick (max one).
  const [customs, setCustoms] = useState<Record<number, string>>({});

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

  const handleSelectAnother = useCallback(
    (index: number, emoji: string) => {
      setCustoms((previous) => ({ ...previous, [index]: emoji }));
      handleSelect(index, emoji);
    },
    [handleSelect]
  );

  return (
    <View style={styles.container}>
      {/* Required at the root. Renders nothing; installs the one recognizer. */}
      <ReactionsPickerHost />

      <FlatList
        data={ROWS}
        keyExtractor={(item) => String(item)}
        renderItem={({ item }) => (
          <Row
            index={item}
            selected={scores[item]}
            custom={customs[item]}
            onSelect={handleSelect}
            onSelectAnother={handleSelectAnother}
            triggersEnabled={TRIGGERS_ENABLED}
          />
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
