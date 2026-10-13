// `ask-control --demo`: a scripted walkthrough of the real card and overlay on a clean stage.
// A drawn cursor plays the agent: it clicks Allow, drags a build toward the notch, and Esc
// stops it halfway. The real mouse and keyboard are never touched, so it's safe to run
// anywhere and to screen-record for a preview.
import AppKit
import QuartzCore
import UniformTypeIdentifiers

final class Demo {
  let screen = mainScreen
  let stage: NSWindow
  let top: NSWindow
  let arrow = CALayer()
  let ghost = CALayer()
  var pos: CGPoint
  var card: ConsentCard!
  var overlay: ControlOverlay?
  var iconCenter = CGPoint.zero
  var tween: Timer?

  init() {
    let f = screen.frame
    func window(level: NSWindow.Level) -> NSWindow {
      let w = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
      w.setFrame(f, display: false)
      w.isOpaque = false
      w.backgroundColor = .clear
      w.ignoresMouseEvents = true
      w.level = level
      w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      w.contentView = LayerView(frame: NSRect(origin: .zero, size: f.size))
      return w
    }
    stage = window(level: .screenSaver)
    top = window(level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2))
    pos = CGPoint(x: f.midX + 260, y: f.minY + f.height * 0.36)

    // Stage: warm paper, and one plain window holding the build to drag.
    let root = stage.contentView!.layer!
    root.backgroundColor = (isDark ? hex(0x1F1E1D) : hex(0xF0EEE6)).cgColor
    let win = CALayer()
    let wr = CGRect(x: f.width / 2 - 520, y: f.height * 0.42, width: 300, height: 210)
    win.frame = wr
    win.backgroundColor = Palette.surface.cgColor
    win.cornerRadius = 12
    win.cornerCurve = .continuous
    win.borderWidth = 1
    win.borderColor = Palette.edge.cgColor
    win.shadowOpacity = 0.12
    win.shadowRadius = 20
    win.shadowOffset = CGSize(width: 0, height: -6)
    for (i, c) in [hex(0xEC6A5E), hex(0xF4BF4F), hex(0x61C554)].enumerated() {
      let d = CALayer()
      d.frame = CGRect(x: 14 + CGFloat(i) * 18, y: wr.height - 22, width: 11, height: 11)
      d.cornerRadius = 5.5
      d.backgroundColor = c.cgColor
      win.addSublayer(d)
    }
    let icon = CALayer()
    icon.frame = CGRect(x: wr.width / 2 - 36, y: 62, width: 72, height: 72)
    icon.contents = NSWorkspace.shared.icon(for: .applicationBundle)
    win.addSublayer(icon)
    let name = CATextLayer()
    name.string = "Build.app"
    name.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    name.fontSize = 12
    name.foregroundColor = Palette.ink.cgColor
    name.alignmentMode = .center
    name.contentsScale = 2
    name.frame = CGRect(x: 0, y: 36, width: wr.width, height: 18)
    win.addSublayer(name)
    root.addSublayer(win)
    iconCenter = CGPoint(x: f.minX + wr.minX + wr.width / 2, y: f.minY + wr.minY + 98)

