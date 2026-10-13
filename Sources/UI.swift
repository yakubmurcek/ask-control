// ask-control visuals: a Liquid Glass consent card with a living AI-glow rim, and while
// control runs, a glow that draws itself around the screen edge plus a small glass pill.
// Pure Core Animation, no assets. Honours Reduce Motion (no spin, no springs).
import AppKit
import QuartzCore
import CoreImage

let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

/// The glow palette, looped so a conic gradient has no seam.
let palette: [NSColor] = [
  NSColor(srgbRed: 1.00, green: 0.54, blue: 0.30, alpha: 1),  // orange
  NSColor(srgbRed: 1.00, green: 0.31, blue: 0.55, alpha: 1),  // pink
  NSColor(srgbRed: 0.62, green: 0.42, blue: 1.00, alpha: 1),  // violet
  NSColor(srgbRed: 0.31, green: 0.55, blue: 1.00, alpha: 1),  // blue
  NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1),  // claude coral
  NSColor(srgbRed: 1.00, green: 0.54, blue: 0.30, alpha: 1),
]

// MARK: - Layer helpers

func conic(_ side: CGFloat, spin: CFTimeInterval) -> CAGradientLayer {
  let g = CAGradientLayer()
  g.type = .conic
  g.startPoint = CGPoint(x: 0.5, y: 0.5)
  g.endPoint = CGPoint(x: 0.5, y: 0)
  g.colors = palette.map(\.cgColor)
  g.bounds = CGRect(x: 0, y: 0, width: side, height: side)
  if !reduceMotion {
    let a = CABasicAnimation(keyPath: "transform.rotation.z")
    a.fromValue = 0
    a.toValue = -2 * Double.pi
    a.duration = spin
    a.repeatCount = .infinity
    g.add(a, forKey: "spin")
  }
  return g
}

func blur(_ r: CGFloat) -> [Any] {
  r > 0 ? [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: r])!] : []
}

/// A layer-backed view whose layers may carry Core Image filters.
class LayerView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layerUsesCoreImageFilters = true
  }
  required init?(coder: NSCoder) { fatalError() }
}

/// A gradient stroke along `paths`, in strands of (line width, blur radius, opacity):
/// a crisp line plus soft halos is what reads as "glow".
final class GlowStroke: LayerView {
  var masks: [CAShapeLayer] = []
  let host = CALayer()

  init(frame: NSRect, paths: [CGPath], strands: [(CGFloat, CGFloat, Float)], spin: CFTimeInterval) {
    super.init(frame: frame)
    host.frame = bounds
    layer!.addSublayer(host)
    let side = hypot(bounds.width, bounds.height) * 1.05
    for (width, radius, opacity) in strands {
      let strand = CALayer()
      strand.frame = bounds
      strand.opacity = opacity
      strand.filters = blur(radius)
      let inner = CALayer()
      inner.frame = bounds
      let g = conic(side, spin: spin)
      g.position = CGPoint(x: bounds.midX, y: bounds.midY)
      inner.addSublayer(g)
      let mask = CALayer()
      mask.frame = bounds
      for p in paths {
        let s = CAShapeLayer()
        s.frame = bounds
        s.path = p
        s.lineWidth = width
        s.lineCap = .round
        s.fillColor = nil
        s.strokeColor = NSColor.white.cgColor
        mask.addSublayer(s)
        masks.append(s)
      }
      inner.mask = mask
      strand.addSublayer(inner)
      host.addSublayer(strand)
    }
  }
  required init?(coder: NSCoder) { fatalError() }

  /// Draw the stroke on from its start, like ink.
  func drawOn(_ duration: CFTimeInterval) {
    guard !reduceMotion else { return }
    for m in masks {
      let a = CABasicAnimation(keyPath: "strokeEnd")
      a.fromValue = 0
      a.toValue = 1
      a.duration = duration
      a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
      m.add(a, forKey: "draw")
    }
  }

