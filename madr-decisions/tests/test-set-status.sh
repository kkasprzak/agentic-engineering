#!/usr/bin/env bash
# Tests for set-status.sh.
#
# Run: madr-decisions/tests/test-set-status.sh
#
# Two things matter most here and they pull against each other. The script has
# to make the moves a lifecycle actually needs, or people edit records by hand
# and the guard protects nothing. And it has to refuse everything else, because
# the status is what the guard reads: a wrong move either locks a draft or
# reopens history.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NEW="$HERE/../skills/record-decision/scripts/new-decision.sh"
SET="$HERE/../skills/record-decision/scripts/set-status.sh"
[ -x "$SET" ] || { echo "not executable: $SET" >&2; exit 1; }

RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT

ok()   { echo ok   >> "$RESULTS"; printf '  ok   %s\n' "$1"; }
bad()  { echo fail >> "$RESULTS"; printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }

workdir() { cd "$(mktemp -d)" || exit 1; }

# Not `diff | grep -c '^[<>]'`: BusyBox diff is unified-only, so that counts
# zero on Alpine and the one-line promise passes vacuously.
changed_lines() {
  awk 'NR == FNR { a[FNR] = $0; n = FNR; next }
       { if (FNR > n || a[FNR] != $0) c++ }
       END { if (n > FNR) c += n - FNR; print c + 0 }' "$1" "$2"
}

status_of() { awk 'NR==1&&/^---$/{i=1;next} i&&/^---$/{exit} i&&/^status:/{print;exit}' "$1"; }

# Bash has no portable timeout and macOS ships no `timeout(1)`. Without this a
# regression in argument handling hangs the suite forever instead of failing it,
# and a missing perl has to read as a skip rather than a pass.
have_perl=0
command -v perl >/dev/null 2>&1 && have_perl=1
run_limited() { perl -e 'alarm shift; exec @ARGV' "$@"; }

echo "set-status.sh"

# --- the moves a lifecycle needs --------------------------------------------

( workdir
  "$NEW" "A Decision" >/dev/null 2>&1
  "$SET" 0000 accepted >/dev/null 2>&1
  check "proposed becomes accepted" "$?" "0"
  check "and the status says so" "$(status_of docs/adr/0000-a-decision.md)" 'status: "accepted"'
)

( workdir
  "$NEW" "A Proposal" >/dev/null 2>&1
  "$SET" 0000 rejected >/dev/null 2>&1
  check "proposed becomes rejected" "$?" "0"
)

( workdir
  "$NEW" "Old Rule" >/dev/null 2>&1
  "$SET" 0000 accepted  >/dev/null 2>&1
  "$SET" 0000 deprecated >/dev/null 2>&1
  check "accepted becomes deprecated" "$?" "0"
)

( workdir
  "$NEW" --scope chat "Narrow" >/dev/null 2>&1
  "$SET" chat/0000 accepted >/dev/null 2>&1
  check "a narrowed record moves by its scoped id" "$?" "0"
  check "and it is the narrowed one that moved" \
        "$(status_of docs/adr/chat/0000-narrow.md)" 'status: "accepted"'
)

# --- everything else is refused ---------------------------------------------

( workdir
  "$NEW" "Settled" >/dev/null 2>&1
  "$SET" 0000 accepted >/dev/null 2>&1
  "$SET" 0000 proposed >/dev/null 2>&1
  check "an accepted record cannot be reopened" "$?" "2"
  check "and it did not move" "$(status_of docs/adr/0000-settled.md)" 'status: "accepted"'
)

( workdir
  "$NEW" "Declined" >/dev/null 2>&1
  "$SET" 0000 rejected >/dev/null 2>&1
  "$SET" 0000 accepted >/dev/null 2>&1
  check "a rejected record cannot be accepted later" "$?" "2"
)

( workdir
  "$NEW" "Retired" >/dev/null 2>&1
  "$SET" 0000 accepted   >/dev/null 2>&1
  "$SET" 0000 deprecated >/dev/null 2>&1
  "$SET" 0000 accepted   >/dev/null 2>&1
  check "a deprecated record cannot be un-deprecated" "$?" "2"
)

( workdir
  "$NEW" "Replaced" >/dev/null 2>&1
  "$SET" 0000 accepted >/dev/null 2>&1
  "$NEW" --supersedes 0000 "Replacement" >/dev/null 2>&1
  "$SET" 0000 deprecated >/dev/null 2>&1
  check "a superseded record is not moved by hand" "$?" "2"
)

