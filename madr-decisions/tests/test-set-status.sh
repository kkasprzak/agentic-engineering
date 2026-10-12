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
  "$SET" 0000 accepted --consulted >/dev/null 2>&1
  check "a trailing --consulted is a usage error, not a hang" "$?" "1"
)

pass=$(grep -c '^ok$'   "$RESULTS" || true)
fail=$(grep -c '^fail$' "$RESULTS" || true)

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
