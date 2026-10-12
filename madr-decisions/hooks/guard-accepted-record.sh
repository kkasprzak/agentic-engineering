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
# Two routes reach a record, and both are covered. `Edit` and `Write` name their
# target, so those are simple. A `Bash` call does not: it carries one string, and
# whether that string writes a given file is not decidable in general. So the
# shell side reads the command, looks for a path shaped like a record, and only
# acts when the command also looks like a write — a redirect, an in-place sed or
# perl, tee, cp, mv, a python open for writing. Reading a record stays free.
#
# This used to be argued the other way: that catching nine spellings and missing
# the tenth reads as cover without being it. Then a live agent was asked to
# accept a record and reached for `sed -i` on its first try, with a literal path,
# and nothing stopped it. The tenth spelling is exotic; the first is what
# actually happens.
#
# What still gets through, and the README says so: a path the shell assembles at
# run time. `F=docs/adr/0014-x.md; sed -i ... $F` has no record in the command
# text, and this hook does not run shells.
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

# The cheap gate, before python starts. This hook is on every Edit, Write and
# Bash call in every session the plugin is enabled in, and the overwhelming
# majority of them have nothing to do with a decision record. A record filename
# is four digits, a dash and `.md`; if nothing in the payload looks like one,
# there is nothing here to protect and the expensive part never runs.
#
# This replaced a list of eleven `if: "Bash(sed *)"` entries in hooks.json. The
# list was both redundant — the script has to decide whether a command writes
# anyway, so it could not trust the filter — and incomplete, with no `ex`, `ed`,
# `install`, `gsed` or an absolute path to any of them. One matcher and one
# decision beat eleven lines that have to be kept in step with nothing.
#
# `grep`, not a `case` glob. bash 3.2 — still the default on macOS — backtracks
# on every `NNNN-` partial match, so a Write of a log full of timestamps took
# 5.3 seconds for 500 KB and nearly a minute for 2 MB. The hook runs on every
# Write and every Bash call, so that is the session stalling, not a slow check.
# bash 5 does not have the problem; grep does not have it anywhere.
printf '%s' "$input" | grep -qE '[0-9]{4}-[^"]*\.md' || exit 0

# One interpreter launch, in a helper beside this file. `guard-record-paths.py`
# is not a hook of its own — nothing registers it and the harness never runs it;
# it shares the `guard-` prefix so the two read as one thing. The path-picking
# needs apostrophes that a `python3 -c '...'` string cannot hold, and this hook
# used to start python three times per call: once for the paths, once for a tool
# name nothing read, once per candidate for the cwd.
#
# First line of the output is the session's working directory, the rest are
# candidate paths.
here=$(cd "$(dirname "$0")" && pwd)
parsed=$(printf '%s' "$input" | python3 "$here/guard-record-paths.py" 2>/dev/null)

cwd=$(printf '%s\n' "$parsed" | sed -n '1p')
candidates=$(printf '%s\n' "$parsed" | sed '1d')

# Anything we could not parse is not something to block on. A guard that fails
# closed on malformed input would stop the session over its own bug.
[ -n "${candidates:-}" ] || exit 0

# One call can name several records — a shell command can touch more than one.
# The first settled record found ends the call, because one is enough to refuse.
examine() {
file_path="$1"
[ -f "$file_path" ] || return 0        # a new file is not yet a record
case "$file_path" in *.md) ;; *) return 0 ;; esac

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
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) return 0 ;;   # a date, not an id
  [0-9][0-9][0-9][0-9]-*.md) ;;
  *) return 0 ;;
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
[ -n "$status" ] || return 0

# Deny only on a status MADR defines as settled. Anything else — `published`,
# `done`, a template placeholder, a status this plugin has never heard of — is
# somebody else's document or a record in a state we cannot reason about, and
# in both cases the safe answer is to stay out of the way.
case "$status" in
  accepted|rejected|deprecated|"superseded by "*) ;;
  *) return 0 ;;
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

# `cwd` came out of the single parse above.
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

This refusal is the rule, not an obstacle in front of it. The same change made
through the shell — sed, a redirect, tee — reaches some records without passing
here, and where it does that is a gap in this guard rather than a way around the
decision. A record changed that way is destroyed just the same, and nobody is
told.

If this is instead a correction to a record that was never right, a typo or a
broken link, stop and say so. That is a person's call, not this session's."

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
# Deny printed: nothing else in this call matters.
exit 0
}

# Split on newlines only, so a path containing spaces stays one candidate. Not a
# pipe into `while read`: that runs in a subshell, where the `exit` inside
# `examine` would end the subshell and let the script carry on past a refusal it
# had already decided to make.
IFS='
'
for candidate in $candidates; do
  [ -n "$candidate" ] || continue
  examine "$candidate"
done

exit 0