( workdir
  "$NEW" "Manual" >/dev/null 2>&1
  # Accepted first: only an accepted record can be superseded, so the refusal
  # below has to be about "superseded is not a status you set", not about the
  # record still being a draft — which would print a different hint.
  "$SET" 0000 accepted >/dev/null 2>&1
  out=$("$SET" 0000 "superseded by 0001" 2>&1)
  code=$?
  check "superseded is not a status you set" "$code" "2"
  case "$out" in
    *--supersedes*) ok "and the refusal points at --supersedes" ;;
    *) bad "and the refusal points at --supersedes" "it did not" ;;
  esac
)

( workdir
  mkdir -p docs/notes
  printf -- '---\nstatus: published\n---\n' > docs/notes/0009-post.md
  "$SET" --root docs/notes 0009 accepted >/dev/null 2>&1
  check "a file with a non-MADR status is not a record" "$?" "2"
  check "and it was left alone" \
        "$(grep -c 'status: published' docs/notes/0009-post.md | tr -d ' ')" "1"
)

# --- what it must not disturb ------------------------------------------------

( workdir
  "$NEW" "Untouched" >/dev/null 2>&1
  cp docs/adr/0000-untouched.md /tmp/before.$$
  "$SET" 0000 accepted >/dev/null 2>&1
  n=$(changed_lines /tmp/before.$$ docs/adr/0000-untouched.md)
  rm -f /tmp/before.$$
  # Same discipline as superseding: the status line and nothing else.
  check "a status change rewrites exactly one line" "$n" "1"
)

( workdir
  "$NEW" "Dated" >/dev/null 2>&1
  before=$(grep '^date:' docs/adr/0000-dated.md)
  "$SET" 0000 accepted >/dev/null 2>&1
  check "the date is not touched" "$(grep '^date:' docs/adr/0000-dated.md)" "$before"
)

( workdir
  mkdir -p docs/adr
  # A `status:` line in the body must not be mistaken for the record's state,
  # and must not be rewritten.
  printf -- '---\nstatus: "proposed"\ndate: 2026-01-01\n---\n\n```yaml\nstatus: "accepted"\n```\n' \
    > docs/adr/0000-fenced.md
  "$SET" 0000 accepted >/dev/null 2>&1
  check "the body's status line survives" \
        "$(grep -c 'status: "accepted"' docs/adr/0000-fenced.md | tr -d ' ')" "2"
)

( workdir
  mkdir -p docs/adr
  printf -- '---\r\nstatus: "proposed"\r\ndate: 2026-01-01\r\n---\r\n\r\n# T\r\n' \
    > docs/adr/0000-crlf.md
  "$SET" 0000 accepted >/dev/null 2>&1
  check "a CRLF record can be moved" "$?" "0"
  check "and keeps its CRLF endings" \
        "$(grep -c $'\r$' docs/adr/0000-crlf.md | tr -d ' ')" \
        "$(wc -l < docs/adr/0000-crlf.md | tr -d ' ')"
)

# --- the optional fields -----------------------------------------------------

( workdir
  "$NEW" "With People" >/dev/null 2>&1
  "$SET" 0000 accepted --decision-makers "Ana, Bo" --consulted "DBA guild" >/dev/null 2>&1
  f=docs/adr/0000-with-people.md
  check "decision-makers is written" "$(grep '^decision-makers:' "$f")" "decision-makers: Ana, Bo"
  check "consulted is written"       "$(grep '^consulted:' "$f")"       "consulted: DBA guild"
  check "informed is left empty"     "$(grep '^informed:' "$f")"        "informed:"
)

( workdir
  "$NEW" "Fields Only" >/dev/null 2>&1
  "$SET" 0000 --informed "frontend team" >/dev/null 2>&1
  check "fields can be set without a status change" "$?" "0"
  check "and the status is unchanged" \
        "$(status_of docs/adr/0000-fields-only.md)" 'status: "proposed"'
)

( workdir
  mkdir -p docs/adr
  # A hand-written record missing the optional keys: asking for one has to add
  # it rather than silently dropping what was requested.
  printf -- '---\nstatus: "proposed"\ndate: 2026-01-01\n---\n\n# T\n' > docs/adr/0000-sparse.md
  "$SET" 0000 accepted --consulted "Security" >/dev/null 2>&1
  check "a missing key is added rather than dropped" \
        "$(grep '^consulted:' docs/adr/0000-sparse.md)" "consulted: Security"
  check "and it landed inside the frontmatter" \
        "$(awk 'NR==1&&/^---$/{i=1;next} i&&/^---$/{exit} i&&/^consulted:/{print "inside"}' docs/adr/0000-sparse.md)" \
        "inside"
)

