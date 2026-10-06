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

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)      scope="${2:-}"; shift 2 ;;
    --supersedes) supersedes="${2:-}"; shift 2 ;;
    --root)       root="${2:-}"; shift 2 ;;
    --print)      print_only=1; shift ;;
    -h|--help)    sed -n '2,38p' "$0"; exit 0 ;;
    -*)           echo "unknown option: $1" >&2; exit 1 ;;
    *)            title="$1"; shift ;;
  esac
done

if [ -z "$title" ]; then
  echo 'usage: new-decision.sh [--scope <name>] [--supersedes <id>] [--print] "Title"' >&2
  exit 1
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

  if ! head -1 "$old_file" | grep -q '^---$'; then
    echo "refusing: $old_file has no frontmatter to update" >&2
    exit 2
  fi
  if ! grep -qE '^status:' "$old_file"; then
    echo "refusing: $old_file has no status field" >&2
    exit 2
  fi
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

mkdir -p "$dir"
printf '%s\n' "$skeleton" > "$path"

# --- flip the superseded record, and nothing else ---------------------------

if [ -n "$old_file" ]; then
  tmp="$old_file.tmp.$$"
  # Only the first status line, which is the one in the frontmatter.
  awk -v repl="status: \"superseded by $ref\"" '
    !done && /^status:/ { print repl; done=1; next }
    { print }
  ' "$old_file" > "$tmp" && mv "$tmp" "$old_file"
  echo "$old_file  → superseded by $ref"
fi

echo "$path"
echo "  → open it and replace the {placeholders} in place. Do not rewrite the file," >&2
echo "    do not retype the frontmatter, and leave status at proposed." >&2
