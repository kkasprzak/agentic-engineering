#!/usr/bin/env bash
# Run the eval suite from the plugin root, working around a local sandbox blocker if there is one.
#
# The Bash sandbox refuses to start when ~/.docker holds symlinks, which Docker Desktop's
# cli-plugins/ and bin/lib/ always do. Where that is the case this builds a throwaway HOME that
# links the real configuration and simply has no .docker in it. Nothing in the real home directory
# is read-write or modified, and a machine without Docker Desktop never takes this path.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

home_override=()
if find "$HOME/.docker" -type l -print -quit 2>/dev/null | grep -q .; then
  sandbox_home="$(mktemp -d)"
  trap 'rm -rf "$sandbox_home"' EXIT
  # Only what the claude CLI needs to find its own config and the login keychain. Nothing else from
  # the real home is reachable from inside the sandbox — in particular not .ssh or .gitconfig.
  for f in .claude .claude.json Library .config; do
    if [ -e "$HOME/$f" ]; then ln -s "$HOME/$f" "$sandbox_home/$f"; fi
  done
  echo ">> ~/.docker holds symlinks, so the Bash sandbox will not start."
  echo ">> Running with HOME=$sandbox_home — your own home directory is untouched."
  home_override=(env "HOME=$sandbox_home")
fi

cd "$root"
set -x
"${home_override[@]}" claude plugin eval . \
  --ablation with-without \
  --scaffold \
  --allow-tools Write Edit Bash \
  --no-publish \
  "$@"
