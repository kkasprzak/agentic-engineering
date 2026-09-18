#!/usr/bin/env bash
# Spawn a Claude Code worker in a new cmux panel.
#
# Encodes the launch details that are easy to get wrong. It cannot confirm the
# worker registered as a peer session — that check is ListAgents, which is a
# tool the coordinator holds, not a shell command. Always verify after running.
set -euo pipefail

ROLE=""
NAME=""
DIR=""
WAIT=15
GUARD="spawn-worker,coordinate-workers"

usage() {
  cat <<'USAGE'
Usage: spawn-worker.sh --role <agent> --name <session-name> --dir <path> [--wait <seconds>] [--guard <skill>]

  --role   agent definition to run the session as, spelled exactly as the Agent
           tool lists it, e.g. agent-crew:backend-developer or agent-crew:tester
  --name   session name; this is the address SendMessage will use
  --dir    working directory, normally a dedicated git worktree
  --wait   how long to wait for the panel to come up, in seconds (default 15).
           This is a timeout, not a duration — the script returns as soon as
           the prompt appears, which is normally a few seconds.
  --guard  comma-separated skills the worker must not be able to load
           (default: the coordination skills); pass "" to disable the guard

Prints the cmux surface ref and the session name on success.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)  ROLE="${2:-}";  shift 2 ;;
    --name)  NAME="${2:-}";  shift 2 ;;
    --dir)   DIR="${2:-}";   shift 2 ;;
    --wait)  WAIT="${2:-}";  shift 2 ;;
    --guard) GUARD="${2-}";  shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$ROLE" && -n "$NAME" && -n "$DIR" ]] || { echo "--role, --name and --dir are required" >&2; usage >&2; exit 2; }
[[ -d "$DIR" ]] || { echo "no such directory: $DIR" >&2; exit 2; }

# The launch line below is TYPED INTO A LIVE SHELL and submitted with Enter, so
# anything interpolated into it is executable. Blocking shell punctuation is not
# enough: a space and a hyphen are sufficient on their own. A name of
# `w1 --dangerously-skip-permissions` adds a flag to the command, and
# `w1 do something` becomes a starting prompt for a worker holding a full shell.
# Hence no spaces, and the first character must be alphanumeric so nothing can
# begin with a hyphen and be read as a flag.
VALID_TOKEN='^[A-Za-z0-9][A-Za-z0-9._:-]*$'
[[ "$ROLE" =~ $VALID_TOKEN ]] || { echo "--role must start with a letter or digit and contain only letters, digits and . _ - : — got: ${ROLE}" >&2; exit 2; }
[[ "$NAME" =~ $VALID_TOKEN ]] || { echo "--name must start with a letter or digit and contain only letters, digits and . _ - : (no spaces) — got: ${NAME}" >&2; exit 2; }
# WAIT reaches $(( ... )), where bash evaluates command substitution: an
# unvalidated `x[$(...)]` would run in THIS shell, not in the worker's.
[[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "--wait must be a whole number of seconds — got: ${WAIT}" >&2; exit 2; }
command -v cmux >/dev/null || { echo "cmux not on PATH; this skill requires cmux" >&2; exit 3; }
[[ -S "${CMUX_SOCKET_PATH:-}" ]] || { echo "cmux socket not found at CMUX_SOCKET_PATH=${CMUX_SOCKET_PATH:-unset}" >&2; exit 3; }

# A terminal surface, not --type agent-session: only a terminal running the
# claude CLI registers as a peer session that SendMessage can reach.
CREATED="$(cmux new-surface --type terminal --working-directory "$DIR" --focus false)"
SURFACE="$(printf '%s\n' "$CREATED" | grep -o 'surface:[0-9]\+' | head -1)"
[[ -n "$SURFACE" ]] || { echo "could not parse surface ref from: $CREATED" >&2; exit 4; }

# -n sets the SendMessage address. Without it the session is auto-named after
# its directory and cannot be addressed predictably.
# Single-quoted in the typed line as a second layer: the validation above
# already excludes a quote, so nothing can close them.
LAUNCH="claude --agent '${ROLE}' -n '${NAME}' --permission-mode auto"
if [[ -n "$GUARD" ]]; then
  IFS=',' read -ra GUARDED <<< "$GUARD"
  for g in "${GUARDED[@]}"; do
    g="$(printf '%s' "$g" | tr -d '[:space:]')"
    [[ -n "$g" ]] || continue
    [[ "$g" =~ $VALID_TOKEN ]] || { echo "--guard entry is not a plain skill name: ${g}" >&2; exit 2; }
    LAUNCH="${LAUNCH} --disallowed-tools 'Skill(${g})'"
  done
fi

# send types the line; send-key submits it. Sending alone leaves it unexecuted.
cmux send --surface "$SURFACE" "$LAUNCH" >/dev/null
cmux send-key --surface "$SURFACE" Enter >/dev/null

# Poll the screen instead of sleeping a flat --wait. Boot is usually a few
# seconds; a fixed wait burns the rest of it on every spawn, which is paid again
# for every worker. --wait is the timeout now, not the duration.
READY=0
TRUST=0
TICKS=0
MAX_TICKS=$(( WAIT * 2 ))          # half-second ticks, integer arithmetic only
while (( TICKS < MAX_TICKS )); do
  SCREEN="$(cmux read-screen --surface "$SURFACE" 2>&1 || true)"
  if printf '%s' "$SCREEN" | grep -qiE 'is this a project you|trust this folder'; then
    TRUST=1; break
  fi
  # The status line only renders once the CLI is up and taking input.
  if printf '%s' "$SCREEN" | grep -qE 'auto mode on|ctx:'; then
    READY=1; break
  fi
  sleep 0.5
  TICKS=$(( TICKS + 1 ))
done
ELAPSED="$(( TICKS / 2 )).$(( (TICKS % 2) * 5 ))"

if [[ "$TRUST" -eq 1 ]]; then
  cmux rename-tab --surface "$SURFACE" "$NAME" >/dev/null 2>&1 || true
  echo "surface=${SURFACE}" >&2
  echo >&2
  echo "${NAME} is waiting on a trust-this-folder prompt and has NOT started." >&2
  echo "${DIR} is new to the CLI. Answering that prompt grants read, write and" >&2
  echo "execute there, so look at the panel and answer it yourself — this script" >&2
  echo "will not press Enter on a permission decision for you." >&2
  exit 6
fi

cmux rename-tab --surface "$SURFACE" "$NAME" >/dev/null 2>&1 || true

printf 'surface=%s\nname=%s\nrole=%s\ndir=%s\nready_after=%ss\n' \
  "$SURFACE" "$NAME" "$ROLE" "$DIR" "$ELAPSED"

if [[ "$READY" -eq 0 ]]; then
  echo
  echo "NOTE: the panel showed no prompt within ${WAIT}s. It may still be starting," >&2
  echo "or the launch may have failed — read the panel before assuming either." >&2
fi

echo
echo "Now verify with ListAgents that '${NAME}' is present, then ask it for its"
echo "working directory and branch before assigning any work. The prompt appearing"
echo "means the CLI is up; peer registration can trail it by a few seconds."
