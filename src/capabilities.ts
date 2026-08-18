import { host } from './host';

/**
 * Whether Liquid Glass will actually render on this device.
 *
 * Backed by the native check, which is the authoritative one: it requires the
 * iOS 26 SDK at build time *and* the API being present at runtime, since some
 * iOS 26 builds shipped without it (spec §6.1). Always false on Android.
 *
 * Note this reports device capability, not what the picker is doing right now —
 * Reduce Transparency suppresses glass at presentation time without changing
 * this value (spec §6.3).
 */
export const isLiquidGlassSupported: boolean = host.isLiquidGlassSupported;