  func breathe(_ low: Float, period: CFTimeInterval) {
    guard !reduceMotion else { return }
    let a = CABasicAnimation(keyPath: "opacity")
    a.fromValue = 1
    a.toValue = low
    a.duration = period
    a.autoreverses = true
    a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    host.add(a, forKey: "breathe")
  }
}

/// Rounded rect as two halves that both start at top centre and meet at bottom centre,
/// so a draw-on animation spreads out symmetrically.
func splitRoundedRect(_ r: CGRect, radius: CGFloat) -> [CGPath] {
  [1.0, -1.0].map { (side: CGFloat) in
    let p = CGMutablePath()
    let x0 = side > 0 ? r.maxX : r.minX
    p.move(to: CGPoint(x: r.midX, y: r.maxY))
    p.addArc(tangent1End: CGPoint(x: x0, y: r.maxY), tangent2End: CGPoint(x: x0, y: r.minY), radius: radius)
    p.addArc(tangent1End: CGPoint(x: x0, y: r.minY), tangent2End: CGPoint(x: r.midX, y: r.minY), radius: radius)
    p.addLine(to: CGPoint(x: r.midX, y: r.minY))
    return p
  }
}

/// Spring the whole view in from slightly small and low (scale about its centre).
func springIn(_ v: NSView, from scale: CGFloat = 0.86, dy: CGFloat = -14, delay: CFTimeInterval = 0) {
  guard let l = v.layer else { return }
  let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
  var t = CATransform3DMakeTranslation(c.x, c.y + dy, 0)
  t = CATransform3DScale(t, scale, scale, 1)
  t = CATransform3DTranslate(t, -c.x, -c.y, 0)
  let fade = CABasicAnimation(keyPath: "opacity")
  fade.fromValue = 0
  fade.toValue = 1
  fade.duration = 0.22
  fade.beginTime = CACurrentMediaTime() + delay
  fade.fillMode = .backwards
  l.add(fade, forKey: "in-fade")
  guard !reduceMotion else { return }
  let s = CASpringAnimation(keyPath: "sublayerTransform")
  s.fromValue = t
  s.toValue = CATransform3DIdentity
  s.mass = 1
  s.stiffness = 240
  s.damping = 19
  s.duration = s.settlingDuration
  s.beginTime = CACurrentMediaTime() + delay
  s.fillMode = .backwards
  l.add(s, forKey: "in-spring")
}

/// Shrink, drift and fade away; `then` runs when it is gone.
func fadeAway(_ v: NSView, to scale: CGFloat = 0.92, dy: CGFloat = 0, duration: CFTimeInterval = 0.22, then: @escaping () -> Void) {
  guard let l = v.layer else { then(); return }
  let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
  var t = CATransform3DMakeTranslation(c.x, c.y + dy, 0)
  t = CATransform3DScale(t, scale, scale, 1)
  t = CATransform3DTranslate(t, -c.x, -c.y, 0)
  CATransaction.begin()
  CATransaction.setCompletionBlock(then)
  let g = CAAnimationGroup()
  let s = CABasicAnimation(keyPath: "sublayerTransform")
  s.toValue = reduceMotion ? CATransform3DIdentity : t
  let o = CABasicAnimation(keyPath: "opacity")
  o.toValue = 0
  g.animations = [s, o]
  g.duration = duration
  g.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
  g.fillMode = .forwards
  g.isRemovedOnCompletion = false
  l.add(g, forKey: "out")
  CATransaction.commit()
}

func glass(_ frame: NSRect, radius: CGFloat) -> NSView {
  if #available(macOS 26.0, *) {
    let g = NSGlassEffectView(frame: frame)
    g.cornerRadius = radius
    // Clear glass over busy text is unreadable; tint it toward the window background.
    g.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72)
    return g
  }
  let v = NSVisualEffectView(frame: frame)
  v.material = .hudWindow
  v.blendingMode = .behindWindow
  v.state = .active
  v.wantsLayer = true
  v.layer?.cornerRadius = radius
  v.layer?.cornerCurve = .continuous
  v.layer?.masksToBounds = true
  return v
}