# --- arguments ---------------------------------------------------------------

( workdir
  "$SET" >/dev/null 2>&1
  check "no arguments is a usage error" "$?" "1"
)

( workdir
  "$NEW" "Nothing Asked" >/dev/null 2>&1
  "$SET" 0000 >/dev/null 2>&1
  check "an id with nothing to change is refused" "$?" "1"
)

( workdir
  "$SET" --root /etc 0000 accepted >/dev/null 2>&1
  check "--root refuses an absolute path" "$?" "1"
)

( workdir
  "$SET" --root ../elsewhere 0000 accepted >/dev/null 2>&1
  check "--root refuses to climb out" "$?" "1"
)

( workdir
  "$SET" ../../victim/0042 accepted >/dev/null 2>&1
  check "an id that is really a path is refused" "$?" "1"
)

( workdir
  mkdir -p docs/adr
  "$SET" 0099 accepted >/dev/null 2>&1
  check "a missing record is refused" "$?" "2"
)

( workdir
  "$NEW" "Trailing" >/dev/null 2>&1
  if [ "$have_perl" -ne 1 ]; then
    printf '  skip a trailing --consulted is a usage error (no perl, cannot time out)\n'
  else
    run_limited 5 "$SET" 0000 accepted --consulted >/dev/null 2>&1
    code=$?
    case "$code" in
      142) bad "a trailing --consulted is a usage error, not a hang" "it hung" ;;
      1)   ok  "a trailing --consulted is a usage error, not a hang" ;;
      *)   bad "a trailing --consulted is a usage error, not a hang" "unexpected exit $code" ;;
    esac
  fi
)

# --- the transition table is the rule; pin every edge of it ------------------
#
# A mutation run showed the suite stayed green when the table was widened with
# `proposed->deprecated` or `accepted->rejected`, which are the two most likely
# ways somebody loosens it. Refusals that were already covered are not enough:
# what is allowed has to be pinned from both sides.

( workdir
  "$NEW" "Skipping" >/dev/null 2>&1
  "$SET" 0000 deprecated >/dev/null 2>&1
  check "a draft cannot skip straight to deprecated" "$?" "2"
)

( workdir
  "$NEW" "Reversing" >/dev/null 2>&1
  "$SET" 0000 accepted >/dev/null 2>&1
  "$SET" 0000 rejected >/dev/null 2>&1
  check "an accepted record cannot be rejected afterwards" "$?" "2"
)

( workdir
  "$NEW" "Sideways" >/dev/null 2>&1
  "$SET" 0000 rejected   >/dev/null 2>&1
  "$SET" 0000 deprecated >/dev/null 2>&1
  check "a rejected record cannot be deprecated" "$?" "2"
)

# --- fields follow the same lifecycle ----------------------------------------

( workdir
  "$NEW" "Settled Fields" >/dev/null 2>&1
  "$SET" 0000 accepted >/dev/null 2>&1
  before=$(grep '^decision-makers:' docs/adr/0000-settled-fields.md)
  "$SET" 0000 --decision-makers "Somebody Else" >/dev/null 2>&1
  check "fields cannot be rewritten on an accepted record" "$?" "2"
  check "and the record was left alone" \
        "$(grep '^decision-makers:' docs/adr/0000-settled-fields.md)" "$before"
)

( workdir
  "$NEW" "Together" >/dev/null 2>&1
  "$SET" 0000 accepted --decision-makers "Ana" >/dev/null 2>&1
  check "but they can be set in the call that accepts" "$?" "0"
  check "and they landed" "$(grep '^decision-makers:' docs/adr/0000-together.md)" "decision-makers: Ana"
)

# The lifecycle check used to require a fields-ONLY call, so attaching fields to
# a legal move out of `accepted` rewrote them anyway. The rule is about the
# state the record is in, not about what else the call does.
( workdir
  "$NEW" "Smuggled" >/dev/null 2>&1
  "$SET" 0000 accepted --decision-makers "Ana" >/dev/null 2>&1
  "$SET" 0000 deprecated --decision-makers "Mallory" >/dev/null 2>&1
  check "fields cannot ride along on a legal transition" "$?" "2"
  check "and the original names survive" \
        "$(grep '^decision-makers:' docs/adr/0000-smuggled.md)" "decision-makers: Ana"
)

