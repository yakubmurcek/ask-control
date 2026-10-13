// ask-control visuals, in Claude's palette: warm ivory, one terracotta accent, a serif title.
// The card's cursor mark ripples while it waits; once allowed, the real pointer wears a
// terracotta halo with an ember trail, a thin line traces the screen edge, and a pill hangs
// under the notch. Pure Core Animation, no assets.
// Honours Reduce Motion (no springs, ripples or draw-on) and light/dark appearance.
import AppKit
import QuartzCore
import CoreImage

let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
let isDark = ProcessInfo.processInfo.environment["ASK_CONTROL_APPEARANCE"].map { $0 == "dark" }  // for testing
  ?? (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
}

/// Claude's colours, resolved once for the current appearance.
enum Palette {
  static let accent = hex(0xD97757)                          // terracotta
  static let accentDeep = hex(0xC6613F)                      // pressed / hover
  static let ember = hex(0xF2A07B)                           // the cursor's trail
  static let surface = isDark ? hex(0x262624) : hex(0xFAF9F5)  // ivory
  static let hairline = isDark ? hex(0x3D3C38) : hex(0xE8E6DC)
  static let edge = isDark ? hex(0x45443F) : hex(0xDDD9CC)
  static let ink = isDark ? hex(0xF5F4EE) : hex(0x141413)
  static let muted = isDark ? hex(0xA6A39A) : hex(0x73726C)
  static let faint = isDark ? hex(0x7A776F) : hex(0xA9A79F)
}

// MARK: - Layer helpers

func blur(_ r: CGFloat) -> [Any] { [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: r])!] }

/// A layer-backed view whose layers may carry Core Image filters.
class LayerView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layerUsesCoreImageFilters = true
  }
  required init?(coder: NSCoder) { fatalError() }
}

func stroke(_ path: CGPath, _ frame: CGRect, width: CGFloat, color: NSColor) -> CAShapeLayer {
  let s = CAShapeLayer()
  s.frame = frame
  s.path = path
  s.lineWidth = width
  s.lineCap = .round
  s.lineJoin = .round
  s.fillColor = nil
  s.strokeColor = color.cgColor
  return s
}

/// Rounded rect as two halves that both start at top centre (where the pill hangs) and
/// meet at bottom centre, so a draw-on animation runs down both sides symmetrically.
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

/// Spring the view in from slightly small and low (scale about its centre).
func springIn(_ v: NSView, from scale: CGFloat = 0.96, dy: CGFloat = -10, delay: CFTimeInterval = 0) {
  guard let l = v.layer else { return }
  let fade = CABasicAnimation(keyPath: "opacity")
  fade.fromValue = 0
  fade.toValue = 1
  fade.duration = 0.2
  fade.beginTime = CACurrentMediaTime() + delay
  fade.fillMode = .backwards
  l.add(fade, forKey: "in-fade")
  guard !reduceMotion else { return }
  let s = CASpringAnimation(keyPath: "sublayerTransform")
  s.fromValue = scaled(v, scale, dy)
  s.toValue = CATransform3DIdentity
  s.stiffness = 300
  s.damping = 24
  s.duration = s.settlingDuration
  s.beginTime = CACurrentMediaTime() + delay
  s.fillMode = .backwards
  l.add(s, forKey: "in-spring")
}

func scaled(_ v: NSView, _ scale: CGFloat, _ dy: CGFloat) -> CATransform3D {
  let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
  var t = CATransform3DMakeTranslation(c.x, c.y + dy, 0)
  t = CATransform3DScale(t, scale, scale, 1)
  return CATransform3DTranslate(t, -c.x, -c.y, 0)
}

