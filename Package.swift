// swift-tools-version:5.9
import PackageDescription

/// Exists so the interaction policy can be tested without CocoaPods, an Xcode
/// project, or a simulator — `swift test` and nothing else.
///
/// It compiles exactly one file, the same file the podspec's `ios/**/*.swift`
/// glob picks up, so there is one source of truth rather than a copy. It also
/// works as a purity guard in the spirit of `scripts/check-glass-guards.mjs`:
/// `PickerInteraction.swift` must build for macOS, so an `import UIKit` or a
/// reference to a Nitro-generated type fails here immediately.
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
      sources: ["PickerInteraction.swift"]
    ),
    .testTarget(
      name: "PickerInteractionTests",
      dependencies: ["PickerInteraction"]
    ),
  ]
)
