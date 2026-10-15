---
name: obscure-test
description: Review tests for whether a reader can tell what each one is trying to show — Obscure Test, Eager Test, Mystery Guest, magic literals — and relay what the reviewer finds
argument-hint: "[test file path or git range]"
---

Target: $ARGUMENTS

If no target was given, pick one and say which: test files named in this conversation, the
uncommitted diff, or the current branch's diff against the repository's default branch. Resolve that
branch rather than assuming it: `git symbolic-ref --short refs/remotes/origin/HEAD` prints it as
`origin/<branch>`, so strip the remote prefix, and fall back to whichever of `main` or `master`
exists when that ref is not set locally. If none of the three targets exist, ask.

When the target is a diff, check that it touches at least one test file. If it touches none, say so
and stop: there is nothing for this lens to read, and a reviewer sent to an empty target reports
noise.

Spawn the `test-review` agent with just the path or git range — no summary of the work, no reason
the tests were written that way, nothing about which ones you already suspect. Relay its findings
verbatim, including a plain "nothing found".
