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

  /// The divider between the consumer's reactions and the "another reaction"
  /// section (custom pick + plus): a hairline with a gap either side. The
  /// extra width it adds over a normal inter-item gap.
  static let separatorLineWidth: CGFloat = 1
  static let separatorGap: CGFloat = 8
  static var separatorExtra: CGFloat {
    separatorGap * 2 + separatorLineWidth - itemSpacing
  }

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

// MARK: - Surface appearance

/// The picker floats over arbitrary app content, so the system theme says
/// nothing about what is actually behind it — a dark screen in a light-mode
/// app got a light pill that all but vanished. The pixels behind the trigger
/// decide instead: walking view background colours is defeated by React
/// Native's view flattening (the painted colour often lives on no ancestor at
/// all), so the trigger's on-screen region is sampled directly. One tiny
/// render per open, at gesture-begin — never on the scroll or focus path.
enum SurfaceAppearance {
  /// `rect` is in the coordinate space of `view`'s window, and is the area the
  /// pill will actually occupy — not the trigger's own frame. PickerLayout
  /// places the pill *above* its trigger, so the trigger's pixels answer the
  /// wrong question: a dark row sitting under a light page resolved `.dark`
  /// and put white symbols on white.
  static func isDark(in rect: CGRect, relativeTo view: UIView) -> Bool {
    let fallback = view.traitCollection.userInterfaceStyle == .dark
    guard let window = view.window else { return fallback }
    let rect = rect.intersection(window.bounds)
    guard !rect.isEmpty, rect.width >= 1, rect.height >= 1 else { return fallback }

    // The whole trigger area squashed into a handful of pixels: the average
    // is wanted anyway, and the tiny target keeps the snapshot cheap.
    let sample = CGSize(width: 4, height: 4)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: sample, format: format)
      .image { context in
        let cg = context.cgContext
        cg.scaleBy(x: sample.width / rect.width, y: sample.height / rect.height)
        cg.translateBy(x: -rect.minX, y: -rect.minY)
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
      }

    guard
      let cgImage = image.cgImage,
      let data = cgImage.dataProvider?.data,
      let bytes = CFDataGetBytePtr(data)
    else { return fallback }

    let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
    var total: CGFloat = 0
    var count = 0
    for y in 0..<cgImage.height {
      for x in 0..<cgImage.width {
        let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
        // Channel order varies by format; for a dark-vs-light call an even
        // average is as good as true luminance.
        let a = CGFloat(bytes[offset])
        let b = CGFloat(bytes[offset + 1])
        let c = CGFloat(bytes[offset + 2])
        total += (a + b + c) / (3 * 255)
        count += 1
      }
    }
    guard count > 0 else { return fallback }
    return total / CGFloat(count) < 0.5
  }
}

// MARK: - Renderable

/// How a drawn slot takes colour.
///
/// Three cases rather than a `UIColor?`, because the rule that matters — only
/// a `.system` symbol changes colour when it becomes the selected reaction —
/// is then a case split rather than a nil check whose meaning has to be
/// remembered. `.own` covers both emoji, which carry colour in their glyphs,
/// and a symbol the consumer coloured: in both, the colour on screen is the
/// one that was asked for, and selection must not overwrite it.
enum SymbolTint: Equatable {
  /// The image brings its own colour. Never tinted, never re-tinted.
  case own
  /// A monochrome symbol: `.label` normally, `.tintColor` when selected.
  case system
  /// A symbol drawn from its own palette. Tinted `.label` like a plain symbol
  /// — a multicolor image is not a template, so only the layers Apple marked
  /// as accent take that colour and the rest keep theirs — but never re-tinted
  /// on selection, which would recolour those accent layers alone and leave
  /// the glyph half-selected.
  case multicolor
  /// A monochrome symbol the consumer gave a colour. Held through selection.
  case custom(UIColor)
}

/// A reaction resolved down to what actually gets drawn. Resolution happens
/// once per prop change; layout and drawing never re-resolve.
struct Renderable {
  let id: String
  let image: UIImage?
  let tint: SymbolTint
  let accessibilityLabel: String
}

// MARK: - View

/// Conforms to `SlotGeometry` because it is the layout authority: the same
/// `slotCenterX` that positions the reactions is what the interaction hit-tests
/// against, so the two can never disagree about where a slot is.
final class ReactionsPillView: UIView, SlotGeometry {

  private var renderables: [Renderable] = []
  private var imageViews: [UIImageView] = []

