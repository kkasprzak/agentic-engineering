#!/usr/bin/env bash
# List the worker roles this plugin ships: each one's --role spelling, the
# effort it runs at, and its description, which says what the role is for.
#
# Read straight from the plugin's agents/ folder, so a role added there shows up
# here with no other edit. Only this plugin's roles are listed; spawn-worker.sh
# --role still accepts any agent definition the CLI can resolve.
set -euo pipefail

case "${1:-}" in
  -h|--help) echo "Usage: list-roles.sh"; exit 0 ;;
  "") ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 -I "$HERE/roles.py" list
