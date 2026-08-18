import type { ViewProps } from 'react-native';
import type {
  NativeReactionItem,
  ReactionRenderMode,
} from './glass-reactions.nitro';

type Props = ViewProps & {
  items: NativeReactionItem[];
  renderMode: ReactionRenderMode;
  selectedId?: string;
};

/**
 * Web stub. There is no web support (spec §3); this exists so bundlers that
 * resolve the package on web fail with a readable message rather than a
 * missing-native-module error. Its props mirror the native host component so
 * type resolution is identical on both sides.
 */
export function NativeGlassReactionsView(_props: Props): never {
  throw new Error(
    "'react-native-glass-reactions' is only supported on native platforms."
  );
}
