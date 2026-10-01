---
name: check-pr-analysis
description: >-
  Close the static-analysis loop on a pull request you just pushed to: wait for the pipeline, read
  what SonarQube / SonarCloud reported, prove the analysis is not a stale run, and fix what your own
  commits introduced. Use after pushing to an open PR, when asked what Sonar says about a PR, when a
  quality gate or new-issue count needs checking, or when a push hook tells you to follow up on an
  analysis. Not for running the analysis yourself — the pipeline does that.
---

# Check a PR's static analysis

The job is not done when the push succeeds. It is done when the analysis of **that push** has been
read and the findings you caused are gone.

## The trap this exists for

A findings query answers instantly and looks authoritative. It is usually the **previous** commit's
analysis, because the pipeline takes minutes. Reporting that as clean is the failure this skill was
written after — it happened twice in one session, the same way both times.

**Never report a result without first proving it belongs to the commit you pushed.**

## Steps

### 1. Wait for the pipeline

Find the job that publishes the analysis (`gh pr checks <N>`; in most repos it is the build job, with
a separate SonarCloud check alongside it). Poll it in the background rather than blocking the
session — a build is typically several minutes.

Do not query the findings while that job is pending. You will get the previous run.

### 2. Read the findings

Use whatever the session has: the SonarQube MCP server, or the project's own tooling. Scope the
query to the PR, not the branch — they are different things in SonarQube, and a branch name passed
where a PR key belongs returns the wrong project's data silently.

Ask for open issues only (`OPEN`, `CONFIRMED`). A plain query returns closed ones too, which reads
as a long list of problems that are already fixed.

### 3. Prove the analysis is not stale

This step is not optional. Any one of these is sufficient proof:

- Findings carry a creation timestamp **after** the push.
- Findings previously reported as open now show as `CLOSED` — that only happens on a newer run.
- The line numbers match the file as it stands now, not as it stood before the fix.

Zero open findings on its own proves nothing. Neither does a passing quality-gate badge, which can
be left over from the previous analysis.

If you cannot prove freshness, say so and keep waiting. Do not round "I think it is fine" up to
"it is clean".

### 4. Fix what you caused

Separate findings your commits introduced from ones that were already there. Fix yours. Pre-existing
ones are the user's call, not yours — mention them, do not silently widen the change.

Push, then start again at step 1. A partial fix is the common case: the first pass often leaves
issues the fix itself shifted onto new lines.

### 5. Report

Say what was found, what was fixed, and **what proved the analysis was current**. If it is clean,
say which run you read and how you know it was that run.

Report it either way. Silence reads as "not checked".
