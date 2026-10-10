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

# Without python3 this hook cannot read the harness's JSON and cannot emit a
# refusal, so it allows the edit. That is the right default — a guard that
# cannot see has not passed, it has abstained, and failing closed would wedge
# every session on a machine missing an interpreter. But it must not do it
# quietly: an installed guard that is permanently inert looks exactly like one
# that is working.
if ! command -v python3 >/dev/null 2>&1; then
  echo "madr-decisions: python3 not found, so decision records are NOT protected" >&2
  echo "  in this session. Install python3 or disable the plugin; do not assume" >&2
  echo "  an accepted record is safe from an agent's edit." >&2
  exit 0
fi

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

# A frontmatter `status` on its own is not enough to call something a decision
# record, and neither is a four-digit prefix. This hook runs on every Edit and
# Write in every session the plugin is enabled in, so a false positive blocks
# unrelated work — and because the refusal prints a runnable command, following
# it rewrites the innocent file's frontmatter and drops a skeleton beside it.
#
# Two signals are required, and both were wrong before:
#
#   - the filename, four digits and a dash — but NOT a date. `2024-01-15-post.md`
#     matched the old pattern, so Jekyll posts, daily notes and dated changelogs
#     were all treated as records.
#   - the status, which must be one MADR actually defines. Everything that was
#     not `proposed` used to be treated as a decision taken, so `published`,
#     `done`, `final` and a template's placeholder were all locked, with a
#     message that read "This record is \"draft\": a decision that was taken".
basename=$(basename "$file_path")
case "$basename" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) exit 0 ;;   # a date, not an id
  [0-9][0-9][0-9][0-9]-*.md) ;;
  *) exit 0 ;;
esac

# Read the status out of the frontmatter only — the block between the first
# `---` and the next. A `status:` line inside a fenced example in the body is
# prose, not state.
#
# `\r?$` throughout: a record saved with CRLF endings has `---\r` as its first
# line, and an anchored `^---$` does not match it. Without this the whole block
# below reads as "no frontmatter", the guard exits 0, and a CRLF record is
# silently unprotected — a bypass that looks exactly like a file the guard
# correctly ignored. Trailing whitespace is stripped for the same class of
# reason: `status: proposed  ` would otherwise fail to equal `proposed` and the
# guard would deny an edit to an open draft, which is the way a guard gets
# switched off.
status=$(awk '
  NR == 1 && /^---\r?$/ { infm = 1; next }
  infm && /^---\r?$/    { exit }
  infm && /^status:/    {
      sub(/\r$/, "")
      sub(/^status:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      gsub(/^["'\'']|["'\'']$/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
  }
' "$file_path" 2>/dev/null)

# No frontmatter status: not a decision record, or not one this plugin made.
[ -n "$status" ] || exit 0

# Deny only on a status MADR defines as settled. Anything else — `published`,
# `done`, a template placeholder, a status this plugin has never heard of — is
# somebody else's document or a record in a state we cannot reason about, and
# in both cases the safe answer is to stay out of the way.
case "$status" in
  accepted|rejected|deprecated|"superseded by "*) ;;
  *) exit 0 ;;
esac

# --- work out what to tell the agent to run instead --------------------------
#
# A refusal that says "supersede it instead" and leaves the agent to work out
# the identifier, the directory and the path to the script is a refusal it will
# get wrong twice before getting it right, and each attempt costs a turn. Since
# everything needed is derivable here, derive it.

abs_dir=$(dirname "$file_path")       # keep the absolute form: the filesystem
record_dir="$abs_dir"                  # check below must not run against the
record_id=$(basename "$file_path" | cut -c1-4)   # hook's own working directory

# Paths relative to where the session is working read better than absolute ones
# and are what the agent has to type.
cwd=$(printf '%s' "$input" | python3 -c '
import json, sys
try:    print(json.load(sys.stdin).get("cwd", ""))
except Exception: pass
' 2>/dev/null)
shown_path="$file_path"
case "$record_dir" in
  "$cwd"/*) record_dir="${record_dir#"$cwd"/}" ;;
esac
case "$shown_path" in
  "$cwd"/*) shown_path="${shown_path#"$cwd"/}" ;;
esac

# Is this record narrowed, or at system scope? It decides the identifier that
# gets written into the old record, and getting it wrong is not harmless: naming
# the record's own directory as --root always RUNS, but for a narrowed record it
# writes `superseded by 0001` where the convention is `superseded by chat/0001`.
# Read under that convention, `0001` is a system record about something else, so
# the chain silently points at the wrong file. A command that fails is better
# than one that quietly writes the wrong thing.
#
# This is decided by looking rather than guessing: a scope directory sits inside
# a root that holds numbered records of its own.
abs_parent=$(dirname "$abs_dir")
scope_name=$(basename "$abs_dir")
narrowed=0
for sibling in "$abs_parent"/[0-9][0-9][0-9][0-9]-*.md; do
  [ -e "$sibling" ] || continue
  narrowed=1
  break
done

# The command the agent types is relative, so relativise the parent too.
parent_dir="$abs_parent"
case "$parent_dir" in
  "$cwd"/*) parent_dir="${parent_dir#"$cwd"/}" ;;
esac

script="${CLAUDE_PLUGIN_ROOT:-<plugin>}/skills/record-decision/scripts/new-decision.sh"
if [ "$narrowed" -eq 1 ]; then
  new_root="$parent_dir"
  supersede_cmd="${script} --root ${new_root} --scope ${scope_name} --supersedes ${scope_name}/${record_id} \"<title of the new decision>\""
  fresh_cmd="${script} --root ${new_root} --scope ${scope_name} \"<title of the new decision>\""
else
  supersede_cmd="${script} --root ${record_dir} --supersedes ${record_id} \"<title of the new decision>\""
  fresh_cmd="${script} --root ${record_dir} \"<title of the new decision>\""
fi

# The advice has to differ by status, because "supersede it" is wrong for three
# of the four. Telling an agent to supersede an already-superseded record sends
# it at a command the script refuses outright.
case "$status" in
  superseded\ by\ *)
    replacement="${status#superseded by }"
    what="This record was already replaced by ${replacement}, so it is two steps behind rather
than one. Superseding it again is refused by the generator as well: it would
repoint this record and leave ${replacement} claiming to replace something that
no longer refers back to it.

Read ${replacement} first. If the decision has changed again, supersede that one
— follow the chain to its end and supersede the record at the end of it."
    ;;
  rejected)
    what="This decision was declined, so there is nothing here to supersede — a rejected
record is the account of a road not taken, and it stays that way.

If the question is being reopened, write a new record with no --supersedes and
refer to this one in its Context:

  ${fresh_cmd}"
    ;;
  deprecated)
    what="This record no longer applies and has been marked so. Editing it to describe
what is true now would turn a retired decision into a live one.

If something has taken its place, record that and supersede this one:

  ${supersede_cmd}

If nothing replaced it — it simply stopped mattering — leave it as it is."
    ;;
  *)
    what="This record is \"${status}\": a decision that was taken, which makes it history
rather than a draft. Editing it rewrites what was decided then to match what is
true now, and leaves no reader able to tell which of the two they are looking at.

If the decision has changed, record the new one:

  ${supersede_cmd}

That writes a new record and changes exactly one line of this one — its status."
    ;;
esac

reason="Refused: ${shown_path} is a decision record and is no longer open for editing.

${what}

If this is instead a correction to a record that was never right — a typo, a
broken link — that is a human's call to make outside this session. Say what you
found and leave the file alone."

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
