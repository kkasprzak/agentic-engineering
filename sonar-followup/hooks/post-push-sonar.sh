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
A commit was just pushed to the branch of open PR #${num} (${url}).

This work is NOT finished yet. Before you report it as done:

1. Wait for that PR's pipeline to finish - specifically the job that runs the
   static analysis (SonarQube / SonarCloud). Poll it in the background rather
   than blocking.
2. Read the analysis findings for the PR.
3. Check you are looking at the NEW analysis, not a stale cached one: compare
   the findings' creation timestamps and line numbers against the commit you
   just pushed. Reporting a stale run as clean is the failure mode to avoid.
4. Fix anything your own commits introduced, push again, and repeat until the
   findings you caused are gone.
5. Tell the user the outcome either way - clean or not.

The user explicitly does not want to have to remember to ask for this.
EOF

jq -cn --arg msg "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $msg
  }
}'
