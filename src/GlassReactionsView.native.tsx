import { getHostComponent } from 'react-native-nitro-modules';
const GlassReactionsConfig = require('../nitrogen/generated/shared/json/GlassReactionsConfig.json');
import type {
  GlassReactionsMethods,
  GlassReactionsProps,
} from './GlassReactions.nitro';

export const GlassReactionsView = getHostComponent<
  GlassReactionsProps,
  GlassReactionsMethods
>('GlassReactions', () => GlassReactionsConfig);
