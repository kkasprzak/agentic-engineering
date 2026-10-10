#!/usr/bin/env bash
# Create a decision record, or the record that supersedes one, in MADR format.
#
# The format is never typed from memory and never hand-edited into existence:
# that is the whole point. A skeleton that is generated cannot be got wrong.
#
# Usage:
#   new-decision.sh "Title"                          system scope
#   new-decision.sh --scope chat "Title"             narrowed to docs/adr/chat/
#   new-decision.sh --supersedes 0014 "Title"        supersede a system record
#   new-decision.sh --supersedes chat/0007 "Title"   supersede a narrowed one
#   new-decision.sh --print "Title"                  skeleton to stdout, write nothing
#   new-decision.sh --root docs/adr "Title"          records live somewhere else
#
# Scope is the directory and nothing else, so it cannot drift from reality:
#   docs/adr/           system-wide
#   docs/adr/<name>/    narrowed to a module or a group of modules
#
# Identifiers are `0014` at system scope and `chat/0014` when narrowed. Numbering
# is per directory, so two people working in different scopes cannot take the
# same number. Gaps are normal and numbers are never reused.
#
# Exit 0 on success, 1 on a usage error, 2 when the target of --supersedes cannot
# be used (missing, ambiguous, no frontmatter, or out of scope).
#
# Things this absorbs so nobody has to hold them:
#   - only MADR's five frontmatter keys. A sixth field of your own is how a
#     format stops being a format.
#   - status starts at `proposed`. `RFC` is not offered: it is a different kind
#     of document, not a state a decision record can hold.
#   - superseding edits ONE line of the old record. Everything else in that file
#     is history and stays byte-for-byte as it was.
#   - a narrowed record may not supersede a system one. A module cannot overrule
#     a decision that binds other modules.
#   - BSD and GNU sed differ: `\+` silently does nothing on BSD and leaves spaces
#     in filenames. Hence `sed -E` throughout.
set -uo pipefail

root="docs/adr"
scope=""
supersedes=""
print_only=0
title=""

# Every option that takes a value checks the value is there before shifting past
# it. Without that check a trailing `--scope` makes `shift 2` fail, and since
# there is no `set -e` the loop spins on the same argument forever — the script
# hangs rather than complaining, and an agent running it blocks until its tool
# times out.
need_value() {
  [ "$2" -ge 2 ] || { echo "$1 needs a value after it" >&2; exit 1; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)      need_value --scope $#;      scope="$2";      shift 2 ;;
    --supersedes) need_value --supersedes $#; supersedes="$2"; shift 2 ;;
    --root)       need_value --root $#;       root="$2";       shift 2 ;;
    --print)      print_only=1; shift ;;
    -h|--help)    sed -n '2,36p' "$0"; exit 0 ;;
    --)           shift; [ $# -gt 0 ] && title="$1"; break ;;
    -*)           echo "unknown option: $1" >&2; exit 1 ;;
    *)            title="$1"; shift ;;
  esac
done

if [ -z "$title" ]; then
  echo 'usage: new-decision.sh [--scope <name>] [--supersedes <id>] [--print] "Title"' >&2
  echo '       use -- before a title that starts with a dash' >&2
  exit 1
fi

