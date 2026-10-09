#!/usr/bin/env bash
# Tests for new-decision.sh.
#
# Run: madr-decisions/tests/test-new-decision.sh
#
# Every case here fails on the code that existed before it was written. A test
# that passes with and without the fix reads as coverage while proving nothing,
# which is worse than having none — so each assertion names the behaviour it
# would have caught.
#
# Each case runs in its own temporary directory, so they cannot see each other's
# records and the numbering in one does not shift the numbering in another.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../skills/record-decision/scripts" && pwd)/new-decision.sh"
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }

# Results go to a file rather than to shell variables. Each case below runs in
# its own subshell for the working directory, and a counter incremented there
# never reaches the parent — the first draft of this file printed twenty-one
# green lines and then "0 passed, 0 failed", which would have exited 0 on a real
# failure too. A suite that cannot fail is worse than no suite.
RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT

ok()   { echo ok >> "$RESULTS"; printf '  ok   %s\n' "$1"; }
bad()  { echo fail >> "$RESULTS"; printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }

workdir() { cd "$(mktemp -d)" || exit 1; }

# Bash has no portable timeout, and macOS ships no `timeout(1)`. perl's alarm is
# everywhere and is the only reason a hang shows up as a failure here rather
# than as a test run that never ends.
run_limited() { perl -e 'alarm shift; exec @ARGV' "$@"; }

echo "new-decision.sh"

# --- argument handling ------------------------------------------------------

( workdir
  run_limited 5 "$SCRIPT" "Title" --scope >/dev/null 2>&1
  code=$?
  # 142 is death by SIGALRM: the loop never terminated.
  if [ "$code" -eq 142 ]; then bad "a trailing --scope exits instead of hanging" "it hung"
  elif [ "$code" -eq 0 ]; then bad "a trailing --scope exits instead of hanging" "it succeeded"
  else ok "a trailing --scope exits instead of hanging"; fi
)

( workdir
  "$SCRIPT" --scope ../escape "Title" >/dev/null 2>&1
  check "--scope may not climb out of the root" "$?" "1"
  # `docs/adr/../escape` resolves to `docs/escape` — outside the ADR root, which
  # is the thing that must not happen. Checking for `../escape` instead would
  # pass against the unfixed script for the wrong reason.
  if [ -e docs/escape ]; then bad "nothing is written outside the root" "docs/escape exists"
  else ok "nothing is written outside the root"; fi
)

( workdir
  "$SCRIPT" --scope chat/sub "Title" >/dev/null 2>&1
  check "--scope may not build a third tier" "$?" "1"
)

( workdir
  "$SCRIPT" --unknown "Title" >/dev/null 2>&1
  check "an unknown option is refused" "$?" "1"
)

( workdir
  "$SCRIPT" >/dev/null 2>&1
  check "a missing title is refused" "$?" "1"
)

# --- generating -------------------------------------------------------------

( workdir
  "$SCRIPT" "First Decision"  >/dev/null 2>&1
  "$SCRIPT" "Second Decision" >/dev/null 2>&1
  check "numbering increments" "$(ls docs/adr | tr '\n' ' ')" \
        "0000-first-decision.md 0001-second-decision.md "
)

( workdir
  "$SCRIPT" "System One" >/dev/null 2>&1
  "$SCRIPT" --scope chat "Chat One" >/dev/null 2>&1
  # Per-directory numbering: the narrowed record starts its own sequence.
  check "numbering is per directory" "$(ls docs/adr/chat)" "0000-chat-one.md"
)

( workdir
  "$SCRIPT" "Ünicode & Punctuation!" >/dev/null 2>&1
  check "the slug drops punctuation" "$(ls docs/adr)" "0000-nicode-punctuation.md"
)

( workdir
  before=$(ls 2>/dev/null)
  "$SCRIPT" --print "Nothing Written" >/dev/null 2>&1
  check "--print writes no file" "$(ls 2>/dev/null)" "$before"
)

# --- superseding ------------------------------------------------------------

( workdir
  "$SCRIPT" "Original" >/dev/null 2>&1
  cp docs/adr/0000-original.md /tmp/before.$$
  "$SCRIPT" --supersedes 0000 "Replacement" >/dev/null 2>&1
  diffcount=$(diff /tmp/before.$$ docs/adr/0000-original.md | grep -c '^[<>]')
  rm -f /tmp/before.$$
  # The whole promise of the plugin: one line changes, the rest is history.
  check "superseding changes exactly one line" "$diffcount" "2"
)

( workdir
  "$SCRIPT" "Original" >/dev/null 2>&1
  "$SCRIPT" --supersedes 0000 "Second" >/dev/null 2>&1
  "$SCRIPT" --supersedes 0000 "Third"  >/dev/null 2>&1
  code=$?
  check "re-superseding a superseded record is refused" "$code" "2"
  check "the first chain link survives the refusal" \
        "$(grep '^status:' docs/adr/0000-original.md)" 'status: "superseded by 0001"'
)

( workdir
  "$SCRIPT" "System Wide" >/dev/null 2>&1
  "$SCRIPT" --scope chat --supersedes 0000 "Narrowed" >/dev/null 2>&1
  check "a narrowed record may not supersede a system one" "$?" "2"
)

( workdir
  "$SCRIPT" --supersedes 0099 "No Such Target" >/dev/null 2>&1
  check "a missing supersede target is refused" "$?" "2"
)

( workdir
  mkdir -p docs/adr
  printf 'no frontmatter here\n' > docs/adr/0000-bare.md
  "$SCRIPT" --supersedes 0000 "Replacement" >/dev/null 2>&1
  check "a record without frontmatter is refused" "$?" "2"
)

( workdir
  mkdir -p docs/adr
  # `status:` in the body, none in the frontmatter. The rewrite must not reach
  # into the prose looking for one.
  printf -- '---\ndate: 2026-01-01\n---\n\n# Example\n\n```yaml\nstatus: "example"\n```\n' \
    > docs/adr/0000-body-status.md
  "$SCRIPT" --supersedes 0000 "Replacement" >/dev/null 2>&1
  check "a status line in the body is not mistaken for frontmatter" "$?" "2"
  check "the body is left alone" \
        "$(grep -c 'status: "example"' docs/adr/0000-body-status.md)" "1"
)

# --- failure is reported as failure -----------------------------------------

( workdir
  "$SCRIPT" "Original" >/dev/null 2>&1
  chmod 555 docs/adr
  "$SCRIPT" --supersedes 0000 "Replacement" >/dev/null 2>&1
  code=$?
  chmod 755 docs/adr
  # The failure this plugin exists to prevent, in the tool itself: reporting
  # work that did not happen.
  check "an unwritable directory is an error, not a success" "$code" "1"
  check "nothing was half-done" "$(ls docs/adr | wc -l | tr -d ' ')" "1"
  check "the old record was not flipped" \
        "$(grep '^status:' docs/adr/0000-original.md)" 'status: "proposed"'
)

pass=$(grep -c '^ok$'   "$RESULTS" || true)
fail=$(grep -c '^fail$' "$RESULTS" || true)

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