func setGlassContent(_ g: NSView, _ content: NSView) {
  if #available(macOS 26.0, *), let g = g as? NSGlassEffectView {
    g.contentView = content
  } else {
    content.frame = g.bounds
    g.addSubview(content)
  }
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor = .labelColor) -> NSTextField {
  let l = NSTextField(labelWithString: s)
  l.font = .systemFont(ofSize: size, weight: weight)
  l.textColor = color
  l.alignment = .center
  l.lineBreakMode = .byTruncatingTail
  return l
}

// MARK: - Orb

/// The "AI is here" mark: a slowly turning gradient sphere with a soft halo and a glyph.
final class Orb: LayerView {
  let glyph = NSImageView()

  init(diameter d: CGFloat, symbol: String?, halo: Bool = true) {
    let pad = halo ? d * 0.4 : 0
    super.init(frame: NSRect(x: 0, y: 0, width: d + pad * 2, height: d + pad * 2))
    let c = CGPoint(x: bounds.midX, y: bounds.midY)
    if halo {
      let h = conic(d * 1.1, spin: 7)
      h.cornerRadius = d * 0.55
      h.masksToBounds = true
      h.position = c
      let hold = CALayer()
      hold.frame = bounds
      hold.filters = blur(d * 0.28)
      hold.opacity = 0.75
      hold.addSublayer(h)
      layer!.addSublayer(hold)
    }
    let core = CALayer()
    core.bounds = CGRect(x: 0, y: 0, width: d, height: d)
    core.position = c
    core.cornerRadius = d / 2
    core.masksToBounds = true
    let g = conic(d * 1.5, spin: 5)
    g.position = CGPoint(x: d / 2, y: d / 2)
    core.addSublayer(g)
    let shine = CAGradientLayer()
    shine.type = .radial
    shine.frame = core.bounds
    shine.colors = [NSColor.white.withAlphaComponent(0.55).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
    shine.startPoint = CGPoint(x: 0.32, y: 0.72)
    shine.endPoint = CGPoint(x: 1.0, y: 0.0)
    core.addSublayer(shine)
    layer!.addSublayer(core)
    if !reduceMotion {
      let b = CABasicAnimation(keyPath: "transform.scale")
      b.fromValue = 0.94
      b.toValue = 1.04
      b.duration = 1.6
      b.autoreverses = true
      b.repeatCount = .infinity
      b.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      core.add(b, forKey: "breathe")
    }
    if let symbol {
      glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      glyph.symbolConfiguration = .init(pointSize: d * 0.42, weight: .bold)
      glyph.contentTintColor = .white
      glyph.frame = NSRect(x: pad, y: pad, width: d, height: d)
      addSubview(glyph)
    }
  }
  required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Buttons

final class CapsuleButton: NSButton {
  let primary: Bool
  var hovering = false { didSet { needsDisplay = true } }

  init(_ title: String, primary: Bool) {
    self.primary = primary
    super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 36))
    isBordered = false
    bezelStyle = .regularSquare
    attributedTitle = NSAttributedString(string: title, attributes: [
      .font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
      .foregroundColor: primary ? NSColor.white : NSColor.labelColor,
    ])
    translatesAutoresizingMaskIntoConstraints = false
    widthAnchor.constraint(equalToConstant: 128).isActive = true
    heightAnchor.constraint(equalToConstant: 36).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }

  override func draw(_ dirty: NSRect) {
    let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
    if primary {
      NSGradient(colors: Array(palette[0...2]))!.draw(in: path, angle: 0)
      if hovering || isHighlighted {
        NSColor.white.withAlphaComponent(isHighlighted ? 0.25 : 0.12).setFill()
        path.fill()
      }
    } else {
      NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.2 : hovering ? 0.14 : 0.09).setFill()
      path.fill()
    }
    super.draw(dirty)
  }

  override func updateTrackingAreas() {
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
  }
  override func mouseEntered(with event: NSEvent) { hovering = true }
  override func mouseExited(with event: NSEvent) { hovering = false }
}

