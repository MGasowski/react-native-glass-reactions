import { withInfoPlist, type ConfigPlugin } from '@expo/config-plugins';

/**
 * The key iOS needs before it will run animations above 60 fps on ProMotion
 * hardware. Without it the display is capped at 60 Hz regardless of what the
 * animation asks for, which puts the 120 fps target in spec §2 out of reach.
 */
export const PRO_MOTION_KEY = 'CADisableMinimumFrameDurationOnPhone';

/**
 * The whole transformation, separated from the Expo mod wrapper so it can be
 * tested without running a prebuild. Mutates and returns the same object,
 * matching what `withInfoPlist` expects of a mod.
 */
export function enableHighFrameRate<T extends object>(infoPlist: T): T {
  // Cast rather than constrain: Expo types the plist as
  // Record<string, JSONValue | undefined>, and a generic parameter cannot be
  // indexed for writing. The cast keeps the caller's exact type on the way out.
  (infoPlist as Record<string, unknown>)[PRO_MOTION_KEY] = true;
  return infoPlist;
}

/**
 * Expo config plugin for react-native-glass-reactions.
 *
 * This is not a convenience wrapper. Managed Expo projects have no Info.plist
 * to edit by hand, so without the plugin they cannot reach 120 fps at all
 * (spec §6.2).
 *
 * The library still requires a development build — it does not run in Expo Go.
 */
const withGlassReactions: ConfigPlugin = (config) =>
  withInfoPlist(config, (modConfig) => {
    modConfig.modResults = enableHighFrameRate(modConfig.modResults);
    return modConfig;
  });

export default withGlassReactions;