    // The dragged copy and the drawn pointer live in a window above everything.
    ghost.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
    ghost.contents = icon.contents
    ghost.opacity = 0
    let img = NSCursor.arrow.image
    arrow.bounds = CGRect(origin: .zero, size: img.size)
    arrow.contents = img
    arrow.anchorPoint = CGPoint(x: NSCursor.arrow.hotSpot.x / img.size.width, y: 1 - NSCursor.arrow.hotSpot.y / img.size.height)
    top.contentView!.layer!.addSublayer(ghost)
    top.contentView!.layer!.addSublayer(arrow)
    place()
  }

  func place() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let p = CGPoint(x: pos.x - screen.frame.minX, y: pos.y - screen.frame.minY)
    arrow.position = p
    ghost.position = CGPoint(x: p.x + 18, y: p.y - 22)
    CATransaction.commit()
  }

  /// Glide the pointer to `to` with a soft ease and a slight arc, like a hand would.
  func glide(to: CGPoint, _ duration: Double, then: @escaping () -> Void = {}) {
    let from = pos, start = CACurrentMediaTime()
    let bend = CGPoint(x: (to.y - from.y) * 0.12, y: -(to.x - from.x) * 0.12)
    tween?.invalidate()
    tween = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] t in
      guard let self else { return }
      let k = min(1, (CACurrentMediaTime() - start) / duration)
      let e = k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
      let arc = 4 * e * (1 - e)
      self.pos = CGPoint(x: from.x + (to.x - from.x) * e + bend.x * arc, y: from.y + (to.y - from.y) * e + bend.y * arc)
      self.place()
      if k >= 1 { t.invalidate(); then() }
    }
    RunLoop.main.add(tween!, forMode: .common)
  }

  func at(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }

  /// A keystroke bubble, so a viewer can see the key that was pressed.
  func showKey(_ label: String) {
    let host = top.contentView!
    let k = NSView(frame: NSRect(x: host.bounds.midX - 34, y: host.bounds.height * 0.3, width: 68, height: 42))
    k.wantsLayer = true
    k.layer?.cornerRadius = 10
    k.layer?.cornerCurve = .continuous
    k.layer?.borderWidth = 1
    k.layer?.borderColor = Palette.edge.cgColor
    k.layer?.backgroundColor = (isDark ? hex(0x30302E) : NSColor.white).cgColor
    k.layer?.shadowOpacity = 0.18
    k.layer?.shadowRadius = 12
    k.layer?.shadowOffset = CGSize(width: 0, height: -4)
    let t = text(label, 16, .medium, Palette.ink)
    t.alignment = .center
    t.frame = NSRect(x: 0, y: 11, width: 68, height: 20)
    k.addSubview(t)
    host.addSubview(k)
    springIn(k, from: 0.7, dy: -8)
    at(1.1) { NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; k.animator().alphaValue = 0 }) { k.removeFromSuperview() } }
  }

  func run() {
    stage.alphaValue = 0
    stage.orderFrontRegardless()
    top.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.4; stage.animator().alphaValue = 1 }

    card = ConsentCard(reason: "Drag the new build onto the notch to test the drop animation", seconds: 20, timeout: 60) { [weak self] ok, _ in
      guard let self, ok else { return }
      let o = ControlOverlay()
      o.cursor.source = { [weak self] in self?.pos ?? .zero }
      o.show(seconds: 20)
      self.overlay = o
      self.top.orderFrontRegardless()
      self.dragBuild()
    }
    at(0.7) { self.card.show() }
    at(1.9) {
      let r = self.card.panel.convertToScreen(self.card.allow.convert(self.card.allow.bounds, to: nil))
      self.glide(to: CGPoint(x: r.midX, y: r.midY), 0.9) {
        self.card.allow.highlight(true)
        self.at(0.14) { self.card.allow.highlight(false); self.card.allowClicked() }
      }
    }
  }

  func dragBuild() {
    at(0.5) {
      self.glide(to: self.iconCenter, 0.8) {
        // Pick it up.
        self.ghost.opacity = 0.85
        let pick = CABasicAnimation(keyPath: "transform.scale")
        pick.fromValue = 1.15
        pick.toValue = 1
        pick.duration = 0.2
        self.ghost.add(pick, forKey: "pick")
        let notch = CGPoint(x: self.screen.frame.midX, y: self.screen.frame.maxY - 60)
        self.at(0.25) { self.glide(to: notch, 2.2) }
        // Halfway there, the human presses Esc.
        self.at(1.35) { self.stop() }
      }
    }
  }

  func stop() {
    tween?.invalidate()
    showKey("esc")
    overlay?.finish(byUser: true) {}
    // The build springs back home; the pointer is the human's again.
    let back = CASpringAnimation(keyPath: "position")
    back.fromValue = ghost.position
    back.toValue = CGPoint(x: iconCenter.x - screen.frame.minX, y: iconCenter.y - screen.frame.minY)
    back.stiffness = 180
    back.damping = 18
    back.duration = back.settlingDuration
    ghost.position = back.toValue as! CGPoint
    ghost.add(back, forKey: "home")
    at(0.6) { self.ghost.opacity = 0 }
    at(2.6) {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.4
        self.stage.animator().alphaValue = 0
        self.top.animator().alphaValue = 0
      }
      // Timed, not a completion handler: those never fire while the display sleeps.
      self.at(0.45) { exit(0) }
    }
  }
}
