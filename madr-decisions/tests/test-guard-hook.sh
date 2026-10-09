#!/usr/bin/env bash
# Tests for guard-accepted-record.sh.
#
# Run: madr-decisions/tests/test-guard-hook.sh
#
# The guard has two ways to be useless and they pull in opposite directions: it
# can fail to block an edit to settled history, or it can block the normal
# workflow of filling in a freshly generated skeleton. Both are covered here,
# and the second matters more — a guard that blocks ordinary work gets switched
# off, and then it protects nothing at all.
set -uo pipefail

GUARD="$(cd "$(dirname "$0")/../hooks" && pwd)/guard-accepted-record.sh"
[ -x "$GUARD" ] || { echo "not executable: $GUARD" >&2; exit 1; }

RESULTS="$(mktemp)"
WORK="$(mktemp -d)"
trap 'rm -rf "$RESULTS" "$WORK"' EXIT

ok()  { echo ok   >> "$RESULTS"; printf '  ok   %s\n' "$1"; }
bad() { echo fail >> "$RESULTS"; printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

# Build a record with the given status and ask the guard about editing it.
# Prints "deny" or "allow".
verdict() {
  local status="$1" name="$2" tool="${3:-Edit}"
  local f="$WORK/$name.md"
  if [ "$status" = "__nofrontmatter__" ]; then
    printf 'just a markdown file\n' > "$f"
  elif [ "$status" = "__bodyonly__" ]; then
    printf -- '---\ndate: 2026-01-01\n---\n\n```yaml\nstatus: "accepted"\n```\n' > "$f"
  else
    printf -- '---\nstatus: "%s"\ndate: 2026-01-01\n---\n\n# Title\n' "$status" > "$f"
  fi
  out=$(printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
        "$tool" "$f" | "$GUARD" 2>/dev/null)
  case "$out" in
    *'"permissionDecision": "deny"'*) echo deny ;;
    *) echo allow ;;
  esac
}

expect() {
  local got; got=$(verdict "$2" "$3" "${4:-Edit}")
  if [ "$got" = "$5" ]; then ok "$1"; else bad "$1" "expected $5, got $got"; fi
}

echo "guard-accepted-record.sh"

# --- the workflow must not be blocked ---------------------------------------

expect "a proposed record stays editable"            proposed    r-proposed   Edit  allow
expect "a proposed record stays writable"            proposed    r-proposed-w Write allow

# --- settled records are history --------------------------------------------

expect "an accepted record is refused"               accepted    r-accepted   Edit  deny
expect "an accepted record is refused on Write too"  accepted    r-accepted-w Write deny
expect "a rejected record is refused"                rejected    r-rejected   Edit  deny
expect "a deprecated record is refused"              deprecated  r-deprecated Edit  deny
expect "a superseded record is refused" "superseded by 0014" r-superseded Edit deny

# --- things that are not decision records ------------------------------------

expect "a file without frontmatter is left alone"    __nofrontmatter__ r-bare   Edit allow
expect "a status inside the body is not state"       __bodyonly__      r-body   Edit allow

# --- edges -------------------------------------------------------------------

out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/does-not-exist.md"}}' "$WORK" \
      | "$GUARD" 2>/dev/null)
if [ -z "$out" ]; then ok "a file that does not exist yet is allowed"
else bad "a file that does not exist yet is allowed" "guard produced: $out"; fi

printf -- '---\nstatus: "accepted"\n---\n' > "$WORK/with space.md"
out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/with space.md"}}' "$WORK" \
      | "$GUARD" 2>/dev/null)
case "$out" in
  *deny*) ok "a path containing a space is still matched" ;;
  *) bad "a path containing a space is still matched" "guard produced: ${out:-<nothing>}" ;;
esac

out=$(printf 'not json at all' | "$GUARD" 2>/dev/null); code=$?
if [ "$code" -eq 0 ] && [ -z "$out" ]; then ok "malformed input does not block the session"
else bad "malformed input does not block the session" "exit=$code out=${out:-<nothing>}"; fi

printf -- '---\nstatus: "accepted"\n---\n' > "$WORK/notes.txt"
out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/notes.txt"}}' "$WORK" \
      | "$GUARD" 2>/dev/null)
if [ -z "$out" ]; then ok "a non-markdown file is left alone"
else bad "a non-markdown file is left alone" "guard produced: $out"; fi

# The denial has to name the way forward, or the agent reads it as a wall and
# starts looking for a way around.
out=$(verdict accepted r-reason Edit >/dev/null; \
      printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/r-reason.md"}}' "$WORK" | "$GUARD")
case "$out" in
  *--supersedes*) ok "the refusal points at --supersedes" ;;
  *) bad "the refusal points at --supersedes" "reason did not mention it" ;;
esac

pass=$(grep -c '^ok$'   "$RESULTS" || true)
fail=$(grep -c '^fail$' "$RESULTS" || true)

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
