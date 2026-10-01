#!/usr/bin/env bash
# Wait until a pull request's checks have settled, so that the analysis you read
# next belongs to the commit you just pushed rather than the one before it.
#
# Usage: wait-for-analysis.sh [PR] [--check PATTERN] [--timeout SECONDS]
#   PR         PR number; defaults to the PR of the current branch
#   --check    only wait on checks whose name matches this (case-insensitive)
#              extended regex, e.g. --check 'sonar|build'. Default: all of them.
#   --timeout  give up after this many seconds (default 1200)
#
# Exit 0 once nothing is pending, 2 on timeout, 1 on a usage or lookup error.
# The final check table goes to stdout; progress goes to stderr.
#
# Gotchas this handles so the caller does not have to:
#   - `gh pr checks` exits non-zero when a check FAILED, which is not the same as
#     still running. Its exit status is therefore ignored and the table parsed.
#   - A check that has not been created yet is absent from the table, so an empty
#     or short table early on does not mean "settled". With --check, the pattern
#     must match at least once before its absence is allowed to count as done.
#   - Polling faster than ~20s buys nothing: a build takes minutes and the API is
#     rate limited.
set -uo pipefail

PR=""
PATTERN=""
TIMEOUT=1200
INTERVAL=20

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   PATTERN="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *)         PR="$1"; shift ;;
  esac
done

seen_pattern=0
deadline=$(( $(date +%s) + TIMEOUT ))

while :; do
  table=$(gh pr checks ${PR:+"$PR"} 2>/dev/null)   # non-zero on failing checks

  if [ -n "$PATTERN" ]; then
    rows=$(printf '%s\n' "$table" | grep -Ei "$PATTERN" || true)
    [ -n "$rows" ] && seen_pattern=1
  else
    rows="$table"
    [ -n "$rows" ] && seen_pattern=1
  fi

  pending=$(printf '%s\n' "$rows" | awk -F'\t' 'NF>1 && $2=="pending"' | wc -l | tr -d ' ')

  if [ "$seen_pattern" = "1" ] && [ "$pending" = "0" ]; then
    printf '%s\n' "$rows"
    exit 0
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "timed out after ${TIMEOUT}s with ${pending} check(s) still pending" >&2
    printf '%s\n' "$rows"
    exit 2
  fi

  echo "waiting: ${pending} check(s) pending" >&2
  sleep "$INTERVAL"
done