  /// Index of the first item after the section divider, or nil for no divider.
  private var separatorAfter: Int?
  private let separatorView = UIView()

  /// How many reactions are currently shown; the host uses it to recover the
  /// per-item stride when computing the selection flight vector.
  var itemCount: Int { imageViews.count }

  // MARK: Slot geometry

  /// Centre of slot `index` in the pill's own coordinates. Delegates to
  /// `SlotLayout`, which both this and `slotIndex(atLocalX:)` below call into
  /// — the single source of truth for layout, hit-testing, and the selection
  /// flight vector — slots are not uniform once the separator inserts its
  /// extra width.
  func slotCenterX(at index: Int) -> CGFloat {
    SlotLayout.centerX(
      at: index, itemSize: Metrics.itemSize, itemSpacing: Metrics.itemSpacing,
      contentInset: Metrics.contentInset, separatorAfter: separatorAfter,
      separatorExtra: Metrics.separatorExtra
    )
  }

  /// The slot nearest the given local x, clamped to the row. The host has
  /// already checked the point is inside the pill's (tolerance-inset) frame.
  func slotIndex(atLocalX x: CGFloat) -> Int? {
    SlotLayout.nearestIndex(
      atLocalX: x, count: renderables.count, itemSize: Metrics.itemSize,
      itemSpacing: Metrics.itemSpacing, contentInset: Metrics.contentInset,
      separatorAfter: separatorAfter, separatorExtra: Metrics.separatorExtra
    )
  }

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

  func apply(items: [Renderable], selectedId: String?, separatorAfter: Int?) {
    renderables = items
    self.separatorAfter = separatorAfter
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
      switch renderable.tint {
      case .own: break
      case .system, .multicolor: imageView.tintColor = .label
      case .custom(let color): imageView.tintColor = color
      }

      imageView.isAccessibilityElement = true
      imageView.accessibilityLabel = renderable.accessibilityLabel
      imageView.accessibilityTraits = .button

      addSubview(imageView)
      imageViews.append(imageView)
    }

    // A dynamic provider, not `UIColor.label.withAlphaComponent(0.25)`:
    // withAlphaComponent resolves the dynamic colour against whatever traits
    // are current when it is called and returns a *static* colour. Items are
    // built before the surface trait is known, so the frozen value was always
    // the system theme's and never followed the pill.
    separatorView.backgroundColor = UIColor { trait in
      UIColor.label.resolvedColor(with: trait).withAlphaComponent(0.25)
    }
    separatorView.isHidden = separatorAfter == nil
    addSubview(separatorView)
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

    // The pill's own alpha stays 1 throughout its lifetime. Fading it — or any
    // ancestor of the effect view — renders the glass as a translucent grey
    // snapshot until the fade completes, which read as "semi-transparent
    // capsule first, real glass after". Nor is the glass *effect* animated:
    // UIKit interpolates UIGlassEffect through the same frosted state. Glass
    // is simply present from the first frame — the open's motion comes from
    // the scale and the item cascade. Blur (pre-26) interpolates cleanly, so
    // it alone fades by effect.
    alpha = 1
    if !usingGlass {
      removeBackdropPresence()
    }
    separatorView.alpha = 0

    guard !reduceMotion else {
      transform = .identity
      imageViews.forEach { $0.alpha = 0; $0.transform = .identity; $0.layer.zPosition = 0 }
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
      UIView.animate(withDuration: 0.15) {
        if !self.usingGlass { self.restoreBackdropPresence() }
        self.separatorView.alpha = 1
        self.imageViews.forEach { $0.alpha = 1 }
      }
      return
    }

