#!/bin/bash
# Exit-code contract of ask-control, for every path that ends before the consent card.
# Nothing here shows a card or touches input, and state lives in a throwaway directory,
# never in ~/.cache/ask-control, so a real control window elsewhere is never stopped.
# Usage: tests/test.sh [path/to/ask-control]
set -u
BIN="$(cd "$(dirname "${1:-./ask-control}")" && pwd)/$(basename "${1:-./ask-control}")"
export ASK_CONTROL_DIR="$(mktemp -d)"
trap 'rm -rf "$ASK_CONTROL_DIR"; [ -n "${SLEEPER:-}" ] && kill "$SLEEPER" 2>/dev/null' EXIT
pass=0 fail=0

check() {  # check <name> <expected exit> <args...>
  local name=$1 want=$2; shift 2
  "$BIN" "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name: exit $got, want $want"; fi
}

now=$(date +%s)
sleep 60 & SLEEPER=$!; disown
active() { echo "$1 $2 test window" > "$ASK_CONTROL_DIR/active"; }

check "--help prints usage"            0 --help
check "unknown flag"                   2 --bogus "x"
check "two reasons"                    2 "one" "two"
check "--seconds needs a number"       2 --seconds abc "x"
check "--seconds must be positive"     2 --seconds 0 "x"
check "--timeout must be positive"     2 --timeout -5 "x"
check "--as needs a name"              2 "x" --as ""
check "no reason"                      2 --seconds 5
check "blank reason"                   2 "   "
check "blank reason with a command"    2 " " -- /usr/bin/true

rm -f "$ASK_CONTROL_DIR/active" "$ASK_CONTROL_DIR/stop"
check "--status with no window"        1 --status
active "$SLEEPER" $((now + 60))
check "--status while a window is open" 0 --status
active "$SLEEPER" $((now - 1))
check "--status after time ran out"    1 --status
active 999999 $((now + 60))
check "--status when its owner is gone" 1 --status

active "$SLEEPER" $((now + 60))
check "--done"                         0 --done
[ -e "$ASK_CONTROL_DIR/stop" ] && { pass=$((pass + 1)); echo "ok   --done writes the stop-file"; } \
  || { fail=$((fail + 1)); echo "FAIL --done wrote no stop-file"; }
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$SLEEPER" 2>/dev/null || break; sleep 0.1; done
kill -0 "$SLEEPER" 2>/dev/null && { fail=$((fail + 1)); echo "FAIL --done left the window's process running"; } \
  || { pass=$((pass + 1)); echo "ok   --done ends the window's process"; }
check "--status after --done"          1 --status
check "--stop is --done"               0 --stop

grep -q "requested" "$ASK_CONTROL_DIR/log" && { pass=$((pass + 1)); echo "ok   the log is written to ASK_CONTROL_DIR"; } \
  || { fail=$((fail + 1)); echo "FAIL no log in ASK_CONTROL_DIR"; }

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
