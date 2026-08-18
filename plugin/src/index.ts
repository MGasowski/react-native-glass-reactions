import { withInfoPlist, type ConfigPlugin } from '@expo/config-plugins';

/**
 * Expo config plugin for react-native-glass-reactions.
 *
 * This is not a convenience wrapper. iOS caps animation at 60 fps on ProMotion
 * iPhones unless `CADisableMinimumFrameDurationOnPhone` is set in Info.plist,
 * which makes the 120 fps target in spec §2 unreachable without it. Managed
 * Expo projects have no Info.plist to edit by hand, so the plugin is the only
 * way they can get there (spec §6.2).
 *
 * The library still requires a development build — it does not run in Expo Go.
 */
const withGlassReactions: ConfigPlugin = (config) =>
  withInfoPlist(config, (modConfig) => {
    modConfig.modResults.CADisableMinimumFrameDurationOnPhone = true;
    return modConfig;
  });

export default withGlassReactions;