    let animator = spring(duration: 0.45, damping: 0.72) {
      if !self.usingGlass { self.restoreBackdropPresence() }
      self.separatorView.alpha = 1
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
      // Blur leaves by its effect; glass stays applied while the pill sinks
      // and is detached whole at teardown — animating UIGlassEffect out plays
      // the same frosted flash as animating it in.
      if !self.usingGlass { self.removeBackdropPresence() }
      self.separatorView.alpha = 0
      self.imageViews.forEach { $0.alpha = 0 }
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

  /// The selection celebration — a stamp: everything that was not chosen
  /// shrinks away, staggered outward from the choice; the chosen reaction pops
  /// past its focus scale, then presses back down in place and fades — like a
  /// stamp lifting off the row. No flight across the screen: the consumer's
  /// own UI reflects the selection at the same moment, and an emoji streaking
  /// from the picker to the row read as a glitch rather than a celebration.
  /// All transform and effect animation, no geometry (spec §6.5).
  func animateSelection(at index: Int, completion: @escaping () -> Void) {
    guard !reduceMotion, index < imageViews.count else {
      animateOut(completion: completion)
      return
    }

    // The capsule leaves first: blur by animating its effect away, a solid
    // backdrop by alpha, glass by sinking alone (its effect is never animated
    // — that plays a frosted flash), and all sink slightly as they go.
    let backdropAnimator = spring(duration: 0.3, damping: 1) {
      if !self.usingGlass { self.removeBackdropPresence() }
      self.separatorView.alpha = 0
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

    // …then presses back down in place and fades, like a stamp lifting off.
    // This is the tracked animator: teardown is bound to its end, and a
    // reopen mid-flight cancels it (spec §4.3).
    let settle = spring(duration: 0.25, damping: 1) {
      chosen.alpha = 0
      chosen.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
    }
    settle.addCompletion { [weak self] position in
      self?.presentationAnimator = nil
      if position == .end { completion() }
    }
    presentationAnimator = settle
    settle.startAnimation(afterDelay: 0.18)
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

  /// Brings the capsule on screen: blur by assigning its effect, a solid
  /// backdrop by alpha. Never called for glass — glass is present from the
  /// first frame and removed only at teardown, because UIKit interpolates
  /// UIGlassEffect through a frosted state that reads as a grey flash.
  private func restoreBackdropPresence() {
    if let effectView = backdrop as? UIVisualEffectView {
      effectView.effect = backdropEffect
    } else {
      backdrop.alpha = 1
    }
  }

  private func removeBackdropPresence() {
    if let effectView = backdrop as? UIVisualEffectView {
      effectView.effect = nil
    } else {
      backdrop.alpha = 0
    }
  }

  private func restoreBackdrop() {
    if let effectView = backdrop as? UIVisualEffectView {
      effectView.effect = backdropEffect
    }
    backdrop.alpha = 1
    backdrop.transform = .identity
    separatorView.alpha = 1
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
    // expressed as a tint. Emoji bring their own colour and are left alone —
    // and so is a symbol the consumer coloured, for the same reason: tinting
    // over a supplied colour would throw that colour away. See spec §5.
    for (index, renderable) in renderables.enumerated() where renderable.tint == .system {
      guard index < imageViews.count else { continue }
      imageViews[index].tintColor =
        renderable.id == selectedId ? .tintColor : .label
    }
  }

  // MARK: Layout

  override var intrinsicContentSize: CGSize {
    let count = CGFloat(renderables.count)
    guard count > 0 else { return .zero }
    var width =
      count * Metrics.itemSize
      + max(0, count - 1) * Metrics.itemSpacing
      + Metrics.contentInset * 2
    if separatorAfter != nil {
      width += Metrics.separatorExtra
    }
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

    for (index, imageView) in imageViews.enumerated() {
      let center = CGPoint(x: slotCenterX(at: index), y: bounds.height / 2)
      if imageView.bounds.size != size {
        imageView.bounds = CGRect(origin: .zero, size: size)
      }
      if imageView.center != center {
        imageView.center = center
      }
    }

    if let separatorAfter {
      // Centred in the widened gap before the first "another reaction" slot.
      let lineX = slotCenterX(at: separatorAfter)
        - Metrics.itemSize / 2 - Metrics.separatorGap
        - Metrics.separatorLineWidth / 2
      separatorView.bounds = CGRect(
        x: 0, y: 0,
        width: Metrics.separatorLineWidth, height: Metrics.itemSize * 0.6
      )
      separatorView.center = CGPoint(x: lineX, y: bounds.height / 2)
      separatorView.layer.cornerRadius = Metrics.separatorLineWidth / 2
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

  /// `multicolor` asks SF Symbols for the glyph's own palette.
  ///
  /// The rendering mode is deliberately left alone. A multicolor symbol image
  /// is not a template, so the colours in it survive a tint on their own —
  /// while the layers Apple marked as *accent* still take the view's tint,
  /// which is what makes `flame.fill` stay orange where an accent-only symbol
  /// follows `.label`. Forcing `.alwaysOriginal` here froze that accent at
  /// UIKit's default blue and painted the whole glyph with it.
  ///
  /// A symbol with no multicolor variant renders in its monochrome form rather
  /// than failing, so this never falls through to the emoji — which is right:
  /// the glyph the consumer named is what they asked for, and its palette was
  /// the preference.
  static func symbol(_ name: String, multicolor: Bool = false) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(
      pointSize: Metrics.rasterSize * 0.62,
      weight: .semibold
    )
    let image = UIImage(systemName: name, withConfiguration: configuration)
    guard multicolor else { return image }
    return image?.applyingSymbolConfiguration(
      UIImage.SymbolConfiguration.preferringMulticolor()
    )
  }

  /// Chrome for the trailing "another reaction" item: by default a dashed
  /// emoji with a plus badge in the corner, so it reads as "pick any emoji"
  /// rather than one more reaction. Template-rendered so it tints with `.label`
  /// like other symbols.
  ///
  /// `symbolName` overrides the glyph; `nil` uses the built-in dashed face
  /// (`face.dashed` is iOS 16+, `circle.dashed` covers 15). Returns `nil` when
  /// a supplied name resolves to no symbol, which is the caller's cue to fall
  /// back to emoji.
  ///
  /// Takes no multicolor option. Glyph and badge are composited into one
  /// bitmap, so any palette would be *baked* — and a symbol without a
  /// multicolor variant would bake its monochrome fallback too, freezing a
  /// colour that must track the surface the pill lands on. A hex colour is
  /// safe here because the composite stays a tintable template; a palette is
  /// not, so `'multicolor'` leaves this item on its default treatment.
  static func anotherReaction(symbolName: String? = nil, badge: Bool = true) -> UIImage? {
    let side = Metrics.rasterSize

    let resolvedName: String
    if let symbolName, !symbolName.isEmpty {
      guard UIImage(systemName: symbolName) != nil else { return nil }
      resolvedName = symbolName
    } else {
      resolvedName = UIImage(systemName: "face.dashed") != nil
        ? "face.dashed"
        : "circle.dashed"
    }

    let format = UIGraphicsImageRendererFormat.preferred()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: side, height: side),
      format: format
    )

    let face = UIImage(
      systemName: resolvedName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: side * 0.56, weight: .medium)
    )
    let plus = UIImage(
      systemName: "plus.circle.fill",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: side * 0.32, weight: .bold)
    )

    let image = renderer.image { context in
      let ctx = context.cgContext
      // Without the badge the glyph owns the whole tile: nothing has to be left
      // clear in the corner, so it can be drawn at the size a lone symbol wants.
      let faceSize = side * (badge ? 0.78 : 0.92)
      let faceRect = CGRect(
        x: badge ? side * 0.05 : (side - faceSize) / 2,
        y: badge ? side * 0.02 : (side - faceSize) / 2,
        width: faceSize,
        height: faceSize
      )
      // Drawn black-on-template so the whole tile comes out as one tintable
      // mask, whatever colour it is eventually asked to take.
      face?.withTintColor(.black, renderingMode: .alwaysTemplate).draw(in: faceRect)

      guard badge else { return }
      let badgeSize = side * 0.40
      let badgeRect = CGRect(
        x: side - badgeSize - side * 0.02,
        y: side - badgeSize - side * 0.02,
        width: badgeSize,
        height: badgeSize
      )
      // Gap so the badge sits on the dashed face rather than merging with it.
      ctx.setBlendMode(.clear)
      ctx.fillEllipse(in: badgeRect.insetBy(dx: -side * 0.045, dy: -side * 0.045))
      ctx.setBlendMode(.normal)
      plus?.withTintColor(.black, renderingMode: .alwaysTemplate).draw(in: badgeRect)
    }
    return image.withRenderingMode(.alwaysTemplate)
  }
}

