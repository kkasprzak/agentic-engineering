#!/usr/bin/env bash
set -euo pipefail
git init -q .
cat > README.md <<'MD'
# Demo

Workers recieve their tasks from the tracker.
MD
git add -A && git -c user.name=t -c user.email=t@t commit -q -m init
