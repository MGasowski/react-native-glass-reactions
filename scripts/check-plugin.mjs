#!/usr/bin/env node
/**
 * Verifies the Expo config plugin actually does its job.
 *
 * The plugin is the only way a managed Expo project can reach 120 fps on
 * ProMotion hardware (spec §6.2), and nothing else in this repo exercises it —
 * the example app is bare React Native, not Expo. Without this, the plugin
 * could silently stop setting the key and every Expo consumer would be capped
 * at 60 fps with no error anywhere.
 *
 * Checks the transformation and that the default export is a usable plugin.
 * It deliberately does not run a full prebuild; that belongs in an Expo example
 * app, which does not exist yet.
 */
import assert from 'node:assert/strict';

// The build is CommonJS, so an ESM `import` wraps it: the module object lands
// on `.default`, and the plugin function is `.default.default`. Resolving it
// the way Expo does — via app.plugin.js — is what actually matters, so that
// entry point is asserted separately below.
const namespace = await import('../plugin/build/index.js');
const plugin = namespace.default ?? namespace;
const { enableHighFrameRate, PRO_MOTION_KEY } = plugin;

const entry = await import('../app.plugin.js');
const withGlassReactions = entry.default;

assert.equal(
  PRO_MOTION_KEY,
  'CADisableMinimumFrameDurationOnPhone',
  'the ProMotion key name changed — consumers would silently cap at 60 fps'
);

// Sets the key on an empty plist.
{
  const plist = {};
  const result = enableHighFrameRate(plist);
  assert.equal(result[PRO_MOTION_KEY], true, 'key not set');
  assert.equal(result, plist, 'must mutate and return the same object');
}

// Leaves unrelated keys alone.
{
  const plist = { CFBundleName: 'Example', UILaunchStoryboardName: 'Launch' };
  enableHighFrameRate(plist);
  assert.equal(plist.CFBundleName, 'Example', 'clobbered an unrelated key');
  assert.equal(plist.UILaunchStoryboardName, 'Launch');
  assert.equal(plist[PRO_MOTION_KEY], true);
}

// Overwrites an explicit opt-out rather than leaving 120 fps unreachable.
{
  const plist = { [PRO_MOTION_KEY]: false };
  enableHighFrameRate(plist);
  assert.equal(plist[PRO_MOTION_KEY], true, 'did not override a false value');
}

// The default export is callable as a config plugin and returns a config.
{
  assert.equal(typeof withGlassReactions, 'function', 'default export missing');
  const config = { name: 'test', slug: 'test' };
  const result = withGlassReactions(config);
  assert.ok(result, 'plugin returned nothing');
  assert.equal(result.name, 'test', 'plugin dropped existing config');
  assert.ok(
    Array.isArray(result.mods?.ios?.infoPlist) ||
      typeof result.mods?.ios?.infoPlist === 'function',
    'plugin did not register an ios infoPlist mod'
  );
}

console.log('Config plugin OK — ProMotion key set, config preserved.');
