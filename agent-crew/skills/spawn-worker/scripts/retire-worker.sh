#!/usr/bin/env bash
# Close a worker's cmux panel, and optionally remove the git worktree it used.
#
# Refuses to remove a worktree that has uncommitted changes or commits the
# worker never pushed. That is the whole point of doing this in a script: the
# manual version is `git worktree remove --force`, which destroys work silently.
set -euo pipefail

NAME=""
REMOVE_WORKTREE=0
FORCE_WORKTREE=0

usage() {
  cat <<'USAGE'
Usage: retire-worker.sh --name <session-name> [--remove-worktree] [--force-worktree]

  --name             session name, as shown in ListAgents and on the cmux panel
  --remove-worktree  also remove the git worktree the worker was running in
  --force-worktree   remove it even when it holds uncommitted or unpushed work

Closing the panel ends the session. Idle notices already in flight can still
arrive afterwards; that is not an orphaned process.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --remove-worktree) REMOVE_WORKTREE=1; shift ;;
    --force-worktree)  FORCE_WORKTREE=1;  shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$NAME" ]] || { echo "--name is required" >&2; usage >&2; exit 2; }
command -v cmux >/dev/null || { echo "cmux not on PATH; this skill requires cmux" >&2; exit 3; }

# Resolve the panel by its title, and capture its directory before it is gone.
# Matching has to be exact: this is the one path that can delete a worktree, and
# a suffix match would let --name bob select a panel called "spongebob".
read -r SURFACE DIR < <(
  cmux list-panels --json | python3 -c '
import json, re, sys
name = sys.argv[1]
for s in json.load(sys.stdin).get("surfaces", []):
    raw = (s.get("title") or "").strip()
    # Panels carry a leading status glyph ("✳ name"); drop it, then match whole.
    if raw == name or re.sub(r"^[^\w]+\s*", "", raw) == name:
        print(s.get("ref", ""), s.get("requested_working_directory") or "")
        break
' "$NAME"
) || true

[[ -n "${SURFACE:-}" ]] || {
  echo "no panel found whose title matches '${NAME}'." >&2
  echo "It may already be closed, or its tab was renamed away from the session name." >&2
  exit 4
}

cmux close-surface --surface "$SURFACE" >/dev/null
echo "closed ${SURFACE} (${NAME})"

[[ "$REMOVE_WORKTREE" -eq 1 ]] || { echo "worktree left in place: ${DIR:-unknown}"; exit 0; }

[[ -n "${DIR:-}" && -d "$DIR" ]] || { echo "no worktree directory recorded for this panel; nothing removed"; exit 0; }
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "${DIR} is not a git worktree; nothing removed"; exit 0; }

DIRTY="$(git -C "$DIR" status --porcelain)"
# Only commits reachable from THIS worktree's HEAD. Scoping to --branches would
# drag in every stale local branch in the repository and refuse every time.
UNPUSHED="$(git -C "$DIR" log --oneline HEAD --not --remotes 2>/dev/null || true)"

if [[ -n "$DIRTY" || -n "$UNPUSHED" ]] && [[ "$FORCE_WORKTREE" -eq 0 ]]; then
  echo
  echo "NOT removing ${DIR} — it still holds work:"
  [[ -n "$DIRTY"    ]] && { echo "  uncommitted changes:"; printf '%s\n' "$DIRTY" | cut -c4- | sed 's/^/    /'; }
  [[ -n "$UNPUSHED" ]] && { echo "  commits not on any remote:"; printf '%s\n' "$UNPUSHED" | sed 's/^/    /'; }
  echo
  echo "Salvage it first, or re-run with --force-worktree to discard it."
  exit 5
fi

git -C "$DIR" rev-parse --git-dir >/dev/null
git worktree remove --force "$DIR"
echo "removed worktree ${DIR}"
