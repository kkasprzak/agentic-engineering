---
name: check-sonar-analysis
description: >-
  Read a pull request's SonarQube / SonarCloud analysis and prove it belongs to the commit that was
  just pushed, not the one before it. Trigger on "what does sonar say", "check sonar", "did that pass
  sonar", "any new issues on this PR", "is the quality gate green", "did the analysis pass", after
  any push to an open PR, and whenever a push hook says to follow up on an analysis.
  Not for running the analysis — the pipeline does that.
---

# Check a PR's static analysis

**Goal:** the findings you report are the ones produced by the commit you just pushed, and the ones
you caused are gone.

**Constraints:** read the PR's analysis, not the branch's. Prove freshness before reporting
anything. Fix what your commits introduced; leave the rest to the user.

## Gotchas

These are the ways this goes wrong. Everything else here is ordinary work.

- **A findings query answers instantly and is usually the previous commit's run.** The pipeline
  takes minutes. This is the failure the skill was written after — it happened twice in one session,
  identically both times. Never report a result you have not proved is current.
- **Zero open findings proves nothing**, and neither does a green quality-gate badge. Both survive
  untouched from the previous analysis.
- **Proof of freshness, best first.** The check run is bound to a commit by GitHub, so
  `gh api repos/<owner>/<repo>/commits/<sha>/check-runs` naming the analysis with
  `"head_sha": "<the sha you pushed>"` settles it outright. The others depend on findings existing
  at all: a finding whose creation timestamp postdates the push, or findings that were open before
  now showing `CLOSED` (only a newer run closes them). If you cannot prove it, say so and keep
  waiting.
- **A change with no analyzable code has no findings to reason about**, so every finding-based proof
  silently becomes unavailable — on a docs-only diff, `new_lines` is not even reported. That is the
  case where the check-run binding is the only proof there is, and also the case most likely to be
  mistaken for "scanned and clean".
- **A PR key and a branch name are different things in SonarQube.** Passing a branch name where a PR
  key belongs returns another project's data with no error.
- **Query open issues only** (`OPEN`, `CONFIRMED`). The default returns closed ones too, which reads
  as a pile of problems that are already fixed.
- **A fix usually shifts the remaining issues onto new lines**, so the second analysis often reports
  findings the first one did not. One clean pass is not the same as settled.
- **`gh pr checks` exits non-zero when a check failed**, which is not the same as still running.
  Parse the table; do not trust the exit status.
- **Saying you will come back later is itself a false report** when nothing will wake you. A turn
  that ends with the pipeline still pending has not checked anything, however it is worded.

## Waiting for the run

`scripts/wait-for-analysis.sh [PR] --check 'sonar|build'` blocks until nothing is pending and exits
2 on timeout. It already handles the `gh` exit-status trap and the not-yet-created-check trap.

Do not query findings while that job is pending. That is precisely how you get the previous run.

**Only background the wait if something will actually wake you.** In a one-shot run — `claude -p`,
a hook-triggered turn, anything that ends when the turn does — backgrounding it means abandoning it,
and "I'll pick this back up when the checks settle" becomes a promise nobody keeps. Run the script in
the foreground there and finish the job in the same turn. If you genuinely cannot wait, say the
analysis was **not** read, rather than implying you will return to it.

## Separating yours from theirs

Pre-existing findings are the user's call. Name them, do not fix them — a static-analysis follow-up
is not a licence to widen the change.
