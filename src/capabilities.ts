import { Platform } from 'react-native';

/**
 * Whether Liquid Glass is expected to render on this device.
 *
 * NOTE (M1): this mirrors the OS-version half of the native gate but not the
 * runtime API-presence check in `GlassSupport.isAvailable` (spec §6.1), and it
 * does not account for Reduce Transparency. The native side is authoritative
 * and degrades on its own; treat this as a hint for consumer-side copy, not as
 * a guarantee. It will be backed by the native check before 1.0.
 */
export const isLiquidGlassSupported: boolean =
  Platform.OS === 'ios' && Number.parseInt(String(Platform.Version), 10) >= 26;