# A scope is one directory name, not a path. Left unchecked, `--scope ../elsewhere`
# writes outside the root entirely, and `--scope a/b` quietly builds a third tier —
# which would make the identifier `a/b/0014` and break the promise that two tiers
# and one subdirectory make identifiers unambiguous by construction.
case "$scope" in
  */*|..|.|*' '*)
    echo "refusing: --scope must be a single directory name, got '$scope'" >&2
    echo "  Scope is one level below $root/. A decision spanning more than one" >&2
    echo "  module belongs at system scope, without --scope." >&2
    exit 1 ;;
esac

# --root and --supersedes need the same containment --scope has. Without it,
# `--supersedes ../../elsewhere/0042` rewrites a file outside the records tree
# entirely — the id is split on the last slash and the remainder is pasted onto
# the root with no normalisation — and --root writes a skeleton anywhere the
# user can write. The skill grants this script with a blanket argument glob, so
# both are reachable without a permission prompt.
case "$root" in
  ""|/*)
    echo "refusing: --root must be a relative path inside the repository, got '$root'" >&2
    exit 1 ;;
  ..|../*|*/..|*/../*)
    echo "refusing: --root must not climb out of the repository, got '$root'" >&2
    exit 1 ;;
esac

if [ -n "$supersedes" ]; then
  # `0014` at system scope, `chat/0014` when narrowed. Nothing else: no absolute
  # paths, no `..`, no deeper nesting.
  ok_id=0
  case "$supersedes" in
    [0-9][0-9][0-9][0-9]) ok_id=1 ;;
    */*/*) ok_id=0 ;;
    */[0-9][0-9][0-9][0-9])
      case "${supersedes%/*}" in
        ""|.|..|*/*|*' '*) ok_id=0 ;;
        *) ok_id=1 ;;
      esac ;;
  esac
  if [ "$ok_id" -ne 1 ]; then
    echo "refusing: --supersedes takes a record id, got '$supersedes'" >&2
    echo "  Use 0014 for a system record, or chat/0014 for a narrowed one." >&2
    exit 1
  fi
fi

if [ -n "$scope" ]; then dir="$root/$scope"; else dir="$root"; fi

# --- resolve the record being superseded ------------------------------------

old_file=""
if [ -n "$supersedes" ]; then
  case "$supersedes" in
    */*) old_scope="${supersedes%/*}"; old_num="${supersedes##*/}"; old_dir="$root/$old_scope" ;;
    *)   old_scope="";                 old_num="$supersedes";       old_dir="$root" ;;
  esac

  # A narrowed record may not overrule one that binds other modules.
  if [ -n "$scope" ] && [ "$scope" != "$old_scope" ]; then
    {
      echo "refusing: a record in $dir/ cannot supersede $supersedes"
      if [ -z "$old_scope" ]; then
        echo "  that is a system-scoped decision, and it binds more than this scope."
        echo "  If it really changes, create the new record without --scope."
      else
        echo "  that belongs to another scope ($root/$old_scope/)."
        echo "  A decision spanning both scopes belongs at system scope, without --scope."
      fi
    } >&2
    exit 2
  fi

  matches=$(find "$old_dir" -maxdepth 1 -name "$old_num-*.md" 2>/dev/null | sort)
  count=$(printf '%s' "$matches" | grep -c . || true)
  if [ "$count" -eq 0 ]; then
    echo "refusing: no record $supersedes under $old_dir/" >&2
    exit 2
  fi
  if [ "$count" -gt 1 ]; then
    { echo "refusing: $supersedes matches more than one file:"; printf '  %s\n' $matches; } >&2
    exit 2
  fi
  old_file="$matches"

  # A record saved with CRLF endings opens with `---\r`, which an anchored
  # `^---$` does not match. Refusing it as "no frontmatter" would leave such a
  # record impossible to supersede through the sanctioned path, while the guard
  # hook refuses to let it be edited either — a record with no way forward.
  #
  # `tr -d '\r'` rather than a `\r` in the pattern. BSD grep reads `\r` in a
  # BRE as carriage return and GNU grep reads it as a literal `r`, so a pattern
  # written that way works on macOS and silently fails on every mainstream
  # Linux. Measured on GNU grep 3.8: `^---\r\?$` matched `---r` and did not
  # match `---<CR>`. Deleting the character first needs no agreement about what
  # an escape means.
  if ! head -1 "$old_file" | tr -d '\r' | grep -q '^---$'; then
    echo "refusing: $old_file has no frontmatter to update" >&2
    exit 2
  fi

  # Read status from the frontmatter only — the block between the first `---`
  # and the next one. A plain grep matches a `status:` line inside a fenced
  # example in the body too, and the rewrite further down would then edit the
  # prose instead of the header.
  old_status=$(awk '
    # Strip a trailing CR with string functions rather than a regex escape:
    # "\r" in an awk STRING is portable, `\r` inside a regex literal is not
    # guaranteed across awks. Every rule below then works on a clean line.
    { line = $0
      if (substr(line, length(line)) == "\r") line = substr(line, 1, length(line) - 1) }
    NR == 1 && line == "---" { infm = 1; next }
    infm && line == "---"    { exit }
    infm && line ~ /^status:/ {
        sub(/^status:[[:space:]]*/, "", line)
        sub(/[[:space:]]+$/, "", line)
        # Strip the optional quotes, exactly as the guard hook does. The two
        # have to read a status the same way or they disagree about what a
        # record is, and then one of them is refusing the other'"'"'s work.
        gsub(/^["'"'"']|["'"'"']$/, "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
        exit
    }
  ' "$old_file")

  if [ -z "$old_status" ]; then
    echo "refusing: $old_file has no status field in its frontmatter" >&2
    exit 2
  fi

  # Supersede only a record this format recognises. `0014-foo.md` is a shape
  # plenty of files share — a dated blog post, a numbered changelog — and
  # flipping a `status:` line in one of those is corruption, not bookkeeping.
  # The guard hook applies the same test before it refuses an edit; the two
  # have to agree about what a record is or one of them is wrong.
  case "$old_status" in
    proposed|accepted|rejected|deprecated|"superseded by "*) ;;
    *)
      {
        echo "refusing: $old_file does not look like a decision record"
        echo "  Its status is \"${old_status}\", which is not one MADR defines."
        echo "  Superseding it would rewrite a file this plugin did not create."
      } >&2
      exit 2 ;;
  esac

  # Superseding something that was already superseded breaks the chain silently:
  # the old record is repointed at the new one, and whatever superseded it first
  # is left claiming to replace a record that no longer refers back to it. The
  # record to supersede is the one at the end of the chain.
  case "$old_status" in
    *superseded\ by*)
      {
        echo "refusing: $supersedes is already $old_status"
        echo "  Superseding it again would repoint it and leave the record that"
        echo "  replaced it pointing at nothing. Supersede the current record"
        echo "  instead — follow the chain to the end."
      } >&2
      exit 2 ;;
  esac
