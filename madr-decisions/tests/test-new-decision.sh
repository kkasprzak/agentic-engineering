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

# How many lines differ between two files. Not `diff | grep -c '^[<>]'`: BusyBox
# diff only speaks unified, so that counts zero on Alpine and the assertion
# passes vacuously on the one promise this plugin makes. awk needs no agreement
# about output format.
changed_lines() {
  awk 'NR == FNR { a[FNR] = $0; n = FNR; next }
       { if (FNR > n || a[FNR] != $0) c++ }
       END { if (n > FNR) c += n - FNR; print c + 0 }' "$1" "$2"
}

# Bash has no portable timeout, and macOS ships no `timeout(1)`. perl's alarm is
# everywhere and is the only reason a hang shows up as a failure here rather
# than as a test run that never ends.
#
# Without perl the wrapper exits 127, which the hang check below read as neither
# "hung" nor "succeeded" and therefore reported as a pass. A test that reports
# ok when it could not run is worse than one that is missing, so the absence is
# named instead.
have_perl=0
command -v perl >/dev/null 2>&1 && have_perl=1
run_limited() { perl -e 'alarm shift; exec @ARGV' "$@"; }

echo "new-decision.sh"

# --- argument handling ------------------------------------------------------

( workdir
  if [ "$have_perl" -ne 1 ]; then
    printf '  skip a trailing --scope exits instead of hanging (no perl, cannot time out)\n'
  else
    run_limited 5 "$SCRIPT" "Title" --scope >/dev/null 2>&1
    code=$?
    # 142 is death by SIGALRM: the loop never terminated.
    case "$code" in
      142) bad "a trailing --scope exits instead of hanging" "it hung" ;;
      0)   bad "a trailing --scope exits instead of hanging" "it succeeded" ;;
      1|2) ok  "a trailing --scope exits instead of hanging" ;;
      *)   bad "a trailing --scope exits instead of hanging" "unexpected exit $code" ;;
    esac
  fi
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

# --- the skeleton's contents ------------------------------------------------
#
# The README calls the generated skeleton the point of the plugin, and until now
# nothing asserted a single thing about what it contains: a sixth frontmatter
# key, a renamed heading or a non-ISO date would all have passed.

( workdir
  "$SCRIPT" "Shape Check" >/dev/null 2>&1
  f=docs/adr/0000-shape-check.md
  keys=$(awk 'NR==1&&/^---$/{i=1;next} i&&/^---$/{exit} i&&/^[a-z-]+:/{sub(/:.*/,"");print}' "$f" | tr '\n' ' ')
  check "the frontmatter carries MADR's five keys and no sixth" \
        "$keys" "status date decision-makers consulted informed "
  check "status starts at proposed" "$(grep '^status:' "$f")" 'status: "proposed"'
  check "the date is ISO" \
        "$(awk -F': ' '/^date:/{print ($2 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) ? "iso" : $2}' "$f")" \
        "iso"
  # The exact heading structure, not a count: a count survives a rename, and a
  # renamed section is the mutation most likely to go unnoticed.
  check "the headings are MADR's, in order and at the right level" \
        "$(grep -E '^#{2,3} ' "$f" | grep -v '{option' | tr '\n' '|')" \
        "## Context and Problem Statement|## Decision Drivers|## Considered Options|## Decision Outcome|### Consequences|### Confirmation|## Pros and Cons of the Options|## More Information|"
)

# --- --root, which every adopting repository needs and nothing tested --------

( workdir
  "$SCRIPT" --root docs/decisions "Elsewhere" >/dev/null 2>&1
  check "--root puts the record where it says" \
        "$(ls docs/decisions 2>/dev/null)" "0000-elsewhere.md"
  check "and does not create the default root" \
        "$([ -d docs/adr ] && echo yes || echo no)" "no"
)

( workdir
  "$SCRIPT" --root docs/decisions "First"  >/dev/null 2>&1
  "$SCRIPT" --root docs/decisions "Second" >/dev/null 2>&1
  check "--root numbers from what is already there" \
        "$(ls docs/decisions | tr '\n' ' ')" "0000-first.md 0001-second.md "
)

