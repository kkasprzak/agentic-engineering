#!/usr/bin/env bash
# Tests for the spawn-worker scripts, run against a fake cmux that behaves the
# way cmux 0.63.1 does (see fake-cmux/cmux for what it reproduces and why).
#
# Run: agent-crew/tests/test-spawn-worker.sh
#
# Cases marked [bug] name the bead they cover; the main assertion of each failed
# on the code before its fix (a few companions, such as "touches no panel",
# guard against the fix overreaching and passed before as well). Cases marked
# [keep] pin behaviour that has to survive the fixes — the regression check.
# Most of those failed before too, but only because on cmux 0.63 the scripts
# never got past the panel lookup.
#
# clear-worker.sh waits about seven seconds for /clear and /rename to land, so
# the cases that run it are the slow ones.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$HERE/../skills/spawn-worker/scripts" && pwd)"
FAKE_BIN="$HERE/fake-cmux"
for s in spawn-worker check-worker clear-worker retire-worker; do
  [ -x "$SCRIPTS/$s.sh" ] || { echo "not executable: $SCRIPTS/$s.sh" >&2; exit 1; }
done
[ -x "$FAKE_BIN/cmux" ] || { echo "not executable: $FAKE_BIN/cmux" >&2; exit 1; }

# Results go to a file: every case runs in a subshell, and a counter bumped in
# one would never reach this shell — a suite that cannot fail proves nothing.
RESULTS="$(mktemp)"
TMPS="$(mktemp)"
trap 'xargs rm -rf < "$TMPS"; rm -f "$RESULTS" "$TMPS"' EXIT

