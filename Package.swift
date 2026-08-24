// swift-tools-version:5.9
import PackageDescription

/// Exists so the interaction policy and reaction resolution can be tested
/// without CocoaPods, an Xcode project, or a simulator — `swift test` and
/// nothing else.
///
/// `sources` below is a deliberate subset of the podspec's `ios/**/*.swift`
/// glob — only the pure modules, not the UIKit adapters (`ReactionsHost.swift`,
/// `ReactionsPillView.swift`, `EmojiInput.swift`) that give them a host. Naming
/// the same files here and in the podspec is what keeps this one source of
/// truth rather than a copy: a pure module lives in `ios/` and is picked up by
/// both, instead of being duplicated into a package-only location.
///
/// Listing a file here also works as a purity guard in the spirit of
/// `scripts/check-glass-guards.mjs`: every file listed must build for macOS, so
/// an `import UIKit` or a reference to a Nitro-generated type fails here
/// immediately. That guard only covers what is listed — add a new pure module
/// to `sources` for it to apply, since the podspec's glob is not enough proof
/// that a file stayed pure.
///
/// This package is not published — `files` in package.json is an allowlist and
/// names neither `Package.swift` nor `Tests`.
let package = Package(
  name: "PickerInteraction",
  platforms: [.macOS(.v11)],
  targets: [
    .target(
      name: "PickerInteraction",
      path: "ios",
      sources: [
        "PickerInteraction.swift", "ReactionResolution.swift", "PickerLayout.swift",
        "SlotLayout.swift",
      ]
    ),
    .testTarget(
      name: "PickerInteractionTests",
      dependencies: ["PickerInteraction"]
    ),
  ]
)
