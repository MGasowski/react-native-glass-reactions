import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules';

export interface GlassReactionsProps extends HybridViewProps {
  color: string;
}
export interface GlassReactionsMethods extends HybridViewMethods {}

export type GlassReactions = HybridView<
  GlassReactionsProps,
  GlassReactionsMethods
>;
