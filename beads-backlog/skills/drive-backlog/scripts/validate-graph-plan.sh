#!/usr/bin/env bash
# Check a `bd create --graph` plan before creating anything, by comparing what the
# plan declares against what a dry run says would actually be created.
#
# Usage: validate-graph-plan.sh plan.json
#
# Exit 0 when the dry run would create exactly the nodes and edges the plan
# declares, 2 when it would silently create fewer, 1 on a usage or `bd` error.
#
# Gotchas this exists to catch, because `bd` reports none of them as errors:
#   - Dependencies written as a `deps` array inside a node parse without complaint
#     and create NOTHING. The dry run then says "N issue(s) and 0 edge(s)", which
#     reads as success. Only a top-level `edges` array with from_key/to_key/type
#     creates dependencies.
#   - Unknown fields are dropped with a warning and the run continues, so a
#     misspelled key costs you a silently different graph.
#   - A dry run validates structure only; its own output says a live create may
#     still be rejected once dependencies resolve. Passing here is necessary, not
#     sufficient.
set -uo pipefail

plan=${1:-}
if [ -z "$plan" ] || [ ! -f "$plan" ]; then
  echo "usage: validate-graph-plan.sh plan.json" >&2
  exit 1
fi

want_nodes=$(jq '(.nodes // []) | length' "$plan" 2>/dev/null) || {
  echo "not valid JSON: $plan" >&2
  exit 1
}
want_edges=$(jq '(.edges // []) | length' "$plan" 2>/dev/null)

# A node carrying its own deps is the silent-drop case; name it before bd hides it.
node_deps=$(jq '[.nodes // [] | .[] | select(has("deps"))] | length' "$plan" 2>/dev/null)

out=$(bd create --graph "$plan" --dry-run 2>&1)
status=$?
if [ $status -ne 0 ]; then
  printf '%s\n' "$out" >&2
  exit 1
fi

got_nodes=$(printf '%s' "$out" | sed -n 's/.*would create \([0-9]*\) issue(s).*/\1/p' | head -1)
got_edges=$(printf '%s' "$out" | sed -n 's/.*and \([0-9]*\) edge(s).*/\1/p' | head -1)

fail=0

if printf '%s' "$out" | grep -q 'unknown field'; then
  printf '%s\n' "$out" | grep 'unknown field' >&2
  echo "^ dropped silently by bd; fix the field names" >&2
  fail=2
fi

if [ "$node_deps" -gt 0 ]; then
  echo "$node_deps node(s) carry a 'deps' array. bd ignores it - move them to a top-level 'edges' array." >&2
  fail=2
fi

if [ "${got_nodes:-0}" != "$want_nodes" ] || [ "${got_edges:-0}" != "$want_edges" ]; then
  echo "plan declares $want_nodes node(s) and $want_edges edge(s); dry run would create ${got_nodes:-0} and ${got_edges:-0}" >&2
  fail=2
fi

if [ $fail -ne 0 ]; then
  exit $fail
fi

echo "ok: $want_nodes node(s), $want_edges edge(s) - plan and dry run agree"
