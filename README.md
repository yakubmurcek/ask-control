# ask-control

**Make your AI agent ask before it touches your mouse.**

<!-- demo: assets/demo.gif (recorded with the real flow: ask, Allow, the agent drives, Esc) -->

Recently a Claude Code session was testing one of my Mac apps. It wrote a ten-line Swift script, and that script started dragging files across my screen while I was in the middle of typing. It never asked. Computer-use tools have their own approval screens, but a script that posts mouse events from the shell skips every one of them.

ask-control is the step that was missing. Before the agent moves anything, it has to ask, in plain words:

- **It asks.** A small card says what the agent wants to do and for how long. Deny is the default, Return denies, and no answer in 60 seconds also means no.
- **You see it.** While the agent drives, your pointer wears a terracotta halo and a pill under the notch counts down.
- **You take it back.** Press Esc or just move your mouse. The agent's command is killed on the spot.

It's one small Swift binary, with no dependencies and nothing running in the background.

## Install

```bash
git clone https://github.com/yakubmurcek/ask-control
cd ask-control && make install   # builds with swiftc into ~/.local/bin
```

You need macOS and the Xcode command line tools (`xcode-select --install`). Tested on macOS 27.

## Give it to your agent

Paste this into your `CLAUDE.md` or `AGENTS.md`:

```
Before driving my Mac's mouse or keyboard any way other than your own computer-use
approval (CGEvent, cliclick, osascript keystrokes), run
`ask-control "<what and why>" --seconds N -- <command>` and go ahead only on exit 0.
```

That's it. The next time your agent wants to click around, you get the card instead of a surprise.

## Use

```bash
# Wrap the command that drives input. It runs in its own process group,
# and that group is killed on Esc, on real mouse input, or when time is up.
ask-control "Drag the build onto the notch to test the drop animation" --seconds 30 -- ./drag-test

# Or gate a script that checks the stop-file itself before every event.
ask-control "Fill in the signup form" --seconds 20 || exit 1
[ -e ~/.cache/ask-control/stop ] && exit 3
ask-control --done   # hand control back early
```

| Flag | |
|---|---|
| `--seconds N` | how long control lasts (default 30) |
| `--timeout N` | how long the card waits before it denies (default 60) |
| `--as NAME` | who is asking, e.g. `--as Codex` (default Claude) |
| `-- cmd …` | run `cmd` under control and kill it when stopped |
| `--status` | exit 0 while control is active |
| `--done` | end control now |

Exit codes: `0` allowed (with `-- cmd`, the command's own exit code), `1` denied or no answer, `2` bad arguments, `3` stopped.

## How it tells your hand from the agent's

Every input event on macOS records which process posted it. Events from real hardware carry process ID 0. Events from the agent's script carry the script's PID. ask-control listens to the event stream and ignores everything with a PID, so the agent's own drags never stop it, but your first nudge of the mouse does.

Esc is also read straight from the keyboard state, so it still works if the event tap gets no key events (for example, with Secure Keyboard Entry on).

Every allow, deny and stop is logged to `~/.cache/ask-control/log`.

## FAQ

**Doesn't Claude's computer use already ask?** Its own tool does, app by app. Scripts the agent writes and runs through the shell don't go through that tool.

**Can an agent just skip it?** Yes. It's a rule in your agent's instructions, not a sandbox. It makes the polite path one command long and visible to you; it won't stop code that is trying to get around it.

**Does it work with Codex, Cursor and the rest?** Anything that can run a shell command can use it. `--as` changes the name on the card.

**Linux or Windows?** No, macOS only.

## License

MIT