fi

# --- next number, per directory ---------------------------------------------

next=0
if [ -d "$dir" ]; then
  for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
    [ -e "$f" ] || continue
    n=$((10#$(basename "$f" | cut -c1-4)))
    [ "$n" -ge "$next" ] && next=$((n + 1))
  done
fi
id=$(printf '%04d' "$next")
if [ -n "$scope" ]; then ref="$scope/$id"; else ref="$id"; fi

slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
if [ -z "$slug" ]; then
  echo "refusing: the title produces an empty filename" >&2
  exit 1
fi

# --- the skeleton -----------------------------------------------------------

read -r -d '' skeleton <<EOF || true
---
status: "proposed"
date: $(date +%F)
decision-makers:
consulted:
informed:
---

# ${title}

## Context and Problem Statement

{Two or three sentences, or a short story. What forced the decision? Name the
components involved so the scope is explicit.}

<!-- This is an optional element. Feel free to remove. -->
## Decision Drivers

* {a quality, concern, constraint or force that pushed the choice}

## Considered Options

* {option 1}
* {option 2}

## Decision Outcome

Chosen option: "{option}", because {justification}.

<!-- This is an optional element. Feel free to remove. -->
### Consequences

* Good, because {consequence}
* Bad, because {consequence}

<!-- This is an optional element. Feel free to remove. -->
### Confirmation

{How compliance with this decision is checked - a fitness function, an ArchUnit
rule, a review step. Not a list of the tests that happened to be written.}

<!-- This is an optional element. Feel free to remove. -->
## Pros and Cons of the Options

### {option 1}

* Good, because {argument}
* Neutral, because {argument}
* Bad, because {argument}

### {option 2}

* Good, because {argument}
* Bad, because {argument}

<!-- This is an optional element. Feel free to remove. -->
## More Information

{Related decisions. When this should be revisited, and on what signal.}
EOF

if [ "$print_only" = "1" ]; then
  printf '%s\n' "$skeleton"
  exit 0
fi

path="$dir/$id-$slug.md"
if [ -e "$path" ]; then
  echo "refusing: $path already exists" >&2
  exit 1
fi

# Every write is checked from here down. There is no `set -e`, so an unchecked
# failure leaves the script printing the path it meant to create and exiting 0 —
# a tool reporting work it did not do, which is the exact failure this plugin
# was written to stop. It must not be the first thing the plugin does.

if ! mkdir -p "$dir"; then
  echo "refusing: cannot create $dir/" >&2
  exit 1
fi

if ! printf '%s\n' "$skeleton" > "$path"; then
  echo "refusing: cannot write $path" >&2
  rm -f "$path"
  exit 1
fi

# --- flip the superseded record, and nothing else ---------------------------

if [ -n "$old_file" ]; then
  tmp="$old_file.tmp.$$"
  # Only the frontmatter's status line. The body may legitimately contain a
  # `status:` line inside an example, and rewriting that would corrupt prose.
  if awk -v repl="status: \"superseded by $ref\"" '
       { line = $0; cr = ""
         if (substr(line, length(line)) == "\r") {
             cr = "\r"; line = substr(line, 1, length(line) - 1) } }
       NR == 1 && line == "---" { infm = 1; print; next }
       infm && line == "---"    { infm = 0; print; next }
       infm && !done && line ~ /^status:/ {
           # Keep the line ending the file already uses. Writing an LF line into
           # a CRLF file would leave one line out of step with every other and
           # show up as a second change in the diff, which is exactly what the
           # one-line promise says will not happen.
           print repl cr
           done = 1
           next
       }
       { print }
     ' "$old_file" > "$tmp" && mv "$tmp" "$old_file"; then
    echo "$old_file  → superseded by $ref"
  else
    rm -f "$tmp"
    # The new record exists but the old one was not flipped. Leaving both would
    # produce two live records for one decision, which is worse than neither.
    rm -f "$path"
    {
      echo "failed: could not update $old_file"
      echo "  $path was removed again, so nothing was half-done."
      echo "  Check the file is writable, then run this command once more."
    } >&2
    exit 1
  fi
fi

echo "$path"
echo "  → open it and replace the {placeholders} in place. Do not rewrite the file," >&2
echo "    do not retype the frontmatter, and leave status at proposed." >&2
