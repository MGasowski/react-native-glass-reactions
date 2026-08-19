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

  /// Dock-style magnification: the reactions either side of the focused one
  /// partially scale and step aside, so dragging across the row reads as a
  /// wave rather than a binary highlight. Must stay below `maxFocusScale` —
  /// rasters are only ever scaled down (spec §6.5).
  static let neighborScale: CGFloat = 1.18
  static let neighborLift: CGFloat = 2
  static let neighborShift: CGFloat = 5

  /// How far the chosen reaction overshoots past the focus scale when picked,
  /// before it flies down to the trigger. Capped by the raster headroom the
  /// same way `neighborScale` is — this is the one place a raster is shown
  /// above `maxFocusScale`, and only for a fraction of a second mid-motion,
  /// where softening is invisible.
  static let selectionPopScale: CGFloat = 1.9

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

  /// How many reactions are currently shown; the host uses it to recover the
  /// per-item stride when computing the selection flight vector.
  var itemCount: Int { imageViews.count }

  /// The capsule behind the reactions — a glass container on iOS 26, a blur
  /// view below that, an opaque view under Reduce Transparency.
  private var backdrop: UIView!

  /// The in-flight open/close animation, kept so a long-press arriving during a
  /// collapse can cancel it rather than letting its completion tear down a
  /// picker that is being reused (spec §4.3).
  private var presentationAnimator: UIViewPropertyAnimator?

  /// Per-item animators from the open cascade and the selection celebration.
  /// Tracked for the same reason as `presentationAnimator`: a long-press
  /// arriving mid-flight must be able to stop them before reusing the views.
  private var itemAnimators: [UIViewPropertyAnimator] = []

  /// The effect the backdrop was built with, kept so the selection celebration
  /// can fade the glass out (by animating `effect` to nil — the only sanctioned
  /// way to fade a UIVisualEffectView) and restore it when the picker is
  /// reused.
  private var backdropEffect: UIVisualEffect?

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
        let effect = UIGlassEffect()
        let capsule = UIVisualEffectView(effect: effect)
        addSubview(capsule)
        backdrop = capsule
        backdropEffect = effect
        return
      }
    #endif

    if UIAccessibility.isReduceTransparencyEnabled {
      let solid = UIView()
      solid.backgroundColor = .secondarySystemBackground
      addSubview(solid)
      backdrop = solid
      backdropEffect = nil
    } else {
      let effect = UIBlurEffect(style: .systemThinMaterial)
      let blur = UIVisualEffectView(effect: effect)
      addSubview(blur)
      backdrop = blur
      backdropEffect = effect
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

      addSubview(imageView)
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
    // A long-press arriving mid-collapse reuses this instance. Stopping without
    // finishing also suppresses the old completion, which would otherwise
    // detach the picker that is being reopened.
    presentationAnimator?.stopAnimation(true)
    presentationAnimator = nil
    for animator in itemAnimators { animator.stopAnimation(true) }
    itemAnimators.removeAll()

    // A reopen can land mid-celebration, with the backdrop's effect animated
    // away and item state scattered. Restore everything before collapsing.
    restoreBackdrop()

    // Grows from the bottom edge, which is the side nearest the trigger, so the
    // expansion reads as coming out of the row rather than appearing over it.
    layer.anchorPoint = CGPoint(x: 0.5, y: 1)
    alpha = 0

    guard !reduceMotion else {
      transform = .identity
      imageViews.forEach { $0.alpha = 1; $0.transform = .identity; $0.layer.zPosition = 0 }
      return
    }

    transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
    for imageView in imageViews {
      imageView.alpha = 0
      imageView.layer.zPosition = 0
      // Each reaction starts small and below its resting place, so the open
      // reads as the row rising out of the trigger rather than materialising.
      imageView.transform = CGAffineTransform(translationX: 0, y: 10)
        .scaledBy(x: 0.4, y: 0.4)
    }
  }

  func animateIn() {
    guard !reduceMotion else {
      UIView.animate(withDuration: 0.15) { self.alpha = 1 }
      return
    }

    let animator = spring(duration: 0.45, damping: 0.72) {
      self.alpha = 1
      self.transform = .identity
    }
    presentationAnimator = animator
    animator.startAnimation()

    // Reactions arrive in sequence rather than all at once. The stagger is
    // small enough that the whole row is settled well inside the time it takes
    // to move a finger to it.
    for (position, imageView) in imageViews.enumerated() {
      let animator = spring(duration: 0.42, damping: 0.58) {
        imageView.alpha = 1
        imageView.transform = .identity
      }
      itemAnimators.append(animator)
      animator.startAnimation(afterDelay: Double(position) * 0.03)
    }
  }

  func animateOut(completion: @escaping () -> Void) {
    let animator = spring(duration: 0.25, damping: 1) {
      self.alpha = 0
      if !self.reduceMotion {
        // Sinks back toward the trigger it grew out of — the inverse of the
        // open — rather than shrinking in place.
        self.transform = CGAffineTransform(translationX: 0, y: 6)
          .scaledBy(x: 0.9, y: 0.9)
      }
    }
    animator.addCompletion { [weak self] position in
      self?.presentationAnimator = nil
      // Only tear down if the collapse actually ran to the end. A cancelled
      // one means the picker was reopened and must stay attached.
      if position == .end { completion() }
    }
    presentationAnimator = animator
    animator.startAnimation()
  }

  /// The selection celebration: everything that was not chosen shrinks away,
  /// staggered outward from the choice; the chosen reaction pops past its focus
  /// scale, then shrinks and flies along `flight` — the vector from its resting
  /// position to the trigger — so the reaction reads as landing on the row that
  /// was pressed. All transform and effect animation, no geometry (spec §6.5).
  func animateSelection(
    at index: Int,
    flight: CGPoint,
    completion: @escaping () -> Void
  ) {
    guard !reduceMotion, index < imageViews.count else {
      animateOut(completion: completion)
      return
    }

    // The capsule leaves first: glass fades by animating its effect away (the
    // sanctioned fade for UIVisualEffectView), a solid backdrop by alpha, and
    // both sink slightly as they go.
    let backdropAnimator = spring(duration: 0.3, damping: 1) {
      if let effectView = self.backdrop as? UIVisualEffectView {
        effectView.effect = nil
      } else {
        self.backdrop.alpha = 0
      }
      self.backdrop.transform = CGAffineTransform(translationX: 0, y: 4)
        .scaledBy(x: 0.9, y: 0.9)
    }
    itemAnimators.append(backdropAnimator)
    backdropAnimator.startAnimation()

    // Non-selected reactions shrink away in a wave spreading outward from the
    // choice, so the eye is pulled toward what was picked.
    for (position, imageView) in imageViews.enumerated() where position != index {
      let animator = spring(duration: 0.24, damping: 1) {
        imageView.alpha = 0
        imageView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
      }
      itemAnimators.append(animator)
      animator.startAnimation(afterDelay: Double(abs(position - index)) * 0.03)
    }

    // The choice pops past its focus scale…
    let chosen = imageViews[index]
    chosen.layer.zPosition = 2
    let pop = spring(duration: 0.3, damping: 0.5) {
      chosen.transform = CGAffineTransform(
        scaleX: Metrics.selectionPopScale, y: Metrics.selectionPopScale
      )
      .translatedBy(x: 0, y: -Metrics.focusLift)
    }
    itemAnimators.append(pop)
    pop.startAnimation()

    // …then flies down to the trigger. This is the tracked animator: teardown
    // is bound to its end, and a reopen mid-flight cancels it (spec §4.3).
    let depart = spring(duration: 0.35, damping: 1) {
      chosen.alpha = 0
      chosen.transform = CGAffineTransform(translationX: flight.x, y: flight.y)
        .scaledBy(x: 0.2, y: 0.2)
    }
    depart.addCompletion { [weak self] position in
      self?.presentationAnimator = nil
      if position == .end { completion() }
    }
    presentationAnimator = depart
    depart.startAnimation(afterDelay: 0.18)
  }

  /// Puts the pooled instance back to a clean resting state after teardown, so
  /// the next open never inherits leftover transforms, alphas, or a faded
  /// backdrop. Called by the host once the closing animation has finished.
  func resetAfterDismissal() {
    transform = .identity
    alpha = 1
    restoreBackdrop()
    for imageView in imageViews {
      imageView.alpha = 1
      imageView.transform = .identity
      imageView.layer.zPosition = 0
    }
  }

  private func restoreBackdrop() {
    if let effectView = backdrop as? UIVisualEffectView {
      effectView.effect = backdropEffect
    }
    backdrop.alpha = 1
    backdrop.transform = .identity
  }

  /// Highlights the reaction under the finger. Dock-style: the focused
  /// reaction rises to full scale, its immediate neighbours partially follow
  /// and step aside, and everything else settles back — so a drag across the
  /// row reads as a travelling wave rather than a binary highlight.
  func setFocusedIndex(_ index: Int?) {
    for (position, imageView) in imageViews.enumerated() {
      let focused = position == index
      let isNeighbor = index != nil && abs(position - index!) == 1

      let target: CGAffineTransform
      var targetAlpha: CGFloat = 1
      if focused {
        target = CGAffineTransform(scaleX: Metrics.maxFocusScale, y: Metrics.maxFocusScale)
          .translatedBy(x: 0, y: -Metrics.focusLift)
      } else if isNeighbor {
        // Pushed away from the focused item so the magnified raster has room.
        let direction: CGFloat = position < index! ? -1 : 1
        target = CGAffineTransform(
          translationX: direction * Metrics.neighborShift, y: 0
        )
        .scaledBy(x: Metrics.neighborScale, y: Metrics.neighborScale)
        .translatedBy(x: 0, y: -Metrics.neighborLift)
      } else {
        target = .identity
        // A whisper of dimming on the far items keeps the eye on the wave.
        targetAlpha = index != nil ? 0.85 : 1
      }

      guard !reduceMotion else {
        imageView.transform = target
        imageView.alpha = 1
        continue
      }

      // zPosition, not bringSubviewToFront: reordering the view hierarchy
      // invalidates layout, layoutSubviews then reassigns this view's frame,
      // and that cancels the transform animation the instant it starts.
      imageView.layer.zPosition = focused ? 2 : (isNeighbor ? 1 : 0)

      // `.beginFromCurrentState` is the whole point: dragging across the row
      // retargets this animation many times per second, and without it each new
      // animation restarts from the *model* value rather than from where the
      // reaction currently appears — which reads as a pop.
      //
      // A UIViewPropertyAnimator is deliberately not used here. Stopping one
      // mid-flight to retarget leaves the model layer already at the previous
      // target, so the view jumps there instantly before the next spring runs.
      //
      // Transform only — animating the item's frame would re-evaluate the glass
      // effect behind it every frame (spec §6.5).
      UIView.animate(
        withDuration: 0.3,
        delay: 0,
        usingSpringWithDamping: 0.58,
        initialSpringVelocity: 0,
        options: [.beginFromCurrentState, .allowUserInteraction]
      ) {
        imageView.transform = target
        imageView.alpha = targetAlpha
      }
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
    // The backdrop clips itself to the capsule; the pill must not clip, or the
    // focused reaction is cut off as it scales past the capsule's bounds.
    backdrop.clipsToBounds = true
    clipsToBounds = false

    // Position via bounds and center rather than frame: these views carry a
    // scale transform while focused, and assigning `frame` to a transformed
    // view is undefined and clobbers the running animation.
    let size = CGSize(width: Metrics.itemSize, height: Metrics.itemSize)
    var x = Metrics.contentInset

    for imageView in imageViews {
      let center = CGPoint(x: x + Metrics.itemSize / 2, y: bounds.height / 2)
      if imageView.bounds.size != size {
        imageView.bounds = CGRect(origin: .zero, size: size)
      }
      if imageView.center != center {
        imageView.center = center
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
