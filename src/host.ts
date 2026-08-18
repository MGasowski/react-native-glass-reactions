import { NitroModules } from 'react-native-nitro-modules';
import type { ReactionsHost } from './reactions-host.nitro';

/**
 * The single native host. Resolved once at module scope: the guarantee that
 * only one picker can exist is enforced here, natively, rather than by where
 * consumers place a component (spec §5).
 */
export const host =
  NitroModules.createHybridObject<ReactionsHost>('ReactionsHost');
