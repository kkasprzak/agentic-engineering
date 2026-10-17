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

This file is the tracker. Each item is a level-two heading with its id; an epic lists its children.

## EPIC-1 — Greetings

Children: TASK-1, TASK-2. TASK-2 depends on TASK-1.

## TASK-1 — Add a greeting helper

Status: open

Create `src/greeting.py` with `greet(name: str) -> str` returning `"Hello, <name>!"`, with a test in
`tests/test_greeting.py`.

## TASK-2 — Use the greeting in main

Status: open

Make `src/app.py` print `greet("world")` instead of `hello`. Update or add a test.
MD
git add -A && git -c user.name=t -c user.email=t@t commit -q -m init
