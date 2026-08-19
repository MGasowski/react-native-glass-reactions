#!/usr/bin/env node
/**
 * Runs the config plugin through Expo's *real* mod pipeline.
 *
 * `check-plugin.mjs` proves the transformation and the entry point in
 * isolation. This proves the piece neither of those covers: that the plugin
 * composes correctly inside Expo's mod system and that the key survives all the
 * way to a resolved Info.plist.
 *
 * Uses `compileModsAsync` in introspection mode, which is the same machinery
 * behind `expo config --type introspect`. That exercises the pipeline without
 * needing a prebuilt native project, so it can run in CI with no Xcode and no
 * second example app.
 *
 * It is still not a full `expo prebuild` against a real project — that needs an
 * Expo example app, which does not exist yet.
 */
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { compileModsAsync } = require('@expo/config-plugins');

const entry = await import('../app.plugin.js');
const withGlassReactions = entry.default;

const PRO_MOTION_KEY = 'CADisableMinimumFrameDurationOnPhone';

const baseConfig = {
  name: 'PrebuildFixture',
  slug: 'prebuild-fixture',
  platforms: ['ios'],
  ios: {
    bundleIdentifier: 'com.example.prebuildfixture',
    // A key the plugin must not disturb.
    infoPlist: { CFBundleDisplayName: 'Prebuild Fixture' },
  },
};

const withPlugin = withGlassReactions(baseConfig);

const compiled = await compileModsAsync(withPlugin, {
  projectRoot: process.cwd(),
  platforms: ['ios'],
  introspect: true,
  assertMissingModProviders: false,
});

const plist = compiled.ios?.infoPlist ?? {};

assert.equal(
  plist[PRO_MOTION_KEY],
  true,
  `${PRO_MOTION_KEY} missing from the compiled Info.plist — managed Expo apps ` +
    `would be capped at 60 fps. Got: ${JSON.stringify(plist)}`
);

assert.equal(
  plist.CFBundleDisplayName,
  'Prebuild Fixture',
  'the plugin clobbered an unrelated Info.plist key set by the app config'
);

console.log(
  'Config plugin OK through Expo mod pipeline — ' +
    `${PRO_MOTION_KEY}=true, existing keys preserved.`
);
