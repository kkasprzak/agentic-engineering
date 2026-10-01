#!/usr/bin/env bash
# PostToolUse(Bash): after a git push, tell the agent to close the static-analysis
# loop on the open PR for the branch it just pushed, without the user asking.
#
# Silent unless the pushed branch actually has an open pull request.
# Needs `gh` (authenticated) and `jq`; exits quietly if either is missing.
set -uo pipefail

payload=$(cat)

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
case "$cmd" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# `gh pr view` still resolves a merged or closed PR for the branch, so filter on state.
pr=$(gh pr view --json number,url,state \
  -q 'select(.state == "OPEN") | [(.number|tostring), .url] | @tsv' 2>/dev/null) || exit 0
[ -n "$pr" ] || exit 0

num=${pr%%$'\t'*}
url=${pr##*$'\t'}

read -r -d '' msg <<EOF || true
A commit was just pushed to the branch of open PR #${num} (${url}). This work is
not finished until that push's static analysis has been read. Call the Skill tool
with skill: "check-pr-analysis" and follow it for this PR. The user does not want
to have to remember to ask for this.
EOF

jq -cn --arg msg "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $msg
  }
}'