/// Shrink, drift and fade away; `then` runs when it is gone.
func fadeAway(_ v: NSView, to scale: CGFloat = 0.97, dy: CGFloat = 0, duration: CFTimeInterval = 0.18, then: @escaping () -> Void) {
  guard let l = v.layer else { then(); return }
  CATransaction.begin()
  CATransaction.setCompletionBlock(then)
  let s = CABasicAnimation(keyPath: "sublayerTransform")
  s.toValue = reduceMotion ? CATransform3DIdentity : scaled(v, scale, dy)
  let o = CABasicAnimation(keyPath: "opacity")
  o.toValue = 0
  let g = CAAnimationGroup()
  g.animations = [s, o]
  g.duration = duration
  g.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
  g.fillMode = .forwards
  g.isRemovedOnCompletion = false
  l.add(g, forKey: "out")
  CATransaction.commit()
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, serif: Bool = false) -> NSTextField {
  let l = NSTextField(labelWithString: s)
  var font = NSFont.systemFont(ofSize: size, weight: weight)
  if serif, let d = font.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { font = f }
  l.font = font
  l.textColor = color
  l.lineBreakMode = .byTruncatingTail
  return l
}

func fixedSize(_ v: NSView, _ w: CGFloat, _ h: CGFloat) {
  v.translatesAutoresizingMaskIntoConstraints = false
  v.widthAnchor.constraint(equalToConstant: w).isActive = true
  v.heightAnchor.constraint(equalToConstant: h).isActive = true
}

/// Small rounded key, like the one printed on the keyboard.
func keycap(_ label: String, onInk: Bool = false) -> NSView {
  let k = NSView()
  k.wantsLayer = true
  k.layer?.cornerRadius = 5
  k.layer?.cornerCurve = .continuous
  k.layer?.borderWidth = 1
  k.layer?.borderColor = (onInk ? hex(0x45443F) : Palette.hairline).cgColor
  k.layer?.backgroundColor = (onInk ? hex(0x262624) : isDark ? hex(0x30302E) : NSColor.white).cgColor
  let t = text(label, 10.5, .medium, onInk ? hex(0xB0AEA5) : Palette.muted)
  t.translatesAutoresizingMaskIntoConstraints = false
  k.addSubview(t)
  NSLayoutConstraint.activate([t.centerXAnchor.constraint(equalTo: k.centerXAnchor), t.centerYAnchor.constraint(equalTo: k.centerYAnchor)])
  fixedSize(k, 30, 20)
  return k
}

// MARK: - Mark

/// A cursor with rings rippling out of it: something is reaching for your pointer.
final class ReachMark: LayerView {
  init(size d: CGFloat) {
    super.init(frame: NSRect(x: 0, y: 0, width: d, height: d))
    let c = CGPoint(x: d / 2, y: d / 2)
    let disc = CALayer()
    disc.bounds = CGRect(x: 0, y: 0, width: d * 0.62, height: d * 0.62)
    disc.position = c
    disc.cornerRadius = d * 0.31
    disc.backgroundColor = Palette.accent.cgColor
    layer!.addSublayer(disc)
    for i in 0..<3 where !reduceMotion {
      let ring = CAShapeLayer()
      ring.frame = bounds
      ring.path = CGPath(ellipseIn: CGRect(x: c.x - d * 0.31, y: c.y - d * 0.31, width: d * 0.62, height: d * 0.62), transform: nil)
      ring.fillColor = nil
      ring.strokeColor = Palette.accent.cgColor
      ring.lineWidth = 1.2
      ring.opacity = 0
      let grow = CABasicAnimation(keyPath: "transform.scale")
      grow.fromValue = 1
      grow.toValue = 1.6
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.7
      fade.toValue = 0
      let g = CAAnimationGroup()
      g.animations = [grow, fade]
      g.duration = 2.4
      g.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.3, 1)
      g.repeatCount = .infinity
      g.beginTime = CACurrentMediaTime() + Double(i) * 0.8
      ring.add(g, forKey: "ripple")
      layer!.insertSublayer(ring, below: disc)
    }
    let arrow = NSImageView(image: NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)!)
    arrow.symbolConfiguration = .init(pointSize: d * 0.3, weight: .semibold)
    arrow.contentTintColor = .white
    arrow.frame = bounds.offsetBy(dx: 1, dy: 0)
    addSubview(arrow)
  }
  required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Buttons

final class FlatButton: NSButton {
  /// Deny is the quiet default (light, with a return glyph: Return denies); Allow is the one
  /// terracotta fill on the card.
  let isDefault: Bool
  var hovering = false { didSet { needsDisplay = true } }