// MARK: - Resolution

/// Turns items into drawables once, applying the fallback chain from spec §5:
/// prefer a symbol under `auto` when one is supplied and actually resolves,
/// otherwise emoji — which is required on every item, so this never yields
/// nothing to draw. Shared by the standalone view and the host.
enum ReactionResolver {
  /// The synthetic id carried by the trailing "another reaction" plus item.
  /// Never reported through onSelect — releasing on it opens the emoji picker.
  static let anotherReactionId = "__another_reaction__"

  /// Default label for the "another reaction" item when the consumer supplies
  /// none. English-only, which is why `accessibilityLabel` is overridable.
  static let anotherReactionLabel = "Add another reaction"

  /// The single entry point: one slot in, one drawable out.
  ///
  /// Renderables are *derived from* the interaction's slots rather than built
  /// alongside them, which is what makes it impossible for the drawn row and
  /// the hit-tested row to disagree about what sits at a given index.
  ///
  /// The *order* to try is `ReactionResolution`'s call — pure, and shared with
  /// Android via a mirrored file. This function's only job is to walk that
  /// order and draw the first candidate that actually rasterises: whether a
  /// supplied symbol name resolves to an image is a question only
  /// `ReactionRasteriser` can answer, which is exactly why the pure module
  /// hands back a chain instead of one resolved choice.
  static func renderable(
    for slot: Slot,
    renderMode: ReactionRenderMode
  ) -> Renderable {
    let mode: RenderMode = renderMode == .auto ? .auto : .emoji
    let order = ReactionResolution.resolutionOrder(
      for: slot, renderMode: mode, symbolsSupported: true
    )

    // Read once per slot rather than per candidate: what the consumer asked
    // for does not change as the chain is walked, only whether the candidate
    // being tried is a symbol at all.
    let paint = SymbolPaint(symbolColor(for: slot))

    for candidate in order {
      if let image = image(for: candidate, paint: paint) {
        return Renderable(
          id: id(for: slot),
          image: image,
          tint: tint(for: candidate, paint: paint),
          accessibilityLabel: label(for: slot)
        )
      }
    }

    // Unreached in practice: the chain always ends in `.emoji` or `.builtIn`,
    // and `NativeReactionItem.emoji` is required, so only an empty custom pick
    // could get here. Drawing nothing is still better than force-unwrapping.
    return Renderable(
      id: id(for: slot), image: nil, tint: .own, accessibilityLabel: label(for: slot)
    )
  }

