#!/usr/bin/env bash
# Refuse an edit to a decision record that is no longer open.
#
# The incident this plugin was written after was not a bad record being created.
# It was an accepted record being edited to match today's code, which destroyed
# the only account of what was decided and left the document contradicting
# itself. `new-decision.sh` runs at creation and cannot help there: by the time
# an agent is "updating the docs" alongside a code change, nothing in this
# plugin is watching.
#
# The lock is the record's own status field:
#
#   proposed                 still being written — editing it is the workflow
#   accepted | rejected      a decision that was taken — history, refuse
#   deprecated               ditto
#   superseded by <id>       ditto, and the replacement already exists
#
# That is why no path list is needed. A record the generator has just produced
# says `proposed`, so filling the skeleton in place — exactly what the skill
# tells the agent to do — is never blocked. The moment a human accepts it, the
# same file becomes read-only to an agent without anything else changing.
#
# What this does NOT cover: a file written through the shell. PreToolUse fires
# for the Bash tool as a whole, not for the redirection inside it, so
# `sed -i` or `cat > record.md` goes around this guard. That is a real hole and
# not one worth plugging with command patterns — there are unlimited ways to
# write a file from a shell, and a guard that catches nine of them reads as
# cover while the tenth walks through. The skill's own instruction to edit
# files with Edit and Write rather than shell substitution is what keeps an
# agent on the covered path.
set -uo pipefail

input=$(cat)

# python3 rather than jq: a file path can contain spaces, quotes and backslashes,
# and grepping JSON for it works until the day it does not. python3 is already
# what this repository's other plugin scripts parse JSON with.
read -r tool_name file_path <<EOF
$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
name = d.get("tool_name", "")
path = (d.get("tool_input") or {}).get("file_path", "")
# One line, two fields; the path is last so spaces in it survive the read.
print(name, path)
' 2>/dev/null)
EOF

# Anything we could not parse is not something to block on. A guard that fails
# closed on malformed input would stop the session over its own bug.
[ -n "${file_path:-}" ] || exit 0
[ -f "$file_path" ] || exit 0          # a new file is not yet a record

case "$file_path" in *.md) ;; *) exit 0 ;; esac

# Read the status out of the frontmatter only — the block between the first
# `---` and the next. A `status:` line inside a fenced example in the body is
# prose, not state.
status=$(awk '
  NR == 1 && /^---$/ { infm = 1; next }
  infm && /^---$/     { exit }
  infm && /^status:/  {
      sub(/^status:[[:space:]]*/, "")
      gsub(/^["'\'']|["'\'']$/, "")
      print
      exit
  }
' "$file_path" 2>/dev/null)

# No frontmatter status: not a decision record, or not one this plugin made.
[ -n "$status" ] || exit 0

case "$status" in
  proposed) exit 0 ;;
esac

# Still open in every other sense but not yet decided? Only `proposed` is, so
# everything reaching here is a record that has been settled.
reason="This record's status is \"${status}\", so it is history rather than a draft.

Editing it rewrites what was decided then to match what is true now, and leaves
nobody able to tell which of the two the document is describing.

If the decision has changed, record the new one:
  <skill>/scripts/new-decision.sh --supersedes <id> \"New title\"

That writes a new record and flips exactly one line of this one. If instead this
is a correction to a record that was never right — a typo, a wrong link — that is
a human's call to make outside this session."

python3 - "$reason" <<'PY'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1],
    }
}))
PY
exit 0
