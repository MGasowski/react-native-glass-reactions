# Contributing

Contributions are always welcome, no matter how large or small!

We want this community to be friendly and respectful to each other. Please follow it in all your interactions with the project. Before contributing, please read the [code of conduct](./CODE_OF_CONDUCT.md).

## Development workflow

This project is a monorepo managed using [Yarn workspaces](https://yarnpkg.com/features/workspaces). It contains the following packages:

- The library package in the root directory.
- An example app in the `example/` directory.

To get started with the project, make sure you have the correct version of [Node.js](https://nodejs.org/) installed. See the [`.nvmrc`](./.nvmrc) file for the version used in this project.

Run `yarn` in the root directory to install the required dependencies for each package:

```sh
yarn
```

> Since the project relies on Yarn workspaces, you cannot use [`npm`](https://github.com/npm/cli) for development without manually migrating.

This project uses Nitro Modules. If you're not familiar with how Nitro works, make sure to check the [Nitro Modules Docs](https://nitro.margelo.com/).

You need to run [Nitrogen](https://nitro.margelo.com/docs/nitrogen) to generate the boilerplate code required for this project. The example app will not build without this step.

Run **Nitrogen** in following cases:

- When you make changes to any `*.nitro.ts` files.
- When running the project for the first time (since the generated files are not committed to the repository).

To invoke **Nitrogen**, use the following command:

```sh
yarn nitrogen
```

The [example app](/example/) demonstrates usage of the library. You need to run it to test any changes you make.

It is configured to use the local version of the library, so any changes you make to the library's source code will be reflected in the example app. Changes to the library's JavaScript code will be reflected in the example app without a rebuild, but native code changes will require a rebuild of the example app.

If you want to use Android Studio or Xcode to edit the native code, you can open the `example/android` or `example/ios` directories respectively in those editors. To edit the Objective-C or Swift files, open `example/ios/GlassReactionsExample.xcworkspace` in Xcode and find the source files at `Pods > Development Pods > react-native-glass-reactions`.

To edit the Java or Kotlin files, open `example/android` in Android studio and find the source files at `react-native-glass-reactions` under `Android`.

You can use various commands from the root directory to work with the project.

To start the packager:

```sh
yarn example start
```

To run the example app on Android:

```sh
yarn example android
```

To run the example app on iOS:

```sh
yarn example ios
```

To confirm that the app is running with the new architecture, you can check the Metro logs for a message like this:

```sh
Running "GlassReactionsExample" with {"fabric":true,"initialProps":{"concurrentRoot":true},"rootTag":1}
```

Note the `"fabric":true` and `"concurrentRoot":true` properties.

Make sure your code passes TypeScript:

```sh
yarn typecheck
```

To check for linting errors, run the following:

```sh
yarn lint
```

To fix formatting errors, run the following:

```sh
yarn lint --fix
```



### Scripts

The `package.json` file contains various scripts for common tasks:

- `yarn`: setup project by installing dependencies.
- `yarn typecheck`: type-check files with TypeScript.
  - `yarn lint`: lint files with [ESLint](https://eslint.org/).
    - `yarn example start`: start the Metro server for the example app.
- `yarn example android`: run the example app on Android.
- `yarn example ios`: run the example app on iOS.
  
### Sending a pull request

> **Working on your first pull request?** You can learn how from this _free_ series: [How to Contribute to an Open Source Project on GitHub](https://app.egghead.io/playlists/how-to-contribute-to-an-open-source-project-on-github).

When you're sending a pull request:

- Prefer small pull requests focused on one change.
- Verify that linters and tests are passing.
- Review the documentation to make sure it looks good.
- Follow the pull request template when opening a pull request.
- For pull requests that change the API or implementation, discuss with maintainers first by opening an issue.

## Regenerating the Nitro bindings

The generated bindings in `nitrogen/generated` are **committed to the repository on purpose**. Consumers must never run the code generator — that is the difference between a package that installs cleanly and a weekly stream of "build fails" issues.

Any change to a `src/*.nitro.ts` spec means regenerating and committing the result:

```sh
yarn nitrogen
```

Then sync the native projects, because Nitrogen adds and removes files the build systems need to know about:

```sh
cd example/ios && pod install
```

Gradle picks the Android side up on the next build.

Review the diff under `nitrogen/generated` before committing. If it is empty after a spec change, the generator did not pick your change up — check that the hybrid object is listed in `nitro.json` under `autolinking`, or it will generate a spec that nothing implements.

Kotlin sources live under the `com.margelo` namespace. That is required by Nitro and appears in the published Android artifact. It is accepted, not a mistake.

## Verifying a change

TypeScript tests catch very little in a native library, so the meaningful checks are the builds:

```sh
yarn typecheck
yarn lint
yarn example ios
yarn example android
```

For anything touching rendering or gestures, run the example app and use it — a green build proves almost nothing here.

### Testing emoji rendering

Some iOS simulator runtimes cannot render emoji at all: every emoji draws as a missing-glyph box through any API, including plain React Native `<Text>`. This was observed on iOS 26.3.1 and is correct on 26.5.

Before debugging emoji rendering in this library, render the same string through `<Text>` as a control. If that shows boxes too, the runtime is at fault and the native code is fine. Verify emoji on a known-good runtime or a real device, never on a single simulator.

## Native UI tests (on-device)

The core interaction cannot be covered by Maestro: `longPressOn` presses *and releases*, which ends the gesture before a reaction can be dragged to. The XCUITest suite in `example/ios/GlassReactionsExampleUITests` covers it with `press(forDuration:thenDragTo:)`, which is a single continuous press → hold → drag → release.

The example project deliberately carries **no** `DEVELOPMENT_TEAM`, so pass your own:

```sh
cd example/ios
xcodebuild test \
  -workspace GlassReactionsExample.xcworkspace \
  -scheme GlassReactionsExample \
  -configuration Release \
  -destination 'platform=iOS,id=<your-device-udid>' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<your-team-id>
```

Find the device UDID with `xcrun devicectl list devices`.

Two things that will waste your time otherwise:

- **The device must be unlocked.** XCUITest against a locked device hangs with no output rather than failing — it looks like a stuck build.
- **Use `Release`.** A Debug build serves JS from Metro and keeps dev-mode assertions live, so any timing you take from it is meaningless.

### Profiling

`testSustainedScrollForProfiling` exists to give a profiler something to attach to. Record with:

```sh
xcrun xctrace record --device <udid> --template 'Animation Hitches' \
  --attach <pid> --time-limit 60s --output hitches.trace
```

Attach by **PID**, not by process name — attaching by name fails and, unhelpfully, `xctrace` still exits 0 while producing no trace. Get the PID from `xcrun devicectl device info processes --device <udid> | grep GlassReactions`.

An empty `hitches-frame-lifetimes` table means the app rendered nothing during the window, not that it rendered perfectly.

## Verifying the Expo config plugin

The example app is bare React Native, so nothing in the normal build path
exercises the plugin. Two checks cover it, both run by `yarn lint`:

- `scripts/check-plugin.mjs` — the transformation and the `app.plugin.js` entry
  point in isolation. Guards the key name, that unrelated `Info.plist` keys
  survive, and that an explicit `false` is overridden.
- `scripts/check-plugin-prebuild.mjs` — the plugin through Expo's real mod
  pipeline via `compileModsAsync` in introspection mode, the same machinery
  behind `expo config --type introspect`. No Xcode and no native project needed.

If you change the plugin, confirm the checks still *fail* when you break it —
flip the key to `false`, run them, and expect a non-zero exit. A check that
cannot fail is worthless.

Not covered: a real `expo prebuild` against a genuine project. That needs an
Expo example app, which does not exist yet.

## Cutting a release

```sh
yarn release
```

release-it bumps the version from the conventional commits, writes `CHANGELOG.md`,
tags `v<version>` and pushes. The tag triggers the `release` job, which publishes
to npm with `--provenance`. release-it deliberately does **not** publish itself —
otherwise the release would either double-publish or publish from a laptop with
no provenance attestation.

**The first release must pin its version explicitly:**

```sh
yarn release 0.1.0
```

Left to itself release-it reads the `feat:` commits in the history and proposes
`0.2.0`, because it assumes `0.1.0` has already shipped.

Before the tag can publish anything, the `NPM_TOKEN` repository secret has to
exist. This is a one-time setup:

1. Create an npmjs.com account and **verify the email address** — npm refuses to
   publish from an unverified account.
2. On npmjs.com, create a **granular access token** with read *and write*
   permission and an expiry. For the *first* release it must be scoped to **all
   packages**: a package-scoped token can only select packages that already
   exist, and `react-native-glass-reactions` does not exist on the registry
   until the first publish creates it.
3. `gh secret set NPM_TOKEN` and paste the token.
4. **After `0.1.0` is on npm**, replace that token with one scoped to just
   `react-native-glass-reactions`, or move to trusted publishing (below) and
   delete the secret. Until then the secret can write to every package the
   account owns.

There is no step where the package gets created on npmjs.com by hand. The
registry creates it from `package.json` on the first successful publish, which
is also what claims the name.

Provenance additionally needs the workflow to run from a public repo with
`id-token: write`, which the `release` job already declares.

Do not run `npm publish` from a laptop. The release job pins the publish to a
build whose inputs are the tagged commit, which is the whole point of the
provenance attestation; a local publish silently produces an unattested tarball.

### Switching to trusted publishing

Trusted publishing (OIDC) would remove the `NPM_TOKEN` secret entirely, but npm
can only link a package that already exists — so it is not an option for the
first release. Once `0.1.0` is on npm, it is worth doing:

1. On `https://www.npmjs.com/package/react-native-glass-reactions/access`, under
   **Publishing access**, add this repository and the `CI` workflow.
2. Drop the `NODE_AUTH_TOKEN` env block and the `--provenance` flag from the
   publish step — npm generates provenance automatically for trusted publishes.
3. Delete the `NPM_TOKEN` secret.