  init(_ title: String, isDefault: Bool) {
    self.isDefault = isDefault
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    let t = NSMutableAttributedString(string: title, attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: isDefault ? Palette.ink : NSColor.white,
    ])
    if isDefault {
      t.append(NSAttributedString(string: "  ↩", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: Palette.faint,
      ]))
    }
    attributedTitle = t
    fixedSize(self, isDefault ? 88 : 76, 30)
  }
  required init?(coder: NSCoder) { fatalError() }

  override func draw(_ dirty: NSRect) {
    let r = bounds.insetBy(dx: 0.75, dy: 0.75)
    let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
    if isDefault {
      (isHighlighted ? Palette.hairline : hovering ? Palette.hairline.withAlphaComponent(0.5) : isDark ? hex(0x30302E) : .white).setFill()
      path.fill()
      Palette.edge.setStroke()
      path.lineWidth = 1
      path.stroke()
    } else {
      (isHighlighted || hovering ? Palette.accentDeep : Palette.accent).setFill()
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

/// Solid ivory surface with a hairline edge and a soft shadow.
func surface(_ frame: NSRect, radius: CGFloat, ink: Bool = false) -> NSView {
  let v = NSView(frame: frame)
  v.wantsLayer = true
  v.layer?.backgroundColor = (ink ? hex(0x141413) : Palette.surface).cgColor
  v.layer?.cornerRadius = radius
  v.layer?.cornerCurve = .continuous
  v.layer?.borderWidth = 1
  v.layer?.borderColor = (ink ? hex(0x2E2D2A) : Palette.edge).cgColor
  v.layer?.shadowColor = NSColor.black.cgColor
  v.layer?.shadowOpacity = isDark || ink ? 0.4 : 0.28
  v.layer?.shadowRadius = ink ? 18 : 40
  v.layer?.shadowOffset = CGSize(width: 0, height: ink ? -6 : -12)
  return v
}

// MARK: - Consent card

final class ConsentCard: NSObject {
  let panel: KeyPanel
  let root: LayerView
  let allow = FlatButton("Allow", isDefault: false)
  let deny = FlatButton("Deny", isDefault: true)
  let drain = CAShapeLayer()
  let timeout: Int
  var decided = false
  var timer: Timer?
  let onDecision: (Bool, String) -> Void

  init(reason: String, seconds: Int, timeout: Int, onDecision: @escaping (Bool, String) -> Void) {
    self.timeout = timeout
    self.onDecision = onDecision
    let width: CGFloat = 400, margin: CGFloat = 48, radius: CGFloat = 18, inset: CGFloat = 26
    root = LayerView(frame: .zero)
    panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    super.init()

    allow.target = self
    allow.action = #selector(allowClicked)
    allow.isEnabled = false  // armed after a beat, so a click already in flight can't land on it
    allow.alphaValue = 0.45
    deny.target = self
    deny.action = #selector(denyClicked)
    deny.keyEquivalent = "\r"  // Return = Deny: a stray keypress can never allow

    let mark = ReachMark(size: 46)
    fixedSize(mark, 46, 46)
    let title = text("\(agentName) wants control", 21, .regular, Palette.ink, serif: true)
    let why = NSTextField(wrappingLabelWithString: reason)
    why.font = .systemFont(ofSize: 13)
    why.textColor = Palette.muted
    why.maximumNumberOfLines = 3
    why.preferredMaxLayoutWidth = width - inset * 2

    // A hairline that drains toward the auto-deny.
    let lineW = width - inset * 2
    let line = LayerView(frame: NSRect(x: 0, y: 0, width: lineW, height: 2))
    fixedSize(line, lineW, 2)
    line.layer!.backgroundColor = Palette.hairline.cgColor
    line.layer!.cornerRadius = 1
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 1))
    p.addLine(to: CGPoint(x: lineW, y: 1))
    drain.path = p
    drain.frame = line.bounds
    drain.lineWidth = 2
    drain.strokeColor = Palette.accent.cgColor
    line.layer!.addSublayer(drain)

    let meta = NSStackView(views: [text(seconds < 120 ? "for \(seconds) s" : "for \(seconds / 60) min", 12, .regular, Palette.faint),
                                   text("·", 12, .regular, Palette.faint), keycap("esc"), text("stops it", 12, .regular, Palette.faint)])
    meta.spacing = 5
    let spacer = NSView()
    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    let footer = NSStackView(views: [meta, spacer, deny, allow])
    footer.spacing = 8
    footer.translatesAutoresizingMaskIntoConstraints = false
    footer.widthAnchor.constraint(equalToConstant: lineW).isActive = true

    let stack = NSStackView(views: [mark, title, why, line, footer])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.setCustomSpacing(14, after: mark)
    stack.setCustomSpacing(18, after: why)
    stack.setCustomSpacing(14, after: line)
    stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: 20, right: inset)
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
    let card = surface(cardRect, radius: radius)
    card.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      stack.topAnchor.constraint(equalTo: card.topAnchor),
      stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
    ])
    root.addSubview(card)
    panel.contentView = root
  }

  func show() {
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    springIn(root)
    let s = NSSound(named: "Tink")
    s?.volume = 0.4
    s?.play()
    let a = CABasicAnimation(keyPath: "strokeEnd")
    a.fromValue = 1
    a.toValue = 0
    a.duration = CFTimeInterval(timeout)
    a.fillMode = .forwards
    a.isRemovedOnCompletion = false
    drain.add(a, forKey: "drain")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      self?.allow.isEnabled = true
      NSAnimationContext.runAnimationGroup { $0.duration = 0.2; self?.allow.animator().alphaValue = 1 }
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
    // Allowed: the card rises toward the notch while the overlay already starts, so there is
    // no dead air between them. Denied: it just recedes, then we report.
    fadeAway(root, to: ok ? 0.92 : 0.97, dy: ok ? 40 : 0, duration: ok ? 0.26 : 0.16) { [self] in
      panel.orderOut(nil)
      if !ok { onDecision(ok, why) }
    }
    if ok { onDecision(ok, why) }
  }
}

