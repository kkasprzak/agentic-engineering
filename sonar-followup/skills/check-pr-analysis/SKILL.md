---
name: check-pr-analysis
description: >-
  Read a pull request's SonarQube / SonarCloud analysis and prove it belongs to the commit that was
  just pushed, not the one before it. Trigger on "what does sonar say", "check sonar", "did that pass
  sonar", "any new issues on this PR", "is the quality gate green", "sprawdź sonara", "co mówi
  sonar", after any push to an open PR, and whenever a push hook says to follow up on an analysis.
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
- **Proof of freshness** is any one of: a creation timestamp after the push; findings that were open
  before now showing `CLOSED` (only a newer run closes them); line numbers matching the file as it
  stands rather than as it stood. If you cannot prove it, say so and keep waiting.
- **A PR key and a branch name are different things in SonarQube.** Passing a branch name where a PR
  key belongs returns another project's data with no error.
- **Query open issues only** (`OPEN`, `CONFIRMED`). The default returns closed ones too, which reads
  as a pile of problems that are already fixed.
- **A fix usually shifts the remaining issues onto new lines**, so the second analysis often reports
  findings the first one did not. One clean pass is not the same as settled.
- **`gh pr checks` exits non-zero when a check failed**, which is not the same as still running.
  Parse the table; do not trust the exit status.

## Waiting for the run

`scripts/wait-for-analysis.sh [PR] --check 'sonar|build'` blocks until nothing is pending and exits
2 on timeout. It already handles the `gh` exit-status trap and the not-yet-created-check trap. Run
it in the background rather than holding the session.

Do not query findings while that job is pending. That is precisely how you get the previous run.

## Separating yours from theirs

Pre-existing findings are the user's call. Name them, do not fix them — a static-analysis follow-up
is not a licence to widen the change.
