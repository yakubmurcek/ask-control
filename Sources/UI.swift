// ask-control visuals, in Claude's palette: warm ivory, one terracotta accent, a serif title.
// The motif is a small light that circles: around the consent card while it waits, and
// around the screen edge while the agent has control. Pure Core Animation, no assets.
// Honours Reduce Motion (no orbit, no springs, no ripples) and light/dark appearance.
import AppKit
import QuartzCore
import CoreImage

let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
}

/// Claude's colours, resolved once for the current appearance.
enum Palette {
  static let accent = hex(0xD97757)                          // terracotta
  static let accentDeep = hex(0xC6613F)                      // pressed / hover
  static let ember = hex(0xF2A07B)                           // the circling light
  static let surface = isDark ? hex(0x262624) : hex(0xFAF9F5)  // ivory
  static let hairline = isDark ? hex(0x3D3C38) : hex(0xE8E6DC)
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

func roundedPerimeter(_ r: CGRect, _ radius: CGFloat) -> CGFloat {
  2 * (r.width + r.height) - 8 * radius + 2 * .pi * radius
}

/// A short bright segment that travels around `path` forever: a crisp core plus a soft halo.
func comet(_ path: CGPath, frame: CGRect, perimeter: CGFloat, length: CGFloat, width: CGFloat, period: CFTimeInterval) -> CALayer {
  let box = CALayer()
  box.frame = frame
  for (w, r, o, c) in [(width * 5, width * 3, Float(0.55), Palette.accent), (width, 0, Float(1), Palette.ember)] {
    let s = stroke(path, frame, width: w, color: c)
    s.lineDashPattern = [NSNumber(value: Double(length)), NSNumber(value: Double(perimeter))]
    s.opacity = o
    if r > 0 { s.filters = blur(r) }
    if !reduceMotion {
      let a = CABasicAnimation(keyPath: "lineDashPhase")
      a.fromValue = 0
      a.toValue = -(perimeter + length)
      a.duration = period
      a.repeatCount = .infinity
      s.add(a, forKey: "orbit")
    }
    box.addSublayer(s)
  }
  if reduceMotion { box.opacity = 0 }
  return box
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
func keycap(_ label: String) -> NSView {
  let k = NSView()
  k.wantsLayer = true
  k.layer?.cornerRadius = 5
  k.layer?.cornerCurve = .continuous
  k.layer?.borderWidth = 1
  k.layer?.borderColor = Palette.hairline.cgColor
  k.layer?.backgroundColor = (isDark ? hex(0x30302E) : NSColor.white).cgColor
  let t = text(label, 10.5, .medium, Palette.muted)
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
  let primary: Bool
  var hovering = false { didSet { needsDisplay = true } }

  init(_ title: String, primary: Bool) {
    self.primary = primary
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    attributedTitle = NSAttributedString(string: title, attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: primary ? NSColor.white : Palette.ink,
    ])
    fixedSize(self, primary ? 84 : 72, 30)
  }
  required init?(coder: NSCoder) { fatalError() }

  override func draw(_ dirty: NSRect) {
    let r = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
    if primary {
      (isHighlighted || hovering ? Palette.accentDeep : Palette.accent).setFill()
      path.fill()
    } else {
      (isHighlighted ? Palette.hairline : hovering ? Palette.hairline.withAlphaComponent(0.5) : .clear).setFill()
      path.fill()
      Palette.hairline.setStroke()
      path.lineWidth = 1
      path.stroke()
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
func surface(_ frame: NSRect, radius: CGFloat) -> NSView {
  let v = NSView(frame: frame)
  v.wantsLayer = true
  v.layer?.backgroundColor = Palette.surface.cgColor
  v.layer?.cornerRadius = radius
  v.layer?.cornerCurve = .continuous
  v.layer?.borderWidth = 1
  v.layer?.borderColor = Palette.hairline.cgColor
  v.layer?.shadowColor = NSColor.black.cgColor
  v.layer?.shadowOpacity = isDark ? 0.5 : 0.14
  v.layer?.shadowRadius = 24
  v.layer?.shadowOffset = CGSize(width: 0, height: -8)
  return v
}

// MARK: - Consent card

final class ConsentCard: NSObject {
  let panel: KeyPanel
  let root: LayerView
  let allow = FlatButton("Allow", primary: true)
  let deny = FlatButton("Deny", primary: false)
  let drain = CAShapeLayer()
  let timeout: Int
  var decided = false
  var timer: Timer?
  let onDecision: (Bool, String) -> Void

  init(reason: String, seconds: Int, timeout: Int, onDecision: @escaping (Bool, String) -> Void) {
    self.timeout = timeout
    self.onDecision = onDecision
    let width: CGFloat = 372, margin: CGFloat = 48, radius: CGFloat = 18, inset: CGFloat = 26
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
    let line = LayerView(frame: NSRect(x: 0, y: 0, width: lineW, height: 1))
    fixedSize(line, lineW, 1)
    line.layer!.backgroundColor = Palette.hairline.cgColor
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0.5))
    p.addLine(to: CGPoint(x: lineW, y: 0.5))
    drain.path = p
    drain.frame = line.bounds
    drain.lineWidth = 1
    drain.strokeColor = Palette.accent.cgColor
    line.layer!.addSublayer(drain)

    let meta = NSStackView(views: [text(seconds < 120 ? "\(seconds) s" : "\(seconds / 60) min", 12, .regular, Palette.faint),
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
    // The circling light rides the card's own edge.
    let orbit = LayerView(frame: root.bounds)
    let edge = CGPath(roundedRect: cardRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
    orbit.layer!.addSublayer(comet(edge, frame: root.bounds, perimeter: roundedPerimeter(cardRect, radius),
                                   length: 70, width: 1.5, period: 3.2))
    root.addSubview(orbit)
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
    // Allowed: the card sinks toward where the control pill appears. Denied: it just recedes.
    fadeAway(root, to: ok ? 0.9 : 0.97, dy: ok ? -40 : 0, duration: ok ? 0.26 : 0.16) { [self] in
      panel.orderOut(nil)
      onDecision(ok, why)
    }
  }
}

// MARK: - Control overlay

final class ControlOverlay {
  let window: NSPanel
  let edge: LayerView
  let draws: [CAShapeLayer]
  let pillBox: LayerView
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

    // Screen edge: a warm inner glow, a fine terracotta line, and the light circling it.
    edge = LayerView(frame: root.bounds)
    let b = root.bounds, r: CGFloat = 12
    let glow = CALayer()
    glow.frame = b
    glow.filters = blur(34)
    glow.opacity = 0.32
    let lineRect = b.insetBy(dx: 1.5, dy: 1.5)
    var drawn: [CAShapeLayer] = []
    for half in splitRoundedRect(b, radius: r) {
      let g = stroke(half, b, width: 70, color: Palette.accent)
      glow.addSublayer(g)
      drawn.append(g)
    }
    edge.layer!.addSublayer(glow)
    for half in splitRoundedRect(lineRect, radius: r) {
      let l = stroke(half, b, width: 3, color: Palette.accent)
      edge.layer!.addSublayer(l)
      drawn.append(l)
    }
    draws = drawn
    let loop = CGPath(roundedRect: lineRect, cornerWidth: r, cornerHeight: r, transform: nil)
    let orbiting = comet(loop, frame: b, perimeter: roundedPerimeter(lineRect, r), length: 260, width: 3, period: 6)
    orbiting.opacity = 0
    edge.layer!.addSublayer(orbiting)
    if !reduceMotion {
      let breathe = CABasicAnimation(keyPath: "opacity")
      breathe.fromValue = 0.32
      breathe.toValue = 0.18
      breathe.duration = 1.8
      breathe.autoreverses = true
      breathe.repeatCount = .infinity
      breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      glow.add(breathe, forKey: "breathe")
      let appear = CABasicAnimation(keyPath: "opacity")
      appear.fromValue = 0
      appear.toValue = 1
      appear.beginTime = CACurrentMediaTime() + 0.8
      appear.duration = 0.4
      appear.fillMode = .both
      appear.isRemovedOnCompletion = false
      orbiting.add(appear, forKey: "appear")
    }
    root.addSubview(edge)

    // Pill: [time ring + dot]  Claude has control  [esc]
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
    endGlyph.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
    endGlyph.frame = ringBox.bounds
    endGlyph.alphaValue = 0
    ringBox.addSubview(endGlyph)

    caption = text("\(agentName) has control", 13, .medium, Palette.ink)
    esc = keycap("esc")
    let row = NSStackView(views: [ringBox, caption, esc])
    row.spacing = 10
    row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
    let size = NSSize(width: row.fittingSize.width, height: 40)
    let vf = screen.visibleFrame
    let origin = NSPoint(x: root.bounds.midX - size.width / 2, y: vf.minY - screen.frame.minY + 28)
    pillBox = LayerView(frame: NSRect(x: origin.x - 40, y: origin.y - 40, width: size.width + 80, height: size.height + 80))
    let pill = surface(NSRect(x: 40, y: 40, width: size.width, height: size.height), radius: size.height / 2)
    row.frame = pill.bounds
    pill.addSubview(row)
    pillBox.addSubview(pill)
    root.addSubview(pillBox)
  }

  func show(seconds: Int) {
    window.orderFrontRegardless()
    if !reduceMotion {
      for d in draws {
        let a = CABasicAnimation(keyPath: "strokeEnd")
        a.fromValue = 0
        a.toValue = 1
        a.duration = 0.8
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        d.add(a, forKey: "draw")
      }
    }
    springIn(pillBox, from: 0.85, dy: -16, delay: 0.1)
    let a = CABasicAnimation(keyPath: "strokeEnd")
    a.fromValue = 1
    a.toValue = 0
    a.duration = CFTimeInterval(seconds)
    a.fillMode = .forwards
    a.isRemovedOnCompletion = false
    ring.add(a, forKey: "drain")
  }

  /// Finish: the pill says what happened, the edge lets go, then everything leaves.
  /// `byUser` adds the macOS "no" shake. `then` runs once it is all gone.
  func finish(byUser: Bool, then: @escaping () -> Void) {
    endGlyph.image = NSImage(systemSymbolName: byUser ? "hand.raised.fill" : "checkmark", accessibilityDescription: nil)
    endGlyph.contentTintColor = byUser ? Palette.accent : Palette.ink
    let swap = CATransition()
    swap.type = .fade
    swap.duration = 0.18
    caption.layer?.add(swap, forKey: "swap")
    caption.stringValue = byUser ? "Stopped" : "Back to you"
    ring.removeAllAnimations()
    ring.opacity = 0
    dot.opacity = 0
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.18
      endGlyph.animator().alphaValue = 1
      esc.animator().alphaValue = 0
    }
    if byUser && !reduceMotion, let l = pillBox.layer {
      let shake = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.x")
      shake.values = [0, -8, 7, -5, 3, -1, 0]
      shake.duration = 0.4
      l.add(shake, forKey: "shake")
    }
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