// MARK: - Consent card

final class ConsentCard: NSObject {
  let panel: KeyPanel
  let root: LayerView
  let allow: CapsuleButton
  var deny: CapsuleButton!
  let countdown = CAShapeLayer()
  let timeout: Int
  var decided = false
  var timer: Timer?
  let onDecision: (Bool, String) -> Void

  init(reason: String, seconds: Int, timeout: Int, onDecision: @escaping (Bool, String) -> Void) {
    self.timeout = timeout
    self.onDecision = onDecision
    let width: CGFloat = 340, margin: CGFloat = 70, radius: CGFloat = 30
    allow = CapsuleButton("Allow", primary: true)
    root = LayerView(frame: .zero)
    panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    super.init()

    allow.target = self
    allow.action = #selector(allowClicked)
    allow.isEnabled = false  // armed after a beat, so a click already in flight can't land on it
    allow.alphaValue = 0.5
    deny = CapsuleButton("Deny", primary: false)
    deny.target = self
    deny.action = #selector(denyClicked)
    deny.keyEquivalent = "\r"  // Return = Deny: a stray keypress can never allow

    let orb = Orb(diameter: 46, symbol: "cursorarrow.motionlines")
    orb.translatesAutoresizingMaskIntoConstraints = false
    orb.widthAnchor.constraint(equalToConstant: orb.frame.width).isActive = true
    orb.heightAnchor.constraint(equalToConstant: orb.frame.height).isActive = true
    let title = text("\(agentName) wants control", 17, .semibold)
    let why = text(reason, 13, .regular, .secondaryLabelColor)
    why.maximumNumberOfLines = 2
    why.cell?.wraps = true
    why.preferredMaxLayoutWidth = width - 56
    let meta = text("\(seconds < 120 ? "\(seconds) s" : "\(seconds / 60) min")  ·  esc to stop", 11.5, .medium, .tertiaryLabelColor)
    let buttons = NSStackView(views: [deny, allow])
    buttons.spacing = 10

    let line = LayerView(frame: NSRect(x: 0, y: 0, width: width - 64, height: 3))
    line.translatesAutoresizingMaskIntoConstraints = false
    line.widthAnchor.constraint(equalToConstant: width - 64).isActive = true
    line.heightAnchor.constraint(equalToConstant: 3).isActive = true
    let track = CALayer()
    track.frame = line.bounds
    track.cornerRadius = 1.5
    track.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    let fill = CAGradientLayer()
    fill.frame = line.bounds
    fill.startPoint = CGPoint(x: 0, y: 0.5)
    fill.endPoint = CGPoint(x: 1, y: 0.5)
    fill.colors = palette[0...3].map(\.cgColor)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 1.5, y: 1.5))
    p.addLine(to: CGPoint(x: line.bounds.width - 1.5, y: 1.5))
    countdown.path = p
    countdown.lineWidth = 3
    countdown.lineCap = .round
    countdown.strokeColor = NSColor.white.cgColor
    countdown.fillColor = nil
    countdown.frame = line.bounds
    fill.mask = countdown
    line.layer!.addSublayer(track)
    line.layer!.addSublayer(fill)

    let stack = NSStackView(views: [orb, title, why, meta, buttons, line])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.setCustomSpacing(-2, after: orb)
    stack.setCustomSpacing(4, after: title)
    stack.setCustomSpacing(18, after: meta)
    stack.setCustomSpacing(18, after: buttons)
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 28, bottom: 16, right: 28)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.widthAnchor.constraint(equalToConstant: width).isActive = true
    let height = stack.fittingSize.height

    let size = NSSize(width: width + margin * 2, height: height + margin * 2)
    let f = mainScreen.visibleFrame
    panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2 + f.height * 0.1,
                          width: size.width, height: size.height), display: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.hidesOnDeactivate = false
    panel.onCancel = { [weak self] in self?.decide(false, "denied (Esc)") }

    root.frame = NSRect(origin: .zero, size: size)
    let cardRect = NSRect(x: margin, y: margin, width: width, height: height)
    let rim = GlowStroke(frame: root.bounds, paths: [CGPath(roundedRect: cardRect, cornerWidth: radius, cornerHeight: radius, transform: nil)],
                         strands: [(3, 0, 1), (12, 10, 0.9), (34, 26, 0.65)], spin: 4)
    rim.breathe(0.7, period: 1.8)
    root.addSubview(rim)
    let card = glass(cardRect, radius: radius)
    setGlassContent(card, stack)
    root.addSubview(card)
    panel.contentView = root
  }

  func show() {
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    springIn(root)
    let s = NSSound(named: "Glass")
    s?.volume = 0.35
    s?.play()
    let drain = CABasicAnimation(keyPath: "strokeEnd")
    drain.fromValue = 1
    drain.toValue = 0
    drain.duration = CFTimeInterval(timeout)
    drain.fillMode = .forwards
    drain.isRemovedOnCompletion = false
    countdown.add(drain, forKey: "drain")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      self?.allow.isEnabled = true
      NSAnimationContext.runAnimationGroup { $0.duration = 0.25; self?.allow.animator().alphaValue = 1 }
    }
    timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeout), repeats: false) { [weak self] _ in
      self?.decide(false, "no answer in \(self?.timeout ?? 0) s")
    }
  }

  @objc func allowClicked() { decide(true, "allowed") }
  @objc func denyClicked() { decide(false, "denied") }

  func decide(_ ok: Bool, _ why: String) {
    guard !decided else { return }
    decided = true
    timer?.invalidate()
    // Allowed: the card sinks toward where the control pill appears. Denied: it just recedes.
    fadeAway(root, to: ok ? 0.7 : 0.92, dy: ok ? -60 : 0, duration: ok ? 0.32 : 0.2) { [self] in
      panel.orderOut(nil)
      onDecision(ok, why)
    }
  }
}

