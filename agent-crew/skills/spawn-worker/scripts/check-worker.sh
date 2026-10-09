#!/usr/bin/env bash
# Show what a worker's panel is displaying, so a coordinator can tell why one
# stopped without reporting.
#
# This script finds the panel, reads the screen and hands it back. It does not
# decide what it is looking at: the reader is a model that already holds the
# context this needs — which worker was given what, and whether a report came —
# and that is the join a pattern here could not make anyway.
#
# It carried a grep for the retry countdown at one point, on the grounds that
# nudging a worker mid-backoff aborts a recovery. That came out. The match ran
# over the whole viewport, so a worker whose own logs or source contained the
# phrase tripped it, and a retry banner sits on screen alongside the API error
# that follows it — both cases print "leave this one alone" over a worker that
# is in fact dead, which is the exact failure this script exists to catch.
# coordinate-workers names the state in its table instead.
set -euo pipefail

NAMES=()

usage() {
  cat <<'USAGE'
Usage: check-worker.sh --name <worker> [--name <worker> ...]

  --name   the worker's stable identity — the cmux tab title, which never
           changes and is how this script finds the panel. Repeat it to check
           several workers in one call.

Prints each worker's screen, blank runs collapsed. It reports what is there and
leaves the judgement to you; coordinate-workers has the table of what each state
looks like and what to do about it.

Reach for this only for a worker that stopped without reporting. ListAgents
already separates busy from idle at no cost, and a busy worker needs no
inspection.

Exit codes: 0 all screens read, 4 a worker could not be found, 5 a screen could
not be read. The worst outcome wins, and every worker is still attempted.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    # Check for the value before shifting past it: a trailing bare --name would
    # otherwise make `shift 2` fail and exit 1 with no message of its own.
    --name) [[ $# -ge 2 ]] || { echo "--name needs a worker name after it" >&2; exit 2; }; NAMES+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ ${#NAMES[@]} -gt 0 ]] || { echo "--name is required" >&2; usage >&2; exit 2; }
command -v cmux >/dev/null || { echo "cmux not on PATH; this skill requires cmux" >&2; exit 3; }

for NAME in "${NAMES[@]}"; do
  [[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { echo "--name must start with a letter or digit and contain only letters, digits and . _ - : (no spaces) — got: ${NAME}" >&2; exit 2; }
done

STATUS=0

for NAME in "${NAMES[@]}"; do
  echo "=== ${NAME} ==="

  SURFACE="$(
    cmux list-panels --json | python3 -c '
import json, re, sys
name = sys.argv[1]
# Strip at most ONE leading status glyph. Every glyph cmux uses is non-ASCII
# ("✳ name", "◑ name"), so requiring that keeps an ASCII-decorated title such
# as "- bob" a genuinely different panel from "bob" instead of a collision.
GLYPH = re.compile(r"^[^\x00-\x7F]\s+")
hits = []
for s in json.load(sys.stdin).get("surfaces", []):
    raw = (s.get("title") or "").strip()
    if raw == name or GLYPH.sub("", raw) == name:
        hits.append((s.get("ref", ""), raw))
if len(hits) > 1:
    sys.stderr.write("AMBIGUOUS: " + ", ".join(f"{r} [{t}]" for r, t in hits) + "\n")
elif hits:
    print(hits[0][0])
' "$NAME"
  )" || true

  if [[ -z "${SURFACE:-}" ]]; then
    echo "no single panel matches '${NAME}'." >&2
    echo "Either none does — the panel title is not the SendMessage address, so a" >&2
    echo "worker whose tab was never named for it cannot be inspected this way —" >&2
    echo "or several do, in which case they are listed above and you need a name" >&2
    echo "that picks out exactly one." >&2
    if [[ "$STATUS" -lt 4 ]]; then STATUS=4; fi
    echo
    continue
  fi

  # Keep stderr: when the read fails, its reason is the only thing that
  # distinguishes a closed panel from a cmux that is not answering, and the
  # message below is worth more with it than without.
  SCREEN="$(cmux read-screen --surface "$SURFACE" 2>&1)" || SCREEN=""

  # An unreadable screen is not a quiet worker, it is an unknown one. Saying so
  # out loud matters more here than anywhere else in this plugin: the whole
  # point of the check is to catch a worker that stopped, and silence read as
  # "nothing to report" recreates exactly the failure it exists to prevent.
  #
  # Strip every kind of whitespace, not just spaces. A viewport of newlines and
  # tabs is as empty as one of spaces, and treating it as readable would print
  # nothing and call it a successful check.
  if [[ -z "${SCREEN//[[:space:]]/}" ]]; then
    echo "could not read ${NAME}'s screen (${SURFACE}) — state UNKNOWN." >&2
    echo "This is not evidence that the worker is fine. Look at the panel." >&2
    if [[ "$STATUS" -lt 5 ]]; then STATUS=5; fi
    echo
    continue
  fi

  echo "surface: ${SURFACE}"
  # Collapse blank runs rather than trimming to the last N lines. The screen is
  # the full viewport and the lower half of it is blank padding, so a tail would
  # return the padding and the status bar and miss the message that explains
  # why the worker stopped. Measured: an error on line 39 of 81, with the chrome
  # starting at line 76.
  printf '%s\n' "$SCREEN" | cat -s
  echo
done

exit "$STATUS"
