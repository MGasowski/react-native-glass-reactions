#!/usr/bin/env node
/**
 * Fails if any Liquid Glass symbol is used outside a `#if compiler(>=6.2)`
 * block.
 *
 * This is the highest-severity failure mode in the library (spec §6.1 and the
 * risk table in §10): glass symbols come from the iOS 26 SDK, so an unguarded
 * use is a *compile failure* for every consumer on an older Xcode, not a
 * graceful degrade. It is also invisible in normal CI, where the toolchain is
 * always new enough.
 *
 * A full build on an old Xcode would be a stronger check, but React Native
 * itself pins a modern toolchain, so it is not achievable here. This verifies
 * the property that actually matters — guard placement — and runs in
 * milliseconds.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const IOS_DIR = 'ios';

/** Symbols that only exist in the iOS 26 SDK. */
const GLASS_PATTERN = /\bUIGlass\w*/;

/** Availability annotations that imply an iOS 26-only API is being touched. */
const AVAILABILITY_PATTERN = /@available\(iOS 26|#available\(iOS 26/;

const failures = [];

for (const file of readdirSync(IOS_DIR).filter((f) => f.endsWith('.swift'))) {
  const path = join(IOS_DIR, file);
  const lines = readFileSync(path, 'utf8').split('\n');

  let depth = 0;

  lines.forEach((line, index) => {
    const trimmed = line.trim();

    if (/^#if\s+compiler\s*\(\s*>=\s*6\.2\s*\)/.test(trimmed)) {
      depth += 1;
      return;
    }
    // Any other #if nested inside a guard still counts as guarded; track it so
    // its #endif does not close the outer guard early.
    if (depth > 0 && /^#if\b/.test(trimmed)) {
      depth += 1;
      return;
    }
    if (depth > 0 && /^#endif\b/.test(trimmed)) {
      depth -= 1;
      return;
    }

    if (depth > 0) return;
    if (trimmed.startsWith('//')) return;

    if (GLASS_PATTERN.test(line) || AVAILABILITY_PATTERN.test(line)) {
      failures.push(`${path}:${index + 1}: ${trimmed}`);
    }
  });

  if (depth !== 0) {
    failures.push(`${path}: unbalanced #if compiler(>=6.2) / #endif`);
  }
}

if (failures.length > 0) {
  console.error(
    'Liquid Glass API used outside a `#if compiler(>=6.2)` guard.\n' +
      'This breaks the build for every consumer on an older Xcode (spec §6.1).\n'
  );
  failures.forEach((failure) => console.error(`  ${failure}`));
  process.exit(1);
}

console.log('Glass guards OK — no iOS 26 API outside a compiler guard.');