// MARK: - Control overlay

final class ControlOverlay {
  let window: NSPanel
  let edge: GlowStroke
  let pill: NSView
  let pillBox: LayerView
  let orb: Orb
  let ring = CAShapeLayer()
  let caption: NSTextField
  let endGlyph = NSImageView()
  let keycap: NSView

  init() {
    let screen = mainScreen
    window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.setFrame(screen.frame, display: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true  // never swallow the clicks being driven
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let root = LayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
    window.contentView = root

    edge = GlowStroke(frame: root.bounds, paths: splitRoundedRect(root.bounds, radius: 14),
                      strands: [(10, 0, 1), (34, 14, 0.95), (110, 48, 0.75)], spin: 6)
    edge.breathe(0.72, period: 1.7)
    root.addSubview(edge)

    // Pill: [orb + time ring]  <agent> has control  [esc]
    orb = Orb(diameter: 16, symbol: nil, halo: false)
    let ringBox = LayerView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
    orb.frame.origin = CGPoint(x: (26 - orb.frame.width) / 2, y: (26 - orb.frame.height) / 2)
    ringBox.addSubview(orb)
    ring.frame = ringBox.bounds
    ring.path = CGPath(ellipseIn: ringBox.bounds.insetBy(dx: 1.25, dy: 1.25), transform: nil)
    ring.lineWidth = 2
    ring.lineCap = .round
    ring.fillColor = nil
    ring.strokeColor = NSColor.labelColor.withAlphaComponent(0.55).cgColor
    // Start at 12 o'clock and drain counter-clockwise.
    ring.transform = CATransform3DConcat(CATransform3DMakeScale(-1, 1, 1), CATransform3DMakeRotation(.pi / 2, 0, 0, 1))
    ringBox.layer!.addSublayer(ring)
    endGlyph.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
    endGlyph.frame = ringBox.bounds
    endGlyph.alphaValue = 0
    ringBox.addSubview(endGlyph)
    ringBox.translatesAutoresizingMaskIntoConstraints = false
    ringBox.widthAnchor.constraint(equalToConstant: 26).isActive = true
    ringBox.heightAnchor.constraint(equalToConstant: 26).isActive = true

    caption = text("\(agentName) has control", 13, .semibold)
    let esc = text("esc", 11, .semibold, .secondaryLabelColor)
    keycap = NSView()
    keycap.wantsLayer = true
    keycap.layer?.cornerRadius = 6
    keycap.layer?.cornerCurve = .continuous
    keycap.layer?.borderWidth = 1
    keycap.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.22).cgColor
    keycap.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    esc.translatesAutoresizingMaskIntoConstraints = false
    keycap.addSubview(esc)
    keycap.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      esc.centerXAnchor.constraint(equalTo: keycap.centerXAnchor),
      esc.centerYAnchor.constraint(equalTo: keycap.centerYAnchor),
      keycap.widthAnchor.constraint(equalToConstant: 34),
      keycap.heightAnchor.constraint(equalToConstant: 22),
    ])
    let row = NSStackView(views: [ringBox, caption, keycap])
    row.spacing = 10
    row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    let size = NSSize(width: row.fittingSize.width, height: 46)
    let vf = screen.visibleFrame
    let origin = NSPoint(x: root.bounds.midX - size.width / 2, y: vf.minY - screen.frame.minY + 26)
    pillBox = LayerView(frame: NSRect(x: origin.x - 40, y: origin.y - 40, width: size.width + 80, height: size.height + 80))
    pill = glass(NSRect(x: 40, y: 40, width: size.width, height: size.height), radius: size.height / 2)
    row.frame = pill.bounds
    setGlassContent(pill, row)
    pillBox.addSubview(pill)
    root.addSubview(pillBox)
  }

  func show(seconds: Int) {
    window.orderFrontRegardless()
    edge.drawOn(0.9)
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.5
    edge.layer!.add(fade, forKey: "in")
    springIn(pillBox, from: 0.6, dy: -24, delay: 0.15)
    let drain = CABasicAnimation(keyPath: "strokeEnd")
    drain.fromValue = 1
    drain.toValue = 0
    drain.duration = CFTimeInterval(seconds)
    drain.fillMode = .forwards
    drain.isRemovedOnCompletion = false
    ring.add(drain, forKey: "drain")
  }

  /// Finish: the pill says what happened, the glow lets go, then everything leaves.
  /// `byUser` adds Apple's "no" shake. `then` runs once it is all gone.
  func finish(byUser: Bool, then: @escaping () -> Void) {
    endGlyph.image = NSImage(systemSymbolName: byUser ? "hand.raised.fill" : "checkmark.circle.fill", accessibilityDescription: nil)
    endGlyph.contentTintColor = byUser ? .systemOrange : .systemGreen
    let swap = CATransition()
    swap.type = .fade
    swap.duration = 0.2
    caption.layer?.add(swap, forKey: "swap")
    caption.stringValue = byUser ? "Stopped" : "Back to you"
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.2
      orb.animator().alphaValue = 0
      endGlyph.animator().alphaValue = 1
      keycap.animator().alphaValue = 0
    }
    ring.removeAllAnimations()
    ring.opacity = 0
    if byUser && !reduceMotion, let l = pillBox.layer {
      let shake = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.x")
      shake.values = [0, -9, 8, -6, 4, -2, 0]
      shake.duration = 0.42
      l.add(shake, forKey: "shake")
    }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.55
      edge.animator().alphaValue = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
      fadeAway(pillBox, to: 0.85, dy: -10, duration: 0.25) { [self] in
        window.orderOut(nil)
        then()
      }
    }
  }
}