// MARK: - Control overlay

/// Claude's hold on the real pointer: a terracotta halo around the cursor and a short ember
/// trail behind it. It is the one thing that still reads in a phone-sized clip.
final class CursorHalo {
  let layer = CALayer()
  let halo = CALayer()
  var trail: [CALayer] = []
  var history: [CGPoint] = []
  let screen: NSScreen
  var timer: Timer?
  /// Where the pointer is, in global screen coordinates; the demo supplies a scripted one.
  var source: () -> CGPoint = { NSEvent.mouseLocation }

  init(screen: NSScreen, in host: CALayer) {
    self.screen = screen
    layer.frame = host.bounds
    for i in 0..<14 {
      let d = CALayer()
      let size = 9 - CGFloat(i) * 0.5
      d.bounds = CGRect(x: 0, y: 0, width: size, height: size)
      d.cornerRadius = size / 2
      d.backgroundColor = Palette.ember.cgColor
      d.opacity = 0.75 * (1 - Float(i) / 14)
      layer.addSublayer(d)
      trail.append(d)
    }
    let glow = CALayer()
    glow.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
    glow.position = CGPoint(x: 23, y: 23)
    glow.cornerRadius = 23
    glow.backgroundColor = Palette.accent.cgColor
    glow.opacity = 0.28
    glow.filters = blur(9)
    let ring = CAShapeLayer()
    ring.frame = CGRect(x: 0, y: 0, width: 46, height: 46)
    ring.path = CGPath(ellipseIn: CGRect(x: 9, y: 9, width: 28, height: 28), transform: nil)
    ring.fillColor = nil
    ring.strokeColor = Palette.accent.cgColor
    ring.lineWidth = 2
    halo.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
    halo.addSublayer(glow)
    halo.addSublayer(ring)
    if !reduceMotion {
      let b = CABasicAnimation(keyPath: "transform.scale")
      b.fromValue = 0.92
      b.toValue = 1.08
      b.duration = 0.9
      b.autoreverses = true
      b.repeatCount = .infinity
      b.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      ring.add(b, forKey: "breathe")
    }
    layer.addSublayer(halo)
    layer.opacity = 0
    host.addSublayer(layer)
  }

