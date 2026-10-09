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

# --- the refusal has to be actionable ----------------------------------------
#
# A refusal that says only "no" is a refusal the agent will try to work around.
# Everything the replacement command needs is derivable here, so these check it
# was actually derived rather than left as a placeholder the agent has to fill.

# A record in a nested directory, so --root has something to get wrong.
mkdir -p "$WORK/docs/adr/chat"
reason_for() {
  printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$WORK" "$1" \
    | "$GUARD" 2>/dev/null \
    | python3 -c 'import json,sys
try:    print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])
except Exception: pass'
}
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "not in the reason: $2" ;; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1" "should not be in the reason: $2" ;; *) ok "$1" ;; esac; }

printf -- '---\nstatus: "accepted"\n---\n' > "$WORK/docs/adr/0014-postgres.md"
r=$(reason_for "$WORK/docs/adr/0014-postgres.md")
has  "the refusal names the record's own id"      "--supersedes 0014" "$r"
has  "the refusal names the record's directory"   "--root docs/adr"   "$r"
has  "the path is shown relative to the session"  "docs/adr/0014-postgres.md" "$r"
hasnt "no placeholder is left for the agent"      "<id>"              "$r"

printf -- '---\nstatus: "accepted"\n---\n' > "$WORK/docs/adr/chat/0003-nested.md"
r=$(reason_for "$WORK/docs/adr/chat/0003-nested.md")
has "a nested record gets its own directory as --root" "--root docs/adr/chat" "$r"

# Telling an agent to supersede an already superseded record aims it at a
# command the generator refuses. It has to be sent along the chain instead.
printf -- '---\nstatus: "superseded by 0021"\n---\n' > "$WORK/docs/adr/0007-old.md"
r=$(reason_for "$WORK/docs/adr/0007-old.md")
has   "a superseded record points at its replacement" "0021" "$r"
hasnt "and does not tell the agent to supersede it"   "--supersedes 0007" "$r"

# A rejected decision was never taken, so there is nothing to supersede. The
# wording may still name the flag — "write a new record with no --supersedes" is
# the clearest way to say it — so what must be absent is the command aimed at
# this record, not the token.
printf -- '---\nstatus: "rejected"\n---\n' > "$WORK/docs/adr/0005-declined.md"
r=$(reason_for "$WORK/docs/adr/0005-declined.md")
hasnt "a rejected record is not offered as a supersede target" "--supersedes 0005" "$r"
has   "and a fresh record is offered instead" "--root docs/adr" "$r"

pass=$(grep -c '^ok$'   "$RESULTS" || true)
fail=$(grep -c '^fail$' "$RESULTS" || true)

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
