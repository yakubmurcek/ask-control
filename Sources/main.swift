// ask-control: ask the human before an AI agent drives their Mac's mouse or keyboard.
//
// Shows a native consent prompt (Deny is the default, auto-deny after --timeout s).
// Allow starts a control window of --seconds: a cursor halo, edge line and notch pill, and an
// abort on Esc, any real key press or real mouse movement/click. Real input is told
// apart from synthetic input by the CGEvent source pid (hardware events carry pid 0,
// events posted by a process carry its pid). See README.md for the contract.
import AppKit
import CoreGraphics
import Darwin

// MARK: - State files

let stateDir = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".cache/ask-control")
let stopPath = stateDir.appendingPathComponent("stop").path
let activePath = stateDir.appendingPathComponent("active").path
let logPath = stateDir.appendingPathComponent("log").path

try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

func log(_ msg: String) {
  let line = "\(ISO8601DateFormatter().string(from: Date())) [\(getpid())] \(msg)\n"
  if let h = FileHandle(forWritingAtPath: logPath) {
    h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
  } else {
    FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
  }
}

func say(_ msg: String) { FileHandle.standardError.write("ask-control: \(msg)\n".data(using: .utf8)!) }

func touchStop() { FileManager.default.createFile(atPath: stopPath, contents: nil) }

/// The active file holds "<pid> <until-epoch> <reason>" of the running control window.
func readActive() -> (pid: pid_t, until: TimeInterval)? {
  guard let s = try? String(contentsOfFile: activePath, encoding: .utf8) else { return nil }
  let parts = s.split(separator: " ", maxSplits: 2)
  guard parts.count >= 2, let pid = pid_t(parts[0]), let until = TimeInterval(parts[1]) else { return nil }
  return (pid, until)
}

func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

// MARK: - Arguments

let usage = """
  usage: ask-control "<what and why>" [--seconds N] [--timeout N] [--as NAME] [-- command args...]
         ask-control --status   exit 0 while a control window is open and not stopped
         ask-control --done     end the current control window (also: --stop)
         ask-control --demo     play a scripted preview; touches no input

  Exit codes: 0 allowed (with -- command: the command's own exit code),
              1 denied or no answer, 2 usage error, 3 stopped by the user or time ran out.
  --as NAME:  who is asking, shown as "NAME wants control" (default: Claude).
  Stop-file:  ~/.cache/ask-control/stop exists = stop driving input now.
  """

var args = Array(CommandLine.arguments.dropFirst())
var reason: String?
var seconds = 30
var timeout = 60
var command: [String] = []
var watchMode = false
var demoMode = false
var agentName = "Claude"

if args.first == "--status" {
  if let a = readActive(), alive(a.pid), Date().timeIntervalSince1970 < a.until,
     !FileManager.default.fileExists(atPath: stopPath) { exit(0) }
  exit(1)
}
if args.first == "--done" || args.first == "--stop" {
  touchStop()
  if let a = readActive(), alive(a.pid) { kill(a.pid, SIGTERM) }
  log("\(args[0]) requested")
  exit(0)
}
if let i = args.firstIndex(of: "--") {
  command = Array(args[(i + 1)...]); args = Array(args[..<i])
}
var i = 0
while i < args.count {
  let a = args[i]
  func num() -> Int {
    guard i + 1 < args.count, let n = Int(args[i + 1]), n > 0 else { say("\(a) needs a positive number"); exit(2) }
    i += 1; return n
  }
  switch a {
  case "--seconds": seconds = num()
  case "--timeout": timeout = num()
  case "--as":
    guard i + 1 < args.count, !args[i + 1].isEmpty else { say("--as needs a name"); exit(2) }
    i += 1; agentName = args[i]
  case "--watch": watchMode = true  // internal: the detached banner/abort watcher
  case "--demo": demoMode = true
  case "-h", "--help": print(usage); exit(0)
  default:
    if a.hasPrefix("--") || reason != nil { say("unexpected argument \(a)\n\(usage)"); exit(2) }
    reason = a
  }
  i += 1
}
final class KeyPanel: NSPanel {
  var onCancel: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onCancel?() }
}

let mainScreen = NSScreen.screens.first!  // the screen with the menu bar