  func start() {
    let a = CABasicAnimation(keyPath: "opacity")
    a.fromValue = 0
    a.toValue = 1
    a.duration = 0.3
    layer.opacity = 1
    layer.add(a, forKey: "in")
    tick()
    timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    RunLoop.main.add(timer!, forMode: .common)
  }

  func stop() { timer?.invalidate() }

  func tick() {
    let m = source()
    let onScreen = screen.frame.contains(m)
    // Centre the halo on the arrow's body, a little below and right of the hotspot.
    let p = CGPoint(x: m.x - screen.frame.minX + 4, y: m.y - screen.frame.minY - 7)
    history.insert(p, at: 0)
    if history.count > trail.count * 2 { history.removeLast() }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.isHidden = !onScreen
    halo.position = p
    for (i, d) in trail.enumerated() { d.position = history[min(history.count - 1, i * 2)] }
    CATransaction.commit()
  }
}

final class ControlOverlay {
  let window: NSPanel
  let edge: LayerView
  let draws: [CAShapeLayer]
  let cursor: CursorHalo
  let pillBox: LayerView
  let pill: NSView
  let row: NSStackView
  let dot = CALayer()
  let ring = CAShapeLayer()
  let caption: NSTextField
  let endGlyph = NSImageView()
  let esc: NSView

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

    // Screen edge: a terracotta line over a warm inner glow, drawn out from the pill.
    edge = LayerView(frame: root.bounds)
    let b = root.bounds, r: CGFloat = 12
    let glow = CALayer()
    glow.frame = b
    glow.filters = blur(34)
    glow.opacity = 0.3
    let lineRect = b.insetBy(dx: 1.5, dy: 1.5)
    var drawn: [CAShapeLayer] = []
    for half in splitRoundedRect(b, radius: r) {
      let g = stroke(half, b, width: 70, color: Palette.accent)
      glow.addSublayer(g)
      drawn.append(g)
    }
    edge.layer!.addSublayer(glow)
    for half in splitRoundedRect(lineRect, radius: r) {
      let l = stroke(half, b, width: 4, color: Palette.accent)
      edge.layer!.addSublayer(l)
      drawn.append(l)
    }
    draws = drawn
    if !reduceMotion {
      // Bright on arrival, then it settles into a slow breath.
      let settle = CABasicAnimation(keyPath: "opacity")
      settle.fromValue = 0.5
      settle.toValue = 0.3
      settle.duration = 1.2
      settle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      glow.add(settle, forKey: "settle")
      let breathe = CABasicAnimation(keyPath: "opacity")
      breathe.fromValue = 0.3
      breathe.toValue = 0.2
      breathe.beginTime = CACurrentMediaTime() + 1.2
      breathe.duration = 1.8
      breathe.autoreverses = true
      breathe.repeatCount = .infinity
      breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      glow.add(breathe, forKey: "breathe")
    }
    root.addSubview(edge)

    // Pill (ivory, hairline edge, soft shadow): [time ring + dot]  Claude has control  [esc]
    let ringBox = LayerView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    fixedSize(ringBox, 20, 20)
    let track = stroke(CGPath(ellipseIn: ringBox.bounds.insetBy(dx: 1, dy: 1), transform: nil), ringBox.bounds, width: 1.5, color: Palette.hairline)
    ring.frame = ringBox.bounds
    ring.path = CGPath(ellipseIn: ringBox.bounds.insetBy(dx: 1, dy: 1), transform: nil)
    ring.lineWidth = 1.5
    ring.lineCap = .round
    ring.fillColor = nil
    ring.strokeColor = Palette.accent.cgColor
    // Start at 12 o'clock and drain counter-clockwise.
    ring.transform = CATransform3DConcat(CATransform3DMakeScale(-1, 1, 1), CATransform3DMakeRotation(.pi / 2, 0, 0, 1))
    dot.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
    dot.position = CGPoint(x: 10, y: 10)
    dot.cornerRadius = 3.5
    dot.backgroundColor = Palette.accent.cgColor
    if !reduceMotion {
      let pulse = CABasicAnimation(keyPath: "transform.scale")
      pulse.fromValue = 0.8
      pulse.toValue = 1.15
      pulse.duration = 0.9
      pulse.autoreverses = true
      pulse.repeatCount = .infinity
      pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      dot.add(pulse, forKey: "pulse")
    }
    ringBox.layer!.addSublayer(track)
    ringBox.layer!.addSublayer(ring)
    ringBox.layer!.addSublayer(dot)
    endGlyph.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
    endGlyph.frame = ringBox.bounds
    endGlyph.alphaValue = 0
    ringBox.addSubview(endGlyph)