# A block sequence does not have to be indented to be a block sequence.
( workdir
  mkdir -p docs/adr
  printf -- '---\nstatus: "proposed"\nconsulted:\n- Ana\n- Bo\n---\n' > docs/adr/0000-flat-list.md
  cp docs/adr/0000-flat-list.md /tmp/flat-before.$$
  "$SET" 0000 --consulted "DBA guild" >/dev/null 2>&1
  check "an unindented block list is refused too" "$?" "2"
  check "and is left alone" "$(changed_lines /tmp/flat-before.$$ docs/adr/0000-flat-list.md)" "0"
  rm -f /tmp/flat-before.$$
)

# A value that cannot be a plain YAML scalar breaks the frontmatter for every
# reader, including this plugin's own.
( workdir
  "$NEW" "Colon" >/dev/null 2>&1
  "$SET" 0000 accepted --consulted 'Ana: the DBA' >/dev/null 2>&1
  check "a value containing a colon-space is refused" "$?" "1"
)

( workdir
  "$NEW" "Hash" >/dev/null 2>&1
  "$SET" 0000 accepted --consulted '#platform' >/dev/null 2>&1
  check "a value starting with a hash is refused" "$?" "1"
)

( workdir
  mkdir -p docs/notes
  printf -- '---\nstatus: published\n---\n' > docs/notes/0009-post.md
  "$SET" --root docs/notes 0009 --consulted "Nobody" >/dev/null 2>&1
  check "a non-MADR status blocks a fields-only call too" "$?" "2"

  # The outcome alone does not pin this: with the "is it a record" check removed
  # the transition table and the lifecycle check still refuse, just with a
  # message about a move nobody asked about. The message is what carries the
  # reason, so the message is what gets asserted.
  out=$("$SET" --root docs/notes 0009 accepted 2>&1)
  case "$out" in
    *"does not look like a decision record"*) ok "and the refusal says it is not a record at all" ;;
    *) bad "and the refusal says it is not a record at all" "it talked about the transition instead" ;;
  esac
)

# --- values reach the file unchanged -----------------------------------------
#
# These went through `awk -v`, which applies escape processing on every awk:
# `CORP\jsmith` arrived as `CORPjsmith`, and `C:\temp\notes` became a tab plus
# an extra frontmatter line, with exit 0.

( workdir
  "$NEW" "Backslash" >/dev/null 2>&1
  "$SET" 0000 accepted --consulted 'CORP\jsmith' >/dev/null 2>&1
  check "a backslash survives" "$(grep '^consulted:' docs/adr/0000-backslash.md)" 'consulted: CORP\jsmith'
)

( workdir
  "$NEW" "Windows Path" >/dev/null 2>&1
  "$SET" 0000 accepted --informed 'C:\temp\notes' >/dev/null 2>&1
  check "so does a Windows path" "$(grep '^informed:' docs/adr/0000-windows-path.md)" 'informed: C:\temp\notes'
  check "and it did not grow a line" \
        "$(awk 'NR==1&&/^---$/{i=1;next} i&&/^---$/{exit} i{n++} END{print n+0}' docs/adr/0000-windows-path.md)" "5"
)

( workdir
  "$NEW" "Multiline" >/dev/null 2>&1
  "$SET" 0000 accepted --informed 'a
date: 1999-01-01' >/dev/null 2>&1
  check "a real newline in a value is refused" "$?" "1"
  check "so no date was injected" \
        "$(grep -c '^date: 1999-01-01' docs/adr/0000-multiline.md | tr -d ' ')" "0"
)

# --- frontmatter shapes that cannot be rewritten safely ----------------------

( workdir
  mkdir -p docs/adr
  printf -- '---\nstatus: "proposed"\nconsulted:\n  - Ana\n  - Bo\n---\n\n# T\n' > docs/adr/0000-list.md
  cp docs/adr/0000-list.md /tmp/list-before.$$
  "$SET" 0000 --consulted "DBA guild" >/dev/null 2>&1
  check "a YAML block list is refused, not flattened" "$?" "2"
  check "and the list is untouched" "$(changed_lines /tmp/list-before.$$ docs/adr/0000-list.md)" "0"
  rm -f /tmp/list-before.$$
)

