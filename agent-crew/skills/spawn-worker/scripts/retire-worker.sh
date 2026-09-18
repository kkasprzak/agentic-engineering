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
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { echo "--name must start with a letter or digit and contain only letters, digits and . _ - : — got: ${NAME}" >&2; exit 2; }
command -v cmux >/dev/null || { echo "cmux not on PATH; this skill requires cmux" >&2; exit 3; }

# Resolve the panel by its title, and capture its directory before it is gone.
# Matching has to be exact and unambiguous: this is the one path that can delete
# a worktree, so picking the first of several near-matches is not acceptable.
read -r SURFACE DIR < <(
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
        hits.append((s.get("ref", ""), s.get("requested_working_directory") or "", raw))
if len(hits) > 1:
    sys.stderr.write("AMBIGUOUS: " + ", ".join(f"{r} [{t}]" for r, _, t in hits) + "\n")
elif hits:
    print(hits[0][0], hits[0][1])
' "$NAME"
) || true

[[ -n "${SURFACE:-}" ]] || {
  echo "no single panel matches '${NAME}'." >&2
  echo "Either none does — it may already be closed, or its tab was renamed away" >&2
  echo "from the session name — or several do, in which case they are listed above" >&2
  echo "and you need a name that picks out exactly one." >&2
  exit 4
}

# Print the directory BEFORE anything is closed or removed. Once the panel is
# gone there is no way to check that the right worker was targeted.
echo "matched ${SURFACE} (${NAME}), working directory: ${DIR:-unknown}"

cmux close-surface --surface "$SURFACE" >/dev/null
echo "closed ${SURFACE} (${NAME})"

[[ "$REMOVE_WORKTREE" -eq 1 ]] || { echo "worktree left in place: ${DIR:-unknown}"; exit 0; }

[[ -n "${DIR:-}" && -d "$DIR" ]] || { echo "no worktree directory recorded for this panel; nothing removed"; exit 0; }
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "${DIR} is not a git worktree; nothing removed"; exit 0; }

# --ignored as well: a worker's .env or local scratch is invisible to a plain
# status and would be destroyed without ever being mentioned.
DIRTY="$(git -C "$DIR" status --porcelain --ignored)"
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
# No --force on the clean path: git runs its own dirty check, and letting it
# object is worth more than saving a second run with --force-worktree.
if [[ "$FORCE_WORKTREE" -eq 1 ]]; then
  git worktree remove --force "$DIR"
else
  git worktree remove "$DIR"
fi
echo "removed worktree ${DIR}"
