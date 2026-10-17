#!/usr/bin/env bash
set -euo pipefail
git init -q .
mkdir -p src
cat > src/app.py <<'PY'
def main():
    print("hello")
PY
cat > TASKS.md <<'MD'
# Tasks

This file is the tracker. Each item is a level-two heading with its id.

## TASK-1 — Add a greeting helper

Status: open

Create `src/greeting.py` with a function `greet(name: str) -> str` that returns
`"Hello, <name>!"`, and a test for it in `tests/test_greeting.py`.

Acceptance: the test passes with `python -m pytest`.
MD
git add -A && git -c user.name=t -c user.email=t@t commit -q -m init
