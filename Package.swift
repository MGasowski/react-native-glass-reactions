// swift-tools-version:5.9
import PackageDescription

/// Exists so the interaction policy and reaction resolution can be tested
/// without CocoaPods, an Xcode project, or a simulator — `swift test` and
/// nothing else.
///
/// It compiles the same files the podspec's `ios/**/*.swift` glob picks up, so
/// there is one source of truth rather than a copy. It also works as a purity
/// guard in the spirit of `scripts/check-glass-guards.mjs`: every file listed
/// here must build for macOS, so an `import UIKit` or a reference to a
/// Nitro-generated type fails here immediately. Any new pure module belongs in
/// this list.
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
      sources: ["PickerInteraction.swift", "ReactionResolution.swift"]
    ),
    .testTarget(
      name: "PickerInteractionTests",
      dependencies: ["PickerInteraction"]
    ),
  ]
)