    caption = text("\(agentName) has control", 13, .medium, Palette.ink)
    esc = keycap("esc")
    row = NSStackView(views: [ringBox, caption, esc])
    row.spacing = 10
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false
    let h: CGFloat = 42
    let w = row.fittingSize.width + 28
    let vf = screen.visibleFrame
    // Hangs under the notch: the one spot no app puts its own controls in.
    let pillRect = NSRect(x: root.bounds.midX - w / 2, y: vf.maxY - screen.frame.minY - h - 8, width: w, height: h)
    pillBox = LayerView(frame: pillRect.insetBy(dx: -40, dy: -40))
    pill = surface(NSRect(x: 40, y: 40, width: w, height: h), radius: h / 2)
    pill.addSubview(row)
    NSLayoutConstraint.activate([
      row.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
      row.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
    ])
    pillBox.addSubview(pill)
    root.addSubview(pillBox)
    cursor = CursorHalo(screen: screen, in: root.layer!)
  }

  func show(seconds: Int) {
    window.orderFrontRegardless()
    if !reduceMotion {
      for d in draws {
        let a = CABasicAnimation(keyPath: "strokeEnd")
        a.fromValue = 0
        a.toValue = 1
        a.duration = 0.6
        a.beginTime = CACurrentMediaTime() + 0.15
        a.fillMode = .backwards
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1)
        d.add(a, forKey: "draw")
      }
    }
    springIn(pillBox, from: 0.8, dy: 26)
    cursor.start()
    let a = CABasicAnimation(keyPath: "strokeEnd")
    a.fromValue = 1
    a.toValue = 0
    a.duration = CFTimeInterval(seconds)
    a.fillMode = .forwards
    a.isRemovedOnCompletion = false
    ring.add(a, forKey: "drain")
  }

  /// Finish: the pill says what happened and tightens to fit, the edge and the halo let go,
  /// then everything leaves. `byUser` adds the macOS "no" shake. `then` runs once it is all gone.
  func finish(byUser: Bool, then: @escaping () -> Void) {
    cursor.stop()
    endGlyph.image = NSImage(systemSymbolName: byUser ? "hand.raised.fill" : "checkmark", accessibilityDescription: nil)
    endGlyph.contentTintColor = byUser ? Palette.accent : Palette.ink
    ring.removeAllAnimations()
    ring.opacity = 0
    dot.opacity = 0
    esc.isHidden = true
    // Old words out (0.1 s), then new words in (0.15 s) while the pill tightens to fit.
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.1
      caption.animator().alphaValue = 0
    }, completionHandler: { [self] in
      caption.stringValue = byUser ? "Stopped" : "Back to you"
      let w = row.fittingSize.width + 28
      var f = pill.frame
      f.origin.x += (f.width - w) / 2
      f.size.width = w
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.25
        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        ctx.allowsImplicitAnimation = true
        caption.animator().alphaValue = 1
        endGlyph.animator().alphaValue = 1
        pill.animator().frame = f
      }
    })
    if byUser && !reduceMotion, let l = pillBox.layer {
      let shake = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.x")
      shake.values = [0, -8, 7, -5, 3, -1, 0]
      shake.duration = 0.4
      l.add(shake, forKey: "shake")
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.toValue = 0
    fade.duration = 0.3
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = false
    cursor.layer.add(fade, forKey: "out")
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.45
      edge.animator().alphaValue = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
      fadeAway(pillBox, to: 0.9, dy: -8, duration: 0.22) { [self] in
        window.orderOut(nil)
        then()
      }
    }
  }
}
