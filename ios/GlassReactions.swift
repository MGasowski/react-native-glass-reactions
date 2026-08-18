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
  private var itemViews: [UIView] = []
  private var imageViews: [UIImageView] = []

  /// The capsule behind the reactions — a glass container on iOS 26, a blur
  /// view below that, an opaque view under Reduce Transparency.
  private var backdrop: UIView!

  /// Container that per-item content is added to. On the glass path this is
  /// the container effect view's `contentView` so pills participate in the
  /// glass union; otherwise it is the backdrop itself.
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
        let container = UIVisualEffectView(effect: UIGlassContainerEffect())
        addSubview(container)
        backdrop = container
        contentHost = container.contentView
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
    for view in itemViews { view.removeFromSuperview() }
    itemViews.removeAll()
    imageViews.removeAll()

    for renderable in renderables {
      let host: UIView

      #if compiler(>=6.2)
        if usingGlass, #available(iOS 26.0, *) {
          // Individual glass pills inside the container merge and separate as
          // the container's spacing threshold is crossed — this is the
          // structure M3 animates, not a decoration.
          host = UIVisualEffectView(effect: UIGlassEffect())
        } else {
          host = UIView()
        }
      #else
        host = UIView()
      #endif

      let imageView = UIImageView()
      imageView.contentMode = .scaleAspectFit
      // Rasterised at max size and scaled down, never up (spec §6.5).
      imageView.layer.minificationFilter = .trilinear
      imageView.image = renderable.image
      if renderable.isSymbol {
        imageView.tintColor = .label
      }

      let contentTarget = (host as? UIVisualEffectView)?.contentView ?? host
      contentTarget.addSubview(imageView)

      host.isAccessibilityElement = true
      host.accessibilityLabel = renderable.accessibilityLabel
      host.accessibilityTraits = .button

      contentHost.addSubview(host)
      itemViews.append(host)
      imageViews.append(imageView)
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

    for host in itemViews {
      host.frame = CGRect(x: x, y: y, width: Metrics.itemSize, height: Metrics.itemSize)
      host.layer.cornerRadius = Metrics.itemSize / 2
      host.layer.cornerCurve = .continuous

      let contentTarget = (host as? UIVisualEffectView)?.contentView ?? host
      for sub in contentTarget.subviews {
        sub.frame = contentTarget.bounds
      }

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

// MARK: - Hybrid

class HybridGlassReactions: HybridGlassReactionsSpec {

  var view: UIView = ReactionsPillView()

  private var pillView: ReactionsPillView { view as! ReactionsPillView }

  var items: [NativeReactionItem] = [] {
    didSet { resolve() }
  }

  var renderMode: ReactionRenderMode = .auto {
    didSet { resolve() }
  }

  var selectedId: String? {
    didSet { resolve() }
  }

  /// Resolves each item down to a drawable once, applying the fallback chain
  /// from spec §5: prefer a symbol under `auto` when one is supplied and
  /// actually resolves, otherwise emoji — which is always present.
  private func resolve() {
    let renderables: [Renderable] = items.map { item in
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

    pillView.apply(items: renderables, selectedId: selectedId)
  }
}
