#!/usr/bin/env bash
# PostToolUse(Bash): after a push that actually reached the remote, tell the agent
# to read what the pipeline reports about it, without the user asking.
#
# Silent unless the branch has an open pull request AND something was really
# pushed. Needs `gh` (authenticated) and `jq`; exits quietly if either is missing.
set -uo pipefail

payload=$(cat)

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
case "$cmd" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# A push that moved nothing starts no pipeline, so following up on it would read
# the PREVIOUS commit's analysis - the exact failure this plugin exists to stop.
case "$cmd" in
  *--dry-run*|*" -n "*) exit 0 ;;
esac

out=$(printf '%s' "$payload" | jq -r '[.tool_response.stdout // "", .tool_response.stderr // ""] | join("\n")' 2>/dev/null) || out=""
case "$out" in
  *"Everything up-to-date"*|*"[rejected]"*|*"failed to push"*) exit 0 ;;
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
with skill: "pipeline-watch:check-sonar-analysis" and follow it for this PR. The
user does not want to have to remember to ask for this.
EOF

jq -cn --arg msg "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $msg
  }
}'
