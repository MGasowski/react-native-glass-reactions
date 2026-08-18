import UIKit

// MARK: - Metrics

private enum Metrics {
  static let itemSize: CGFloat = 40
  static let itemSpacing: CGFloat = 8
  static let contentInset: CGFloat = 8

  /// Reactions are rasterised at the largest size they will ever be displayed
  /// at and scaled *down* from there. Apple Color Emoji is a bitmap font whose
  /// largest strike is ~160px, so scaling a small raster up under the user's
  /// finger visibly softens it. See spec §6.5.
  static let maxFocusScale: CGFloat = 1.6

  /// How far the focused reaction rises, in its own (pre-scale) coordinates.
  static let focusLift: CGFloat = 6

  static var rasterSize: CGFloat { itemSize * maxFocusScale }
}

// MARK: - Glass availability

enum GlassSupport {
  /// Liquid Glass requires the iOS 26 SDK at build time *and* the API actually
  /// being present at runtime — some iOS 26 builds shipped without it and
  /// crashed on use. Both guards are required. See spec §6.1.
  static let isAvailable: Bool = {
    #if compiler(>=6.2)
      if #available(iOS 26.0, *) {
        return NSClassFromString("UIGlassEffect") != nil
      }
    #endif
    return false
  }()

  /// Glass is suppressed when the user has asked for reduced transparency
  /// (spec §6.3). Read at build time rather than cached, since it can change
  /// while the app is running.
  static var shouldUseGlass: Bool {
    isAvailable && !UIAccessibility.isReduceTransparencyEnabled
  }
}

// MARK: - Renderable

/// A reaction resolved down to what actually gets drawn. Resolution happens
/// once per prop change; layout and drawing never re-resolve.
struct Renderable {
  let id: String
  let image: UIImage?
  let isSymbol: Bool
  let accessibilityLabel: String
}

// MARK: - View

final class ReactionsPillView: UIView {

  private var renderables: [Renderable] = []
  private var imageViews: [UIImageView] = []

  /// The capsule behind the reactions — a glass container on iOS 26, a blur
  /// view below that, an opaque view under Reduce Transparency.
  private var backdrop: UIView!

  /// Container the reactions are added to — the effect view's `contentView`
  /// on the glass and blur paths, the backdrop itself when opaque.
  private var contentHost: UIView!

  private var usingGlass = false

  // MARK: Init

  override init(frame: CGRect) {
    super.init(frame: frame)
    buildBackdrop()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    buildBackdrop()
  }

  private func buildBackdrop() {
    backdrop?.removeFromSuperview()
    usingGlass = GlassSupport.shouldUseGlass

    #if compiler(>=6.2)
      if usingGlass, #available(iOS 26.0, *) {
        // One capsule behind the whole row, not a pill per reaction. The
        // per-item glass of spec §4.4 is superseded by the single-container
        // design decision recorded there.
        let capsule = UIVisualEffectView(effect: UIGlassEffect())
        addSubview(capsule)
        backdrop = capsule
        contentHost = capsule.contentView
        return
      }
    #endif

