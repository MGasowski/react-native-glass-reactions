import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import {
  ReactionsPickerHost,
  ReactionTrigger,
  type ReactionId,
  type ReactionItem,
} from 'react-native-glass-reactions';

/**
 * The capture screen: the same library, over content chosen so the glass is
 * actually visible.
 *
 * Liquid Glass refracts and tints whatever sits behind it. Over the benchmark
 * screen's #101014 there is nothing to refract, so the pill reads as a dark
 * grey capsule and looks near-identical to the opaque fallback. Saturated
 * artwork behind the pill is what separates the two, which makes this screen
 * the one worth pointing a camera at.
 *
 * Artwork is drawn from plain Views rather than bundled images: no asset to
 * license, no binary in git, and overlapping translucent circles give the pill
 * several hues to pick up across its width.
 */

/**
 * Coloured symbols: the glyphs come from SF Symbols but each carries the hue
 * its emoji would have had, so the row reads as reactions rather than as a
 * toolbar. `laugh` is left as an emoji on purpose — the two forms sit side by
 * side in the same pill.
 */
const REACTIONS: readonly ReactionItem[] = [
  {
    id: 'like',
    emoji: '👍',
    symbol: { ios: 'hand.thumbsup.fill', color: '#4C8DFF' },
    accessibilityLabel: 'Like',
  },
  {
    id: 'love',
    emoji: '❤️',
    symbol: { ios: 'heart.fill', color: '#FF6B6B' },
    accessibilityLabel: 'Love',
  },
  {
    id: 'fire',
    emoji: '🔥',
    symbol: { ios: 'flame.fill', color: '#FF6B2C' },
    accessibilityLabel: 'Fire',
  },
  {
    id: 'star',
    emoji: '⭐',
    symbol: { ios: 'star.fill', color: '#FFC53D' },
    accessibilityLabel: 'Star',
  },
  { id: 'laugh', emoji: '😂', accessibilityLabel: 'Laugh' },
];

const EMOJI_BY_ID: Record<string, string> = Object.fromEntries(
  REACTIONS.map((reaction) => [reaction.id, reaction.emoji])
);

/**
 * Each entry is a base plus two blob colours. Hues are deliberately far apart
 * within a row and between neighbours: the pill opens above its trigger and
 * overlaps the row before it, so it should span two different colour fields.
 */
const TRACKS: readonly {
  readonly title: string;
  readonly artist: string;
  readonly base: string;
  readonly blobs: readonly [string, string];
}[] = [
  {
    title: 'Neon Harbour',
    artist: 'Vela Cruz',
    base: '#FF3B6B',
    blobs: ['#FFB03B', '#7B2FF7'],
  },
  {
    title: 'Slow Transit',
    artist: 'Nine Palms',
    base: '#00C2A8',
    blobs: ['#0066FF', '#B4FF39'],
  },
  {
    title: 'Paper Cities',
    artist: 'Ivory Sound',
    base: '#7B2FF7',
    blobs: ['#FF3B6B', '#00E0FF'],
  },
  {
    title: 'Long Way Down',
    artist: 'Marisol',
    base: '#FF8A00',
    blobs: ['#FF2D95', '#FFE156'],
  },
  {
    title: 'Glasshouse',
    artist: 'Ada Kern',
    base: '#0066FF',
    blobs: ['#00E0FF', '#B14BFF'],
  },
  {
    title: 'Static Bloom',
    artist: 'Kite Parade',
    base: '#00B84D',
    blobs: ['#B4FF39', '#00C2A8'],
  },
  {
    title: 'Midnight Ferry',
    artist: 'The Lantern',
    base: '#E01E5A',
    blobs: ['#7B2FF7', '#FF8A00'],
  },
  {
    title: 'Copper Wire',
    artist: 'Sable',
    base: '#FFB03B',
    blobs: ['#FF3B6B', '#00C2A8'],
  },
];

const ROWS = Array.from({ length: 200 }, (_, index) => index);

