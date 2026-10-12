#!/usr/bin/env bash
# Move a decision record along its lifecycle, and fill in who decided.
#
# Usage:
#   set-status.sh 0014 accepted                      a proposal carries
#   set-status.sh 0014 rejected                      a proposal does not
#   set-status.sh 0014 deprecated                    it stopped applying
#   set-status.sh chat/0003 accepted                 a narrowed record
#   set-status.sh 0014 accepted --decision-makers "Ana, Bo" --consulted "DBA guild"
#   set-status.sh 0014 --informed "frontend team"    fields only, status unchanged
#
#   --root <dir>   records live somewhere other than docs/adr
#
# THIS SCRIPT IS DELIBERATELY NOT IN THE SKILL'S allowed-tools.
#
# Accepting a record is what arms the guard hook: from that moment no agent can
# edit it. If an agent could run this without asking, it could accept its own
# work and lock it against everyone else, which is the opposite of the point.
# Leaving it out of the grant means every run stops for the user's approval,
# and the approval prompt — showing the id and the status — IS the human
# decision. That is a mechanism the harness already enforces, rather than a
# sentence in a skill asking an agent to restrain itself.
#
# Transitions, which are this plugin's rule and not MADR's. MADR defines no
# lifecycle at all: its template calls every frontmatter field optional and
# ends its status list with an ellipsis. So the narrow set here exists to catch
# mistakes, not to implement a standard:
#
#   proposed  -> accepted     the decision carried
#   proposed  -> rejected     it did not
#   accepted  -> deprecated   it stopped applying, with nothing replacing it
#
# Anything else is refused. `superseded by <id>` is not set here — that is
# new-decision.sh --supersedes, which writes the replacement and flips this
# record in one step, so the two can never disagree.
#
# `date` is left alone. MADR reads it as "when the decision was last updated";
# this plugin reads a record as dated history, so the date stays the day it was
# written. That divergence is in the README.
set -uo pipefail

root="docs/adr"
id=""
new_status=""
set_makers=0; makers=""
set_consulted=0; consulted=""
set_informed=0; informed=""

need_value() {
  [ "$2" -ge 2 ] || { echo "$1 needs a value after it" >&2; exit 1; }
}

usage() { sed -n '2,13p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root)             need_value --root $#;             root="$2";      shift 2 ;;
    --decision-makers)  need_value --decision-makers $#;  makers="$2";    set_makers=1;    shift 2 ;;
    --consulted)        need_value --consulted $#;        consulted="$2"; set_consulted=1; shift 2 ;;
    --informed)         need_value --informed $#;         informed="$2";  set_informed=1;  shift 2 ;;
    -h|--help)          usage; exit 0 ;;
    -*)                 echo "unknown option: $1" >&2; exit 1 ;;
    *)
      if [ -z "$id" ]; then id="$1"
      elif [ -z "$new_status" ]; then new_status="$1"
      else echo "unexpected argument: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [ -z "$id" ]; then
  usage >&2
  exit 1
fi

if [ -z "$new_status" ] && [ "$set_makers$set_consulted$set_informed" = "000" ]; then
  echo "nothing to do: give a status, or at least one of --decision-makers," >&2
  echo "--consulted, --informed." >&2
  exit 1
fi

case "$root" in
  ""|/*)          echo "refusing: --root must be a relative path inside the repository, got '$root'" >&2; exit 1 ;;
  ..|../*|*/..|*/../*) echo "refusing: --root must not climb out of the repository, got '$root'" >&2; exit 1 ;;
esac

# `0014`, or `chat/0014` for a narrowed record. Nothing else: no paths, no `..`.
case "$id" in
  [0-9][0-9][0-9][0-9]) dir="$root"; num="$id" ;;
  */*/*)                echo "refusing: '$id' is not a record id" >&2; exit 1 ;;
  */[0-9][0-9][0-9][0-9])
    scope="${id%/*}"; num="${id##*/}"
    case "$scope" in
      ""|.|..|*' '*) echo "refusing: '$id' is not a record id" >&2; exit 1 ;;
    esac
    dir="$root/$scope" ;;
  *)
    echo "refusing: '$id' is not a record id" >&2
    echo "  Use 0014 for a system record, or chat/0014 for a narrowed one." >&2
    exit 1 ;;
esac

matches=$(find "$dir" -maxdepth 1 -name "$num-*.md" 2>/dev/null | sort)
count=$(printf '%s' "$matches" | grep -c . || true)
if [ "$count" -eq 0 ]; then
  echo "refusing: no record $id under $dir/" >&2
  exit 2
fi
if [ "$count" -gt 1 ]; then
  { echo "refusing: $id matches more than one file:"; printf '  %s\n' $matches; } >&2
  exit 2
fi
file="$matches"