    if UIAccessibility.isReduceTransparencyEnabled {
      let solid = UIView()
      solid.backgroundColor = .secondarySystemBackground
      addSubview(solid)
      backdrop = solid
      contentHost = solid
    } else {
      let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
      addSubview(blur)
      backdrop = blur
      contentHost = blur.contentView
    }
  }

  // MARK: Content

  func apply(items: [Renderable], selectedId: String?) {
    renderables = items
    rebuildItemViews()
    applySelection(selectedId)
    setNeedsLayout()
  }

  private func rebuildItemViews() {
    for view in imageViews { view.removeFromSuperview() }
    imageViews.removeAll()

    for renderable in renderables {
      let imageView = UIImageView()
      imageView.contentMode = .scaleAspectFit
      // Rasterised at max size and scaled down, never up (spec §6.5).
      imageView.layer.minificationFilter = .trilinear
      imageView.image = renderable.image
      if renderable.isSymbol {
        imageView.tintColor = .label
      }

      imageView.isAccessibilityElement = true
      imageView.accessibilityLabel = renderable.accessibilityLabel
      imageView.accessibilityTraits = .button

      contentHost.addSubview(imageView)
      imageViews.append(imageView)
    }
  }

  // MARK: Animation

  /// Reduce Motion replaces every spring with a plain fade (spec §6.3). Read
  /// live rather than cached — it can be toggled while the app runs.
  private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

  private func spring(
    duration: TimeInterval,
    damping: CGFloat,
    _ animations: @escaping () -> Void
  ) -> UIViewPropertyAnimator {
    let timing = UISpringTimingParameters(dampingRatio: damping)
    let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
    animator.addAnimations(animations)
    return animator
  }

  /// Collapsed state, set before the picker is attached.
  func prepareForPresentation() {
    // Grows from the bottom edge, which is the side nearest the trigger, so the
    // expansion reads as coming out of the row rather than appearing over it.
    layer.anchorPoint = CGPoint(x: 0.5, y: 1)
    alpha = 0

    guard !reduceMotion else {
      transform = .identity
      imageViews.forEach { $0.alpha = 1; $0.transform = .identity }
      return
    }

    transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
    for imageView in imageViews {
      imageView.alpha = 0
      imageView.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
    }
  }

  func animateIn() {
    guard !reduceMotion else {
      UIView.animate(withDuration: 0.15) { self.alpha = 1 }
      return
    }

    spring(duration: 0.42, damping: 0.72) {
      self.alpha = 1
      self.transform = .identity
    }.startAnimation()

    // Reactions arrive in sequence rather than all at once. The stagger is
    // small enough that the whole row is settled well inside the time it takes
    // to move a finger to it.
    for (position, imageView) in imageViews.enumerated() {
      let animator = spring(duration: 0.38, damping: 0.62) {
        imageView.alpha = 1
        imageView.transform = .identity
      }
      animator.startAnimation(afterDelay: Double(position) * 0.025)
    }
  }

  func animateOut(completion: @escaping () -> Void) {
    let animator = spring(duration: 0.22, damping: 1) {
      self.alpha = 0
      if !self.reduceMotion {
        self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
      }
    }
    animator.addCompletion { _ in completion() }
    animator.startAnimation()
  }

  /// Highlights the reaction under the finger.
  func setFocusedIndex(_ index: Int?) {
    for (position, imageView) in imageViews.enumerated() {
      let focused = position == index
      let target =
        focused
        ? CGAffineTransform(scaleX: Metrics.maxFocusScale, y: Metrics.maxFocusScale)
          .translatedBy(x: 0, y: -Metrics.focusLift)
        : .identity

      guard !reduceMotion else {
        imageView.transform = target
        continue
      }
      // Transform only — animating the item's frame would re-evaluate the
      // glass effect behind it every frame (spec §6.5).
      spring(duration: 0.3, damping: 0.58) {
        imageView.transform = target
      }.startAnimation()
    }
  }

  private func applySelection(_ selectedId: String?) {
    // Symbols are monochrome and carry no colour of their own, so selection is
    // expressed as a tint. Emoji bring their own colour and are left alone.
    // See spec §5.
    for (index, renderable) in renderables.enumerated() where renderable.isSymbol {
      guard index < imageViews.count else { continue }
      imageViews[index].tintColor =
        renderable.id == selectedId ? .tintColor : .label
    }
  }

  // MARK: Layout

  override var intrinsicContentSize: CGSize {
    let count = CGFloat(renderables.count)
    guard count > 0 else { return .zero }
    let width =
      count * Metrics.itemSize
      + max(0, count - 1) * Metrics.itemSpacing
      + Metrics.contentInset * 2
    return CGSize(width: width, height: Metrics.itemSize + Metrics.contentInset * 2)
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    backdrop.frame = bounds
    // Capsule via corner radius rather than a mask layer — masking a blurred
    // layer forces an offscreen render pass (spec §6.3).
    backdrop.layer.cornerRadius = bounds.height / 2
    backdrop.layer.cornerCurve = .continuous
    if !usingGlass {
      backdrop.clipsToBounds = true
    }

    var x = Metrics.contentInset
    let y = (bounds.height - Metrics.itemSize) / 2

    for imageView in imageViews {
      imageView.frame = CGRect(
        x: x, y: y, width: Metrics.itemSize, height: Metrics.itemSize
      )
      x += Metrics.itemSize + Metrics.itemSpacing
    }
  }

  // MARK: Trait changes

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    // Reduce Transparency can be toggled while the app runs; rebuild if the
    // effective backdrop kind would now differ.
    if usingGlass != GlassSupport.shouldUseGlass {
      buildBackdrop()
      rebuildItemViews()
      setNeedsLayout()
    }
  }
}

// MARK: - Rasterisation

private enum ReactionRasteriser {

  /// Emoji are drawn once into an image and reused. Laying out text on every
  /// open is avoidable work on the critical path (spec §6.5).
  static func emoji(_ value: String) -> UIImage? {
    guard !value.isEmpty else { return nil }

    let side = Metrics.rasterSize
    let pointSize = side * 0.82

    // Rasterised by snapshotting a UILabel so drawing goes through exactly the
    // path UIKit uses on screen — colour glyph handling and vertical centring
    // come for free rather than being reimplemented with CoreText metrics.
    // One-off per item: no text layout happens on open (spec §6.5).
    let label = UILabel()
    label.text = value
    label.font = UIFont.systemFont(ofSize: pointSize)
    label.textAlignment = .center
    label.backgroundColor = .clear
    label.frame = CGRect(x: 0, y: 0, width: side, height: side)

    let format = UIGraphicsImageRendererFormat.preferred()
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: side, height: side),
      format: format
    )
    return renderer.image { context in
      label.layer.render(in: context.cgContext)
    }
  }

  static func symbol(_ name: String) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(
      pointSize: Metrics.rasterSize * 0.62,
      weight: .semibold
    )
    return UIImage(systemName: name, withConfiguration: configuration)
  }
}

// MARK: - Resolution

/// Turns items into drawables once, applying the fallback chain from spec §5:
/// prefer a symbol under `auto` when one is supplied and actually resolves,
/// otherwise emoji — which is required on every item, so this never yields
/// nothing to draw. Shared by the standalone view and the host.
enum ReactionResolver {
  static func resolve(
    _ items: [NativeReactionItem],
    renderMode: ReactionRenderMode
  ) -> [Renderable] {
    items.map { item in
      var image: UIImage?
      var isSymbol = false

      if renderMode == .auto, let name = item.symbolIos, !name.isEmpty {
        image = ReactionRasteriser.symbol(name)
        isSymbol = image != nil
      }

      if image == nil {
        image = ReactionRasteriser.emoji(item.emoji)
        isSymbol = false
      }

      return Renderable(
        id: item.id,
        image: image,
        isSymbol: isSymbol,
        accessibilityLabel: item.accessibilityLabel
      )
    }
  }
}