( workdir
  mkdir -p docs/adr
  printf -- '---\nstatus: "proposed"\ndate: 2026-01-01\n' > docs/adr/0000-unterminated.md
  "$SET" 0000 accepted --consulted Security >/dev/null 2>&1
  check "frontmatter with no closing fence is refused" "$?" "2"
)

( workdir
  mkdir -p docs/adr
  printf -- 'Not frontmatter\n---\nstatus: "proposed"\n---\n' > docs/adr/0000-late-fence.md
  "$SET" 0000 accepted >/dev/null 2>&1
  check "a fence that is not on line one is refused" "$?" "2"
)

# --- read the status the way the siblings read it ----------------------------
#
# `status: "accepted "` has its whitespace inside the quotes. One trim leaves
# `accepted ` and the record stops being recognised, so a file the guard locks
# and the generator will supersede became one this script called "not a record".

( workdir
  mkdir -p docs/adr
  printf -- '---\nstatus: "accepted "\ndate: 2026-01-01\n---\n\n# T\n' > docs/adr/0000-spaced.md
  "$SET" 0000 deprecated >/dev/null 2>&1
  check "a status padded inside its quotes is still read" "$?" "0"
)

( workdir
  mkdir -p docs/adr
  # No status in the frontmatter, one in the body. The body is prose.
  printf -- '---\ndate: 2026-01-01\n---\n\n```yaml\nstatus: "accepted"\n```\n' > docs/adr/0000-body.md
  "$SET" 0000 accepted >/dev/null 2>&1
  check "a status in the body is not the record's status" "$?" "2"
)

( workdir
  "$NEW" "Fenced Body" >/dev/null 2>&1
  f=docs/adr/0000-fenced-body.md
  # A DIFFERENT value from the one being set, so rewriting the body shows up.
  printf -- '\n```yaml\nstatus: "rejected"\n```\n' >> "$f"
  "$SET" 0000 accepted >/dev/null 2>&1
  check "the body's own status line is not rewritten" \
        "$(grep -c 'status: "rejected"' "$f" | tr -d ' ')" "1"
)

# --- the refusal points at a command that is right ---------------------------

( workdir
  "$NEW" --scope chat "Narrow" >/dev/null 2>&1
  "$SET" chat/0000 accepted >/dev/null 2>&1
  out=$("$SET" chat/0000 "superseded by 0001" 2>&1)
  case "$out" in
    *"--scope chat"*) ok "a narrowed refusal names the scope" ;;
    *) bad "a narrowed refusal names the scope" "it did not" ;;
  esac
  case "$out" in
    *"--supersedes chat/0000"*) ok "and a scoped id, not a bare number" ;;
    *) bad "and a scoped id, not a bare number" "it suggested the bare number" ;;
  esac
)

# --- failures are failures ---------------------------------------------------

( workdir
  "$NEW" "Unwritable" >/dev/null 2>&1
  chmod 555 docs/adr
  if : 2>/dev/null > docs/adr/.probe; then
    rm -f docs/adr/.probe; chmod 755 docs/adr
    printf '  skip unwritable-directory case (writes succeed here — running as root?)\n'
  else
    "$SET" 0000 accepted >/dev/null 2>&1
    code=$?
    chmod 755 docs/adr
    check "an unwritable directory is an error" "$code" "1"
    check "and the record did not move" \
          "$(status_of docs/adr/0000-unwritable.md)" 'status: "proposed"'
  fi
)

( workdir
  mkdir -p docs/adr
  printf -- '---\nstatus: "proposed"\n---\n' > docs/adr/0000-one.md
  printf -- '---\nstatus: "proposed"\n---\n' > docs/adr/0000-two.md
  "$SET" 0000 accepted >/dev/null 2>&1
  check "an id matching two files is refused" "$?" "2"
)

# NOT COVERED, and said so rather than implied: the branch where the rewrite
# succeeds and `mv` then fails. The unwritable-directory case above never
# reaches it, because writing the temp file fails first. Making only the rename
# fail needs a writable directory holding an unrenameable target, which is not
# portable, and the alternative is a seam in production code that exists for a
# test. A mutation removing that `exit 1` passes this suite. The branch is three
# lines and is reviewed by reading. Same gap, same reason, as the rollback
# branch in test-new-decision.sh.

pass=$(grep -c '^ok$'   "$RESULTS" || true)
fail=$(grep -c '^fail$' "$RESULTS" || true)

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