# --- read the record's current state ----------------------------------------
#
# Same reading as new-decision.sh and the guard hook: frontmatter only, CR
# stripped with string functions rather than a regex escape, quotes removed.
# All three have to agree about what a record is, or one refuses the others'
# work.
read_key() {
  awk -v want="$1" '
    { line = $0
      if (substr(line, length(line)) == "\r") line = substr(line, 1, length(line) - 1) }
    NR == 1 && line == "---" { infm = 1; next }
    infm && line == "---"    { exit }
    infm && index(line, want ":") == 1 {
        sub(/^[a-z-]+:[[:space:]]*/, "", line)
        sub(/[[:space:]]+$/, "", line)
        gsub(/^["'"'"']|["'"'"']$/, "", line)
        print line
        exit
    }
  ' "$2"
}

if ! head -1 "$file" | tr -d '\r' | grep -q '^---$'; then
  echo "refusing: $file has no frontmatter to update" >&2
  exit 2
fi

current=$(read_key status "$file")
if [ -z "$current" ]; then
  echo "refusing: $file has no status field in its frontmatter" >&2
  exit 2
fi

case "$current" in
  proposed|accepted|rejected|deprecated|"superseded by "*) ;;
  *)
    {
      echo "refusing: $file does not look like a decision record"
      echo "  Its status is \"${current}\", which is not one MADR defines."
      echo "  Changing it would rewrite a file this plugin did not create."
    } >&2
    exit 2 ;;
esac

# --- is the move allowed ----------------------------------------------------

if [ -n "$new_status" ]; then
  allowed=0
  case "$current->$new_status" in
    "proposed->accepted"|"proposed->rejected"|"accepted->deprecated") allowed=1 ;;
  esac

  if [ "$allowed" -ne 1 ]; then
    {
      echo "refusing: $id cannot go from \"${current}\" to \"${new_status}\"."
      echo

      # Explain in terms of this record, not by reciting the rule. A refusal
      # that only lists the allowed moves leaves the reader to work out which
      # of them applies to the file in front of them.
      case "$new_status" in
        superseded*)
          echo "  Superseding is not a status you set. Write the record that replaces"
          echo "  this one, and both ends are updated in a single step:"
          echo "    new-decision.sh --root ${dir} --supersedes ${num} \"<new title>\""
          echo ;;
      esac

      case "$current" in
        "superseded by "*)
          echo "  This record was already replaced by ${current#superseded by }, and its"
          echo "  status follows from that record existing. Act on the replacement." ;;
        accepted)
          echo "  An accepted decision is history. It can be deprecated once it stops"
          echo "  applying, or replaced by a record that supersedes it — not reopened." ;;
        rejected|deprecated)
          echo "  This record is closed. If the question is live again, that is a new"
          echo "  decision with its own record, which can refer back to this one." ;;
        proposed)
          echo "  A proposal can be accepted or rejected; those are the only moves it"
          echo "  can make while it is still a draft." ;;
      esac

      echo
      echo "  Moves this script makes: proposed->accepted, proposed->rejected,"
      echo "  accepted->deprecated."
    } >&2
    exit 2
  fi
fi

# --- rewrite the frontmatter, and nothing else ------------------------------

tmp="$file.tmp.$$"

if ! awk -v want_status="$new_status" \
         -v set_makers="$set_makers"       -v makers="$makers" \
         -v set_consulted="$set_consulted" -v consulted="$consulted" \
         -v set_informed="$set_informed"   -v informed="$informed" '
  function emit(key, value,   out) {
      out = key ": " value
      print out cr
  }
  { line = $0; cr = ""
    if (substr(line, length(line)) == "\r") {
        cr = "\r"; line = substr(line, 1, length(line) - 1) } }

  NR == 1 && line == "---" { infm = 1; print; next }

  # Closing fence: add any requested key the frontmatter did not already carry,
  # so a hand-written record missing `consulted:` still gets one rather than
  # silently dropping what was asked for.
  infm && line == "---" {
      if (set_makers    && !seen_makers)    emit("decision-makers", makers)
      if (set_consulted && !seen_consulted) emit("consulted", consulted)
      if (set_informed  && !seen_informed)  emit("informed", informed)
      infm = 0; print; next
  }

  infm && index(line, "status:") == 1 {
      if (want_status != "") { emit("status", "\"" want_status "\""); next }
      print; next
  }
  infm && index(line, "decision-makers:") == 1 {
      seen_makers = 1
      if (set_makers) { emit("decision-makers", makers); next }
      print; next
  }
  infm && index(line, "consulted:") == 1 {
      seen_consulted = 1
      if (set_consulted) { emit("consulted", consulted); next }
      print; next
  }
  infm && index(line, "informed:") == 1 {
      seen_informed = 1
      if (set_informed) { emit("informed", informed); next }
      print; next
  }
  { print }
' "$file" > "$tmp"; then
  rm -f "$tmp"
  echo "failed: could not rewrite $file; it is unchanged" >&2
  exit 1
fi

if ! mv "$tmp" "$file"; then
  rm -f "$tmp"
  echo "failed: could not replace $file; it is unchanged" >&2
  exit 1
fi

if [ -n "$new_status" ]; then
  echo "$file  $current → $new_status"
else
  echo "$file  fields updated, status unchanged ($current)"
fi

if [ "$new_status" = "accepted" ]; then
  echo "  → it is protected from here on: an agent can no longer edit it." >&2
  echo "    If it turns out to be wrong, record the decision that replaces it." >&2
fi