  private static func image(for candidate: Candidate, paint: SymbolPaint) -> UIImage? {
    switch candidate {
    case .symbol(let name):
      return ReactionRasteriser.symbol(name, multicolor: paint == .multicolor)
    // No multicolor here: the ＋ item is a composite bitmap and cannot carry a
    // palette safely. See `ReactionRasteriser.anotherReaction`.
    case .anotherSymbol(let name, let badge):
      return ReactionRasteriser.anotherReaction(symbolName: name, badge: badge)
    case .emoji(let value):
      return ReactionRasteriser.emoji(value)
    // The built-in dashed face has no palette of its own to prefer, so asking
    // for one changes nothing about how it draws.
    case .builtIn(let badge):
      return ReactionRasteriser.anotherReaction(badge: badge)
    }
  }

  /// How the drawn image takes colour.
  ///
  /// Every candidate but `.emoji` is a monochrome template image — the built-in
  /// glyph included, since it is chrome rather than content — so all of them
  /// tint, unless the consumer asked for the glyph's own palette, which came
  /// out of the rasteriser already coloured and must not be tinted over.
  ///
  /// The paint comes off the *slot* rather than the candidate because
  /// `Candidate` is `ReactionResolution`'s type, and that module decides the
  /// order to try, not what the result looks like.
  private static func tint(for candidate: Candidate, paint: SymbolPaint) -> SymbolTint {
    if case .emoji = candidate { return .own }
    switch paint {
    case .default:
      return .system
    // Only a lone symbol is drawn from a palette; the ＋ composite ignored the
    // request, so it must keep the treatment that goes with what was drawn.
    case .multicolor:
      if case .symbol = candidate { return .multicolor }
      return .system
    case .solid(let color):
      return .custom(
        UIColor(
          red: color.red, green: color.green, blue: color.blue, alpha: color.alpha
        )
      )
    }
  }

  private static func symbolColor(for slot: Slot) -> String? {
    switch slot {
    case .reaction(let reaction): return reaction.symbolColor
    // A custom pick is an emoji and never draws as a symbol, so it has no
    // colour to give.
    case .custom: return nil
    case .another(let appearance): return appearance?.symbolColor
    }
  }

  private static func id(for slot: Slot) -> String {
    switch slot {
    case .reaction(let reaction): return reaction.id
    // The custom pick's id is the emoji itself — it exists in no item list,
    // so the emoji is the only stable identity it has.
    case .custom(let emoji): return emoji
    case .another: return anotherReactionId
    }
  }

  private static func label(for slot: Slot) -> String {
    switch slot {
    case .reaction(let reaction): return reaction.accessibilityLabel
    case .custom(let emoji): return emoji
    case .another(let appearance): return appearance?.accessibilityLabel ?? anotherReactionLabel
    }
  }
}
