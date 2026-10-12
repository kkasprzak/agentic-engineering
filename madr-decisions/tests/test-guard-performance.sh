#!/usr/bin/env bash
# The guard hook must stay cheap, because it runs on every Edit, Write and Bash
# call in every session the plugin is enabled in.
#
# This is separate from the correctness suites on purpose. A timing assertion
# belongs nowhere near them: it can fail on a loaded machine without anything
# being wrong, and a correctness suite that cries wolf stops being read.
#
# It exists because the bug it catches is invisible to a pass/fail suite. The
# first version gated on `case "$input" in *[0-9][0-9][0-9][0-9]-*.md*`, which
# backtracks on bash 3.2 — still the default shell on macOS — on every `NNNN-`
# partial match in the payload. Every case passed. A Write of a log full of
# timestamps took 5.3 seconds for 500 KB and nearly a minute for 2 MB.
#
# The bound is deliberately loose. The real figure is around 60 ms, so two
# seconds is a thirty-fold margin: slow enough never to flap on a busy runner,
# fast enough that the quadratic version fails it by more than double.
set -uo pipefail

GUARD="$(cd "$(dirname "$0")/../hooks" && pwd)/guard-accepted-record.sh"
[ -x "$GUARD" ] || { echo "not executable: $GUARD" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || {
  echo "  skip: python3 is missing, so the guard abstains and times nothing"
  echo
  echo "0 passed, 0 failed (skipped)"
  exit 0
}

LIMIT_MS=2000
fail=0

# A payload with many `digits-dash` runs and no record path: the shape that made
# the old gate backtrack. Nothing here should be refused, so the whole cost is
# the gate deciding there is nothing to do.
payload=$(python3 - <<'PY'
import json
# Varying digit runs rather than one repeated line: measured at 6.4 s against
# the old gate and 2.5 s against a fixed line, so this shape keeps the failing
# side well clear of the limit.
body = "\n".join("2024-01-15 req=%d-%d ok" % (i, i) for i in range(500_000 // 28))
print(json.dumps({
    "cwd": "/tmp",
    "tool_name": "Write",
    "tool_input": {"file_path": "/tmp/app.log", "content": body},
}))
PY
)

echo "guard-accepted-record.sh performance"
printf '  payload: %s KB of timestamped log lines\n' "$(( ${#payload} / 1024 ))"

start=$(python3 -c 'import time; print(int(time.time() * 1000))')
printf '%s' "$payload" | "$GUARD" >/dev/null 2>&1
end=$(python3 -c 'import time; print(int(time.time() * 1000))')
elapsed=$(( end - start ))

if [ "$elapsed" -le "$LIMIT_MS" ]; then
  printf '  ok   gate returns in %s ms (limit %s)\n' "$elapsed" "$LIMIT_MS"
else
  printf '  FAIL gate took %s ms, limit is %s\n' "$elapsed" "$LIMIT_MS"
  printf '       A payload with no record in it must cost almost nothing.\n'
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then echo "1 passed, 0 failed"; else echo "0 passed, 1 failed"; fi
[ "$fail" -eq 0 ]
