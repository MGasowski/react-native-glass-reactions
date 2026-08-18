import { getHostComponent } from 'react-native-nitro-modules';
import type {
  GlassReactionsMethods,
  GlassReactionsProps,
} from './glass-reactions.nitro';

const GlassReactionsConfig = require('../nitrogen/generated/shared/json/GlassReactionsConfig.json');

/**
 * Raw Nitro host component. Internal — consumers use `ReactionsPicker`, which
 * owns the mapping from the public item shape to the flattened native one.
 */
export const NativeGlassReactionsView = getHostComponent<
  GlassReactionsProps,
  GlassReactionsMethods
>('GlassReactions', () => GlassReactionsConfig);