ok()   { echo ok >> "$RESULTS"; printf '  ok   %s\n' "$1"; }
bad()  { echo fail >> "$RESULTS"; printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }
has()  { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1" "no [$3] in: $(printf '%s' "$2" | head -5)"; fi; }
lacks(){ if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1" "unexpected [$3] in: $(printf '%s' "$2" | head -5)"; else ok "$1"; fi; }

newtmp() { local d; d="$(mktemp -d)"; echo "$d" >> "$TMPS"; (cd "$d" && pwd -P); }

# A fresh fake cmux world: its own panels, its own state dir, its own socket.
setup() {
  W="$(newtmp)"
  export FAKE_CMUX_DIR="$W/cmux"; mkdir -p "$FAKE_CMUX_DIR"
  export AGENT_CREW_STATE_DIR="$W/state"
  export PATH="$FAKE_BIN:$PATH"
  export CMUX_SOCKET_PATH="$W/sock"
  python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$CMUX_SOCKET_PATH"
  unset FAKE_CMUX_LIST
}
panel() { printf '%s\t%s\n' "$1" "$2" >> "$FAKE_CMUX_DIR/panels"; }
panels() { cut -f1 "$FAKE_CMUX_DIR/panels" 2>/dev/null | tr '\n' ' '; }
# The text spawn-worker typed into the panel.
typed() { awk -F'\t' '$1=="send" {print $4}' "$FAKE_CMUX_DIR/calls" 2>/dev/null; }

# A repo with a remote and a worktree whose branch is pushed, so retire's
# "unpushed work" guard has nothing to object to.
clean_worktree() {
  local root; root="$(newtmp)"
  git init -q --bare "$root/origin.git"
  git clone -q "$root/origin.git" "$root/main" 2>/dev/null
  git -C "$root/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$root/main" push -q origin HEAD 2>/dev/null
  mkdir -p "$root/main/.claude/worktrees"
  git -C "$root/main" worktree add -q "$root/main/.claude/worktrees/w1" -b w1
  git -C "$root/main/.claude/worktrees/w1" push -q origin w1 2>/dev/null
  printf '%s' "$root/main/.claude/worktrees/w1"
}

echo "spawn-worker scripts (fake cmux 0.63)"

# --- ae-sc4: --json is a global option on cmux 0.63 -------------------------

( setup; panel surface:7 "✳ w1"
  out="$("$SCRIPTS/check-worker.sh" --name w1 2>&1)"; rc=$?
  check "[bug ae-sc4] check-worker finds a panel that exists" "$rc" 0
  has   "[bug ae-sc4] check-worker prints that panel's screen" "$out" "surface: surface:7"
)

( setup; panel surface:7 "✳ w1"
  out="$("$SCRIPTS/clear-worker.sh" --name w1 2>&1)"; rc=$?
  check "[bug ae-sc4] clear-worker finds a panel that exists" "$rc" 0
  has   "[bug ae-sc4] clear-worker types /clear into it" "$(typed)" "/clear"
)

( setup; panel surface:7 "✳ w1"; panel surface:8 other
  out="$("$SCRIPTS/retire-worker.sh" --name w1 2>&1)"; rc=$?
  check "[bug ae-sc4] retire-worker finds and closes a panel that exists" "$rc" 0
  check "[bug ae-sc4] retire-worker closes only that panel" "$(panels)" "surface:8 "
)

for s in check-worker clear-worker retire-worker; do
  ( setup; panel surface:7 w1; export FAKE_CMUX_LIST=text
    out="$("$SCRIPTS/$s.sh" --name w1 2>&1)"; rc=$?
    check "[bug ae-sc4] $s: unparseable panel list exits 3, not 4" "$rc" 3
    has   "[bug ae-sc4] $s: says the panel list could not be read" "$out" "did not return JSON"
    lacks "[bug ae-sc4] $s: does not claim the panel is missing" "$out" "matches 'w1'"
    lacks "[bug ae-sc4] $s: no Python traceback" "$out" "Traceback"
    check "[bug ae-sc4] $s: touches no panel" "$(typed)$(panels)" "surface:7 "
  )
done

for s in check-worker clear-worker retire-worker; do
  ( setup; panel surface:8 other
    "$SCRIPTS/$s.sh" --name w1 >/dev/null 2>&1; rc=$?
    check "[keep] $s: a panel that is not there still exits 4" "$rc" 4
  )
  ( setup; panel surface:7 "✳ w1"; panel surface:8 "◑ w1"
    out="$("$SCRIPTS/$s.sh" --name w1 2>&1)"; rc=$?
    check "[keep] $s: two matching panels still exit 4" "$rc" 4
    has   "[keep] $s: and both are listed" "$out" "AMBIGUOUS: surface:7"
  )
done

( setup; panel surface:7 "- w1"
  "$SCRIPTS/check-worker.sh" --name w1 >/dev/null 2>&1; rc=$?
  check "[keep] an ASCII-decorated title is a different panel" "$rc" 4
)

# --- ae-k9i: the worker must start in --dir ---------------------------------

( setup; d="$(newtmp)"
  "$SCRIPTS/spawn-worker.sh" --role agent-crew:developer --name w1 --dir "$d" >/dev/null 2>&1; rc=$?
  check "[keep] spawn-worker succeeds" "$rc" 0
  line="$(typed)"
  has   "[bug ae-k9i] the launch line changes into --dir first" "$line" "cd '${d}' && claude "

  # Run the typed line in a shell that starts somewhere else — what cmux 0.63
  # does — with claude stubbed to report where it was started.
  stub="$(newtmp)"; printf '#!/bin/sh\npwd -P\n' > "$stub/claude"; chmod +x "$stub/claude"
  elsewhere="$(newtmp)"
  for sh in bash zsh; do
    command -v "$sh" >/dev/null || { printf '  skip %s not installed\n' "$sh"; continue; }
    got="$(cd "$elsewhere" && PATH="$stub:$PATH" "$sh" -c "$line" 2>&1)"
    check "[bug ae-k9i] under $sh, claude starts in --dir" "$got" "$d"
  done
)

( setup; d="$(newtmp)"; mkdir -p "$d/sub"
  ( cd "$d" && "$SCRIPTS/spawn-worker.sh" --role r --name w1 --dir sub >/dev/null 2>&1 ); rc=$?
  check "[bug ae-k9i] a relative --dir is accepted" "$rc" 0
  has   "[bug ae-k9i] and typed as an absolute path" "$(typed)" "cd '${d}/sub' && "
)

( setup; d="$(newtmp)"; mkdir -p "$d/it's"
  out="$("$SCRIPTS/spawn-worker.sh" --role r --name w1 --dir "$d/it's" 2>&1)"; rc=$?
  check "[bug ae-k9i] a --dir containing a quote is refused" "$rc" 2
  check "[bug ae-k9i] and nothing is opened or typed" "$(typed)$(panels)" ""
)

( setup; d="$(newtmp)"
  out="$("$SCRIPTS/spawn-worker.sh" --role r --name 'w1 --x' --dir "$d" 2>&1)"; rc=$?
  check "[keep] a --name with a space is still refused" "$rc" 2
)

# --- ae-ghb: retire needs the directory cmux no longer reports ---------------

( setup; wt="$(clean_worktree)"
  "$SCRIPTS/spawn-worker.sh" --role r --name w1 --dir "$wt" >/dev/null 2>&1
  out="$("$SCRIPTS/retire-worker.sh" --name w1 2>&1)"; rc=$?
  check "[bug ae-ghb] retire knows the directory spawn was given" "$rc" 0
  has   "[bug ae-ghb] and prints it before closing" "$out" "working directory: ${wt}"
  has   "[bug ae-ghb] and says the worktree was left in place" "$out" "worktree left in place: ${wt}"
  [ -d "$wt" ] && ok "[keep] without --remove-worktree the worktree stays" || bad "[keep] without --remove-worktree the worktree stays"
)

( setup; wt="$(clean_worktree)"
  "$SCRIPTS/spawn-worker.sh" --role r --name w1 --dir "$wt" >/dev/null 2>&1
  # From a directory outside that repository, which is where a coordinator
  # usually is: removal used to resolve against the caller's directory.
  out="$(cd "$(newtmp)" && "$SCRIPTS/retire-worker.sh" --name w1 --remove-worktree 2>&1)"; rc=$?
  check "[bug ae-ghb] --remove-worktree removes a clean worktree" "$rc" 0
  has   "[bug ae-ghb] and says so" "$out" "removed worktree ${wt}"
  [ -d "$wt" ] && bad "[bug ae-ghb] the directory is gone" "still there: $wt" || ok "[bug ae-ghb] the directory is gone"
  check "[bug ae-ghb] the panel is closed" "$(panels)" ""
)

( setup; wt="$(clean_worktree)"; echo x > "$wt/scratch"
  "$SCRIPTS/spawn-worker.sh" --role r --name w1 --dir "$wt" >/dev/null 2>&1
  out="$("$SCRIPTS/retire-worker.sh" --name w1 --remove-worktree 2>&1)"; rc=$?
  check "[keep] a worktree holding work is not removed (exit 5)" "$rc" 5
  has   "[keep] and the work is named" "$out" "scratch"
  [ -d "$wt" ] && ok "[keep] the worktree is still there" || bad "[keep] the worktree is still there"
)

( setup; panel surface:7 w1
  out="$("$SCRIPTS/retire-worker.sh" --name w1 --remove-worktree 2>&1)"; rc=$?
  check "[bug ae-ghb] --remove-worktree with no known directory fails" "$rc" 7
  has   "[bug ae-ghb] and says why" "$out" "no working directory is recorded"
  check "[bug ae-ghb] and closes nothing" "$(panels)" "surface:7 "
)

( setup; panel surface:7 w1
  out="$("$SCRIPTS/retire-worker.sh" --name w1 2>&1)"; rc=$?
  check "[keep] retire without --remove-worktree still closes an unrecorded panel" "$rc" 0
  has   "[keep] reporting the directory as unknown" "$out" "working directory: unknown"
)

( setup; wt="$(clean_worktree)"
  "$SCRIPTS/spawn-worker.sh" --role r --name w1 --dir "$wt" >/dev/null 2>&1
  # The recorded panel went away and another one now carries the name: the
  # record describes a different worker and must not steer a deletion.
  : > "$FAKE_CMUX_DIR/panels"; panel surface:50 w1
  out="$("$SCRIPTS/retire-worker.sh" --name w1 --remove-worktree 2>&1)"; rc=$?
  check "[bug ae-ghb] a record for another surface is not trusted" "$rc" 7
  [ -d "$wt" ] && ok "[bug ae-ghb] and that worktree is left alone" || bad "[bug ae-ghb] and that worktree is left alone"
)

( setup; wt="$(clean_worktree)"
  "$SCRIPTS/spawn-worker.sh" --role r --name w1 --dir "$wt" >/dev/null 2>&1
  "$SCRIPTS/retire-worker.sh" --name w1 >/dev/null 2>&1
  left="$(ls -A "$AGENT_CREW_STATE_DIR" 2>/dev/null)"
  check "[bug ae-ghb] retiring drops the record" "$left" ""
)

pass="$(grep -c '^ok$' "$RESULTS")"; fail="$(grep -c '^fail$' "$RESULTS")"
echo
echo "${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