( workdir
  "$SCRIPT" --root /tmp "Absolute" >/dev/null 2>&1
  check "--root refuses an absolute path" "$?" "1"
)

( workdir
  "$SCRIPT" --root ../outside "Climbing" >/dev/null 2>&1
  check "--root refuses to climb out" "$?" "1"
)

( workdir
  mkdir -p docs/adr ../victim
  printf -- '---\nstatus: "accepted"\n---\n' > ../victim/0042-important.md 2>/dev/null
  "$SCRIPT" --supersedes ../../victim/0042 "Traversal" >/dev/null 2>&1
  check "--supersedes refuses a path instead of an id" "$?" "1"
)

# --- the narrowed supersede happy path, only its refusal was covered ---------

( workdir
  "$SCRIPT" --scope chat "Narrow One" >/dev/null 2>&1
  "$SCRIPT" --scope chat --supersedes chat/0000 "Narrow Two" >/dev/null 2>&1
  check "a narrowed record can supersede its own scope" "$?" "0"
  # The identifier must carry the scope, or the chain points at a system record
  # with the same number.
  check "and the written identifier keeps the scope" \
        "$(grep '^status:' docs/adr/chat/0000-narrow-one.md)" \
        'status: "superseded by chat/0001"'
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
  n=$(changed_lines /tmp/before.$$ docs/adr/0000-original.md)
  rm -f /tmp/before.$$
  # The whole promise of the plugin: one line changes, the rest is history.
  check "superseding changes exactly one line" "$n" "1"
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
  # A record saved with CRLF endings. Refusing it as "no frontmatter" would be
  # worse than a plain bug: the guard hook refuses to let such a record be
  # edited, so if the generator also refuses to supersede it, there is no way
  # forward at all.
  printf -- '---\r\nstatus: "accepted"\r\ndate: 2026-01-01\r\n---\r\n\r\n# Old\r\n' \
    > docs/adr/0000-crlf.md
  "$SCRIPT" --supersedes 0000 "Replacement" >/dev/null 2>&1
  check "a CRLF record can be superseded" "$?" "0"
  check "its status was flipped" \
        "$(tr -d '\r' < docs/adr/0000-crlf.md | grep '^status:')" \
        'status: "superseded by 0001"'
  # The replacement line has to carry the ending the rest of the file uses, or
  # one line is out of step with every other and the diff shows two changes.
  check "and keeps the file's CRLF endings" \
        "$(grep -c $'\r$' docs/adr/0000-crlf.md | tr -d ' ')" \
        "$(wc -l < docs/adr/0000-crlf.md | tr -d ' ')"
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
  # chmod does not stop root, so under a root CI container the script would
  # succeed and these three would fail while the script is correct. A suite that
  # cries wolf gets ignored, so probe first and skip rather than assert.
  # The 2>/dev/null comes FIRST: redirections are applied left to right, so with
  # it last the failing `> .probe` has already printed to the real stderr.
  if : 2>/dev/null > docs/adr/.probe; then
    rm -f docs/adr/.probe
    chmod 755 docs/adr
    printf '  skip unwritable-directory case (writes succeed here — running as root?)\n'
  else
    "$SCRIPT" --supersedes 0000 "Replacement" >/dev/null 2>&1
    code=$?
    chmod 755 docs/adr
    # The failure this plugin exists to prevent, in the tool itself: reporting
    # work that did not happen.
    check "an unwritable directory is an error, not a success" "$code" "1"
    check "nothing was half-done" "$(ls docs/adr | wc -l | tr -d ' ')" "1"
    check "the old record was not flipped" \
          "$(grep '^status:' docs/adr/0000-original.md)" 'status: "proposed"'
  fi
)

# NOT COVERED, deliberately and worth saying so rather than implying otherwise:
# the rollback branch, where the new record is written and flipping the old one
# then fails. The case above never reaches it — the new-record write fails first,
# so the script exits before the flip is attempted. Forcing only the flip to fail
# needs a writable directory containing an unwritable rename target, which is not
# portable, and the alternative is a seam in production code that exists solely
# for a test. The branch is three lines and is reviewed by reading.

pass=$(grep -c '^ok$'   "$RESULTS" || true)
fail=$(grep -c '^fail$' "$RESULTS" || true)

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
