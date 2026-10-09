#!/usr/bin/env bash
# Show what a worker's panel is displaying, so a coordinator can tell why one
# stopped without reporting.
#
# This script deliberately does NOT decide what it is looking at. It finds the
# panel, reads the screen and hands it back; the reading happens in
# coordinate-workers, which lists what each state looks like. A screen is UI,
# and UI drifts between releases — a pattern baked into a script here would go
# on reporting "fine" after the thing it matched stopped existing, which is the
# one failure worth avoiding. Prose goes stale visibly; code goes stale silently.
#
# The single exception is the retry warning below, and it is there because
# acting on that state does damage rather than nothing.
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
    --name) NAMES+=("${2:-}"); shift 2 ;;
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
    echo "no panel found whose title matches '${NAME}'." >&2
    echo "The panel title is not the SendMessage address; a worker launched without" >&2
    echo "a matching tab name cannot be inspected this way." >&2
    STATUS=4
    echo
    continue
  fi

  SCREEN="$(cmux read-screen --surface "$SURFACE" 2>/dev/null)" || SCREEN=""

  # An unreadable screen is not a quiet worker, it is an unknown one. Saying so
  # out loud matters more here than anywhere else in this plugin: the whole
  # point of the check is to catch a worker that stopped, and silence read as
  # "nothing to report" recreates exactly the failure it exists to prevent.
  if [[ -z "${SCREEN// /}" ]]; then
    echo "could not read ${NAME}'s screen (${SURFACE}) — state UNKNOWN." >&2
    echo "This is not evidence that the worker is fine. Look at the panel." >&2
    STATUS=5
    echo
    continue
  fi

  # The one judgement this script does make. A worker showing a retry countdown
  # is not stuck — the CLI is waiting out a backoff that was measured at over
  # two minutes, and a message sent now interrupts a recovery that would have
  # succeeded on its own. Every other state is cheap to get wrong and is left
  # to the reader; this one is not.
  if printf '%s' "$SCREEN" | grep -qiE 'will retry in|waiting for api response'; then
    echo "NOTE: ${NAME} is retrying — leave it alone. The countdown runs for"
    echo "      minutes, and nudging now aborts a recovery already in progress."
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