if demoMode {
  // A scripted walkthrough of the real UI. Nothing touches the real mouse or keyboard.
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let demo = Demo()
  demo.run()
  app.run()
}
guard let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty else { say("say what and why\n\(usage)"); exit(2) }
if CGSessionCopyCurrentDictionary() == nil { say("no GUI session, denied"); log("DENY no-gui: \(reason)"); exit(1) }



// MARK: - Control window: overlay + abort watcher

final class Session: NSObject {
  let seconds: Int
  let reason: String
  var child: pid_t?
  let until: Date
  let overlay = ControlOverlay()
  var tap: CFMachPort?
  var armedAt: Date
  var moved: Double = 0
  var realKeys = 0  // real key presses the tap saw, logged at the end for diagnosis
  var ended = false
  var timers: [Timer] = []
  var signalSources: [DispatchSourceSignal] = []
  var childSource: DispatchSourceProcess?

  init(seconds: Int, reason: String, child: pid_t?) {
    self.seconds = seconds
    self.reason = reason
    self.child = child
    until = Date().addingTimeInterval(TimeInterval(seconds))
    armedAt = Date().addingTimeInterval(1.5)  // grace: the hand that clicked Allow is still moving
    super.init()
  }

  func start() {
    try? FileManager.default.removeItem(atPath: stopPath)
    try? "\(getpid()) \(Int(until.timeIntervalSince1970)) \(reason)".write(toFile: activePath, atomically: true, encoding: .utf8)
    installTap()
    overlay.show(seconds: seconds)
    timers.append(Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in self?.poll() })
    for sig in [SIGTERM, SIGINT, SIGHUP] {
      signal(sig, SIG_IGN)
      let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      s.setEventHandler { [weak self] in self?.end("ended (signal \(sig))", code: 3, byUser: false) }
      s.resume()
      signalSources.append(s)
    }
    if let child {
      let src = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .main)
      src.setEventHandler { [weak self] in
        var status: Int32 = 0
        waitpid(child, &status, 0)
        let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        self?.child = nil
        self?.end("command finished (exit \(code))", code: code, byUser: false, stop: false)
      }
      src.resume()
      childSource = src
    }
  }

  func poll() {
    if Date() >= until { end("time ran out", code: 3, byUser: false); return }
    if FileManager.default.fileExists(atPath: stopPath) { end("stop-file appeared", code: 3, byUser: false); return }
    // Esc is also polled from the hardware key state: a tap can be created yet get no key
    // events (no Input Monitoring for the responsible app, Secure Keyboard Entry).
    // A synthetic Esc stopping us is fail-safe.
    if CGEventSource.keyState(.hidSystemState, key: 53) { end("stopped by user (Esc, polled)", code: 3, byUser: true) }
  }

  func installTap() {
    let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                .leftMouseDragged, .rightMouseDragged, .scrollWheel, .keyDown]
    let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
    let me = Unmanaged.passUnretained(self).toOpaque()
    tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                            eventsOfInterest: mask, callback: { _, type, event, info in
      let s = Unmanaged<Session>.fromOpaque(info!).takeUnretainedValue()
      s.handle(type, event)
      return Unmanaged.passUnretained(event)
    }, userInfo: me)
    guard let tap else { log("no event tap (Input Monitoring not granted?): Esc polling only"); return }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  func handle(_ type: CGEventType, _ e: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return
    }
    let pid = e.getIntegerValueField(.eventSourceUnixProcessID)
    if pid != 0 { return }  // posted by a process: the control we allowed
    let src = "pid \(pid), state \(e.getIntegerValueField(.eventSourceStateID))"
    if type == .keyDown {
      realKeys += 1
      let key = e.getIntegerValueField(.keyboardEventKeycode)
      end(key == 53 ? "stopped by user (Esc; \(src))" : "stopped by user (key \(key); \(src))", code: 3, byUser: true)
      return
    }
    guard Date() >= armedAt else { return }
    switch type {
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
      moved += abs(e.getDoubleValueField(.mouseEventDeltaX)) + abs(e.getDoubleValueField(.mouseEventDeltaY))
      if moved > 12 { end("stopped by user (mouse moved; \(src))", code: 3, byUser: true) }
    default:
      end("stopped by user (\(type == .scrollWheel ? "scroll" : "click"); \(src))", code: 3, byUser: true)
    }
  }

  func end(_ why: String, code: Int32, byUser: Bool, stop: Bool = true) {
    guard !ended else { return }
    ended = true
    // Input stops at once; only the goodbye animation takes its time.
    if stop { touchStop() }
    if let child { kill(-child, SIGTERM) }  // the wrapped command's own group, never ours
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    log("END \(why) [tap: \(tap == nil ? "none" : "on"), real keys seen: \(realKeys)]: \(reason)")
    say(why)
    timers.forEach { $0.invalidate() }
    if let a = readActive(), a.pid == getpid() { try? FileManager.default.removeItem(atPath: activePath) }
    overlay.finish(byUser: byUser) { [child] in
      if let child, alive(child) { kill(-child, SIGKILL) }
      exit(code)
    }
    // Never let the goodbye animation hold the exit: animation callbacks can stall while
    // the display sleeps, and the agent is blocked on our exit code.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [child] in
      if let child, alive(child) { kill(-child, SIGKILL) }
      exit(code)
    }
  }
}