function Artwork({ index }: { readonly index: number }) {
  const track = TRACKS[index % TRACKS.length]!;

  return (
    <View style={[styles.artwork, { backgroundColor: track.base }]}>
      <View
        style={[
          styles.blob,
          styles.blobOne,
          { backgroundColor: track.blobs[0] },
        ]}
      />
      <View
        style={[
          styles.blob,
          styles.blobTwo,
          { backgroundColor: track.blobs[1] },
        ]}
      />
      {/* A bright sliver near the top edge. Small, but it is the sort of hard
          highlight the glass bends most visibly. */}
      <View style={styles.sheen} />
    </View>
  );
}

function Row({
  index,
  selected,
  custom,
  onSelect,
  onSelectAnother,
}: {
  readonly index: number;
  readonly selected?: ReactionId;
  readonly custom?: string;
  readonly onSelect: (index: number, id: ReactionId | null) => void;
  readonly onSelectAnother: (index: number, emoji: string) => void;
}) {
  const track = TRACKS[index % TRACKS.length]!;

  const handleSelect = useCallback(
    (id: ReactionId | null) => onSelect(index, id),
    [index, onSelect]
  );

  const handleSelectAnother = useCallback(
    (emoji: string) => onSelectAnother(index, emoji),
    [index, onSelectAnother]
  );

  return (
    <ReactionTrigger
      items={REACTIONS}
      selected={selected}
      onSelect={handleSelect}
      onSelectAnother={handleSelectAnother}
      anotherSelected={custom}
      style={styles.row}
      testID={`card-${index}`}
    >
      <View style={styles.card}>
        <Artwork index={index} />
        {/* Overlaid rather than in a strip beneath the cover. The pill opens
            just above its trigger, which lands it on the *bottom* of the card
            above — a white caption there gave the glass nothing but white to
            refract, which is the whole thing this screen exists to show. */}
        <View style={styles.caption}>
          <View style={styles.scrim} />
          <View style={styles.captionText}>
            <Text style={styles.rowTitle}>{track.title}</Text>
            <Text style={styles.rowBody}>{track.artist}</Text>
          </View>
          <View
            style={styles.badge}
            accessible
            testID={`badge-${index}`}
            accessibilityLabel={selected ? String(selected) : 'none'}
          >
            <Text style={styles.badgeText}>
              {selected ? (EMOJI_BY_ID[selected] ?? selected) : ''}
            </Text>
          </View>
        </View>
      </View>
    </ReactionTrigger>
  );
}

export default function DemoApp() {
  const [scores, setScores] = useState<Record<number, ReactionId>>({});
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
    // Light on purpose. Liquid Glass earns its keep by bending bright, varied
    // content; a dark ground gives it almost nothing to work with and the
    // result is hard to tell from the opaque fallback.
    backgroundColor: '#F4F4F7',
  },
  row: {
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  card: {
    backgroundColor: '#FFFFFF',
    borderRadius: 22,
    overflow: 'hidden',
    shadowColor: '#3A3A4A',
    shadowOpacity: 0.1,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 5 },
  },
  // A wide cover rather than a thumbnail: the pill opens above its trigger and
  // spans most of the width, so the colour needs to span most of the width too.
  artwork: {
    height: 210,
    overflow: 'hidden',
  },
  blob: {
    position: 'absolute',
    borderRadius: 999,
    opacity: 0.9,
  },
  blobOne: {
    width: 300,
    height: 300,
    top: -130,
    left: -70,
  },
  blobTwo: {
    width: 240,
    height: 240,
    bottom: -120,
    right: -50,
    opacity: 0.8,
  },
  sheen: {
    position: 'absolute',
    top: 34,
    left: -60,
    width: 460,
    height: 26,
    borderRadius: 999,
    backgroundColor: '#FFFFFF',
    opacity: 0.32,
    transform: [{ rotate: '-16deg' }],
  },
  caption: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  // Keeps the title readable over a light cover without hiding the colour.
  scrim: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    backgroundColor: '#000000',
    opacity: 0.22,
  },
  captionText: {
    flex: 1,
  },
  rowTitle: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '600',
  },
  rowBody: {
    color: '#F0F0F5',
    fontSize: 14,
    marginTop: 2,
  },
  badge: {
    width: 34,
    height: 34,
    alignItems: 'center',
    justifyContent: 'center',
  },
  badgeText: {
    fontSize: 24,
  },
});
