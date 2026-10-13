# ask-control

A consent prompt for AI agents that want to use your Mac's mouse and keyboard.

Coding agents can move your cursor and type on your Mac with a ten-line script (CGEvent, cliclick, AppleScript), and that skips every approval screen. ask-control puts a native prompt in front of it. The agent says what it wants to do and for how long. Nothing moves until you click Allow, and Esc or a nudge of the mouse takes your Mac back at once.

- **Asks first.** A card says what the agent wants to do and why. Deny is the default (Return), and it denies on its own after 60 s.
- **Shows it.** While the agent is in control, your pointer wears a terracotta halo with a short ember trail, a thin line traces the screen edge, and a pill under the notch counts down.
- **Stops it.** Press Esc, or move or click the real mouse, and the agent's command is killed. The agent's own synthetic events don't trip it.

## Install

```bash
git clone https://github.com/yakubmurcek/ask-control
cd ask-control && make install   # builds with swiftc into ~/.local/bin
```

You need the Xcode command line tools. It's tested on macOS 27, light mode; the dark-mode colours are set but haven't been looked at yet.

## Tell your agent

Paste this into your `CLAUDE.md` / `AGENTS.md`:

```
Before driving my Mac's mouse or keyboard any way other than your own computer-use
approval (CGEvent, cliclick, osascript keystrokes), run
`ask-control "<what and why>" --seconds N -- <command>` and go ahead only on exit 0.
```

## Use

```bash
# Wrap the command that drives input. ask-control runs it in its own process group
# and kills that group on Esc, real mouse input, or when the time is up.
ask-control "Drag the build onto the notch to test the drop animation" --seconds 30 -- ./drag-test

# Or gate a script that checks the stop-file itself before every event.
ask-control "Fill in the signup form" --seconds 20 || exit 1
[ -e ~/.cache/ask-control/stop ] && exit 3
ask-control --done   # hand control back early
```

| Flag | |
|---|---|
| `--seconds N` | how long control lasts (default 30) |
| `--timeout N` | how long the prompt waits before it denies (default 60) |
| `--as NAME` | who is asking: "NAME wants control" (default Claude) |
| `-- cmd …` | run `cmd` under control and kill it when stopped |
| `--status` | exit 0 while control is active |
| `--done` | end control now |

Exit codes: `0` allowed (or, with `-- cmd`, the command's own exit code), `1` denied or no answer, `2` bad arguments, `3` stopped.

## How it tells you from the agent

A listen-only event tap reads where each input event came from. Events from real hardware have a source process ID of 0. Events an agent posts carry that agent's PID, so the agent's own drags never stop it, while yours do. Esc is also polled from the hardware key state, in case the tap gets no key events (no Input Monitoring permission, or Secure Keyboard Entry is on).

Every allow, deny and stop is logged to `~/.cache/ask-control/log`.

## License

MIT