// MARK: - Spawning

func cStrings(_ a: [String]) -> [UnsafeMutablePointer<CChar>?] { a.map { strdup($0) } + [nil] }

/// Wrapped command in its own process group, so an abort can stop all of it.
func spawnCommand(_ cmd: [String]) -> pid_t? {
  var attr: posix_spawnattr_t?
  posix_spawnattr_init(&attr)
  posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
  posix_spawnattr_setpgroup(&attr, 0)
  var pid: pid_t = 0
  let rc = posix_spawnp(&pid, cmd[0], nil, &attr, cStrings(cmd), environ)
  posix_spawnattr_destroy(&attr)
  if rc != 0 { say("cannot run \(cmd[0]): \(String(cString: strerror(rc)))"); return nil }
  return pid
}

/// Detached watcher (new session, stdio to /dev/null) so the caller's pipe closes and it returns at once.
func spawnWatcher() -> pid_t? {
  var attr: posix_spawnattr_t?
  posix_spawnattr_init(&attr)
  posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
  var fa: posix_spawn_file_actions_t?
  posix_spawn_file_actions_init(&fa)
  for fd: Int32 in [0, 1, 2] { posix_spawn_file_actions_addopen(&fa, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0) }
  let me = Bundle.main.executablePath ?? CommandLine.arguments[0]
  var pid: pid_t = 0
  let rc = posix_spawn(&pid, me, &fa, &attr, cStrings([me, "--watch", "--seconds", String(seconds), "--as", agentName, reason]), environ)
  posix_spawn_file_actions_destroy(&fa)
  posix_spawnattr_destroy(&attr)
  return rc == 0 ? pid : nil
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var session: Session?
var card: ConsentCard?

if watchMode {
  session = Session(seconds: seconds, reason: reason, child: nil)
  session!.start()
} else {
  card = ConsentCard(reason: reason, seconds: seconds, timeout: timeout) { ok, why in
    log("\(ok ? "ALLOW" : "DENY") \(why), \(seconds) s: \(reason)")
    guard ok else { say(why); exit(1) }
    // A new Allow replaces any control window still open.
    if let a = readActive(), alive(a.pid) { kill(a.pid, SIGTERM); usleep(200_000) }
    try? FileManager.default.removeItem(atPath: stopPath)
    if command.isEmpty {
      guard let w = spawnWatcher() else { say("could not start the overlay, denied"); exit(1) }
      // Written here too, so `--status` is right the moment we return 0.
      let until = Int(Date().timeIntervalSince1970) + seconds
      try? "\(w) \(until) \(reason)".write(toFile: activePath, atomically: true, encoding: .utf8)
      say("allowed for \(seconds) s; stop when \(stopPath) exists or `ask-control --status` fails")
      // Let the card finish leaving while the watcher's overlay comes up.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
      return
    }
    guard let pid = spawnCommand(command) else { exit(1) }
    session = Session(seconds: seconds, reason: reason, child: pid)
    session!.start()
  }
  card!.show()
}
app.run()
