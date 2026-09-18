#!/usr/bin/env bash
# Clear a worker's conversation between tasks, keeping the session alive.
#
# /clear is a CLI command, not a tool, so it cannot be delivered as a message —
# it has to be typed into the panel. That means this script is keystroke
# injection: it does not know what is on screen, and Enter sent at a permission
# dialog answers the dialog. Hence the checks below, which are the reason to use
# this rather than sending the keys by hand.
#
# Verified: /clear wipes the conversation, keeps the --agent role, and keeps the
# -n session name, so the SendMessage address survives.
set -euo pipefail

NAME=""
LABEL=""
FORCE=0

usage() {
  cat <<'USAGE'
Usage: clear-worker.sh --name <worker> [--label <task>] [--force]

  --name   the worker's stable identity — the cmux tab title, which never
           changes and is how this script finds the panel
  --label  short name of the task it is about to take (a tracker id, a few
           words). Shown in the panel header so several workers in the same
           role can be told apart by what they are doing.
  --force  skip the busy/dialog checks and clear regardless

Refuses while the worker is mid-turn or showing a prompt that is not the plain
input box. Clearing a worker that is still working discards its working state.

NOTE: with --label the session is renamed, and renaming changes the SendMessage
address. The new address is printed at the end; use it for the next dispatch.
The tab title stays put, so --name keeps working here regardless.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)  NAME="${2:-}";  shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$NAME" ]] || { echo "--name is required" >&2; usage >&2; exit 2; }
command -v cmux >/dev/null || { echo "cmux not on PATH; this skill requires cmux" >&2; exit 3; }

# Both of these end up typed into the panel, where a newline submits whatever
# precedes it — so neither may carry control characters or shell punctuation.
[[ "$NAME" =~ ^[A-Za-z0-9._:-][A-Za-z0-9\ ._:-]*$ ]] || { echo "--name may contain only letters, digits, spaces and . _ - : — got: ${NAME}" >&2; exit 2; }
[[ -z "$LABEL" || "$LABEL" =~ ^[A-Za-z0-9._:/-][A-Za-z0-9\ ._:/-]*$ ]] || { echo "--label may contain only letters, digits, spaces and . _ - : / — got: ${LABEL}" >&2; exit 2; }

SURFACE="$(
  cmux list-panels --json | python3 -c '
import json, re, sys
name = sys.argv[1]
for s in json.load(sys.stdin).get("surfaces", []):
    raw = (s.get("title") or "").strip()
    # Panels carry a leading status glyph ("✳ name"); drop it, then match the
    # whole title. A suffix match would let --name bob select "spongebob".
    if raw == name or re.sub(r"^[^\w]+\s*", "", raw) == name:
        print(s.get("ref", ""))
        break
' "$NAME"
)" || true

[[ -n "${SURFACE:-}" ]] || {
  echo "no panel found whose title matches '${NAME}'." >&2
  echo "The panel title is not the SendMessage address; a worker launched without" >&2
  echo "a matching tab name cannot be reached this way." >&2
  exit 4
}

SCREEN="$(cmux read-screen --surface "$SURFACE" 2>&1 || true)"

if [[ "$FORCE" -eq 0 ]]; then
  # A spinner line like "Noodling… (24s · ↓ 291 tokens)" means mid-turn.
  if printf '%s' "$SCREEN" | grep -qE '…[[:space:]]*\([0-9]+s'; then
    echo "${NAME} is mid-turn — not clearing." >&2
    echo "Wait for its report. Clearing now discards whatever it is holding." >&2
    exit 5
  fi
  # A permission prompt or any other chooser replaces the plain input box.
  # Enter typed into one of those answers it, which is the failure worth avoiding.
  if printf '%s' "$SCREEN" | grep -qiE 'do you want|allow this|❯[[:space:]]*[0-9]+\.'; then
    echo "${NAME} appears to be showing a chooser or permission prompt — not clearing." >&2
    echo "Typing Enter there would answer it. Look at the panel first, then --force." >&2
    exit 5
  fi
fi

cmux send --surface "$SURFACE" "/clear" >/dev/null
cmux send-key --surface "$SURFACE" Enter >/dev/null
sleep 4

# /clear leaves the cmux tab title alone but reverts the panel header to the
# agent name, so every cleared worker starts looking like every other worker in
# the same role. /rename puts an identity back. Keep the worker's own name in it
# even when a task label is given: /rename also changes the SendMessage address,
# and an address that is only a task id loses the thread back to who is doing it.
SESSION_NAME="$NAME"
[[ -n "$LABEL" ]] && SESSION_NAME="${NAME} · ${LABEL}"

# ctrl+u first: anything left in the input box would concatenate with the
# command and be submitted as an ordinary prompt instead of running.
cmux send-key --surface "$SURFACE" ctrl+u >/dev/null
cmux send --surface "$SURFACE" "/rename ${SESSION_NAME}" >/dev/null
cmux send-key --surface "$SURFACE" Enter >/dev/null
sleep 3

# The tab keeps the bare identity — it is this script's lookup key and the one
# label that survives every rename.
cmux rename-tab --surface "$SURFACE" "$NAME" >/dev/null 2>&1 || true

echo "cleared ${SURFACE} (${NAME})"

if cmux read-screen --surface "$SURFACE" 2>&1 | grep -qF -- "$SESSION_NAME"; then
  echo "panel header now reads: ${SESSION_NAME}"
else
  echo "WARNING: the panel header does not read '${SESSION_NAME}' — the rename may" >&2
  echo "not have landed. Look at the panel; until it does, several workers in one" >&2
  echo "role are indistinguishable and the address below may be wrong." >&2
fi

echo "SendMessage address is now: ${SESSION_NAME}"
echo
echo "The role survives a clear; only the conversation goes. The worker now has no"
echo "brief — send the next task in full, since nothing it was told before this"
echo "point still exists, including whatever you told it when you spawned it."
