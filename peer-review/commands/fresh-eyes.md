---
name: fresh-eyes
description: Re-examine something that already exists — a plan, a diff, a document — with a reviewer given no context but the artifact, and relay what it finds
argument-hint: "[path or git range]"
---

Target: $ARGUMENTS

If no target was given, pick one and say which: a plan or document from this conversation, the
uncommitted diff, or the current branch's diff against the repository's default branch. Resolve that
branch rather than assuming it: `git symbolic-ref --short refs/remotes/origin/HEAD` prints it as
`origin/<branch>`, so strip the remote prefix, and fall back to whichever of `main` or `master`
exists when that ref is not set locally. If none of the three targets exist, ask.

Spawn the `fresh-eyes-review` agent with just the path or git range. Relay its findings.
