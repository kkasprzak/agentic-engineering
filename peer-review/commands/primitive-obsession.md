---
name: primitive-obsession
description: Review a plan or diff for primitives that should be types — a string, number, boolean or map standing in for a domain concept — and relay what the reviewer finds
argument-hint: "[path or git range]"
---

Target: $ARGUMENTS

If no target was given, pick one and say which: a plan or document from this conversation, the
uncommitted diff, or the current branch's diff against the repository's default branch. Resolve that
branch rather than assuming it: `git symbolic-ref --short refs/remotes/origin/HEAD` prints it as
`origin/<branch>`, so strip the remote prefix, and fall back to whichever of `main` or `master`
exists when that ref is not set locally. If none of the three targets exist, ask.

Spawn the `type-review` agent with just the path or git range — no summary of the work, no reason
it was built that way, nothing about which types you already have in mind. Relay its findings
verbatim, including a plain "nothing found".
