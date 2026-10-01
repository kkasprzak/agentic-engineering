# beads-backlog

`agent-crew` names the moves. This plugin knows how to make them.

The crew deliberately does not name a tracker — it says *the tracker* and *a task item* throughout,
so that the store is a choice rather than an assumption. Installing this makes that choice:
the backlog is [Beads](https://github.com/gastownhall/beads), driven by `bd`.

Swap this plugin for another provider and the crew is unchanged.

## What it does not do

It does not restate `bd`. Beads is built agent-first and ships its own agent-facing context —
`bd prime` — which is better than any copy of it would be. The skill points there and then covers
only the things that help cannot tell you:

- the `--graph` plan schema, which the flag's help names but does not describe
- the way that plan fails **quietly** — dependencies written on a node parse cleanly and create
  nothing, so a dry run reports issues created and zero edges, and that reads as success
- that `bd` does not resolve its database from the current directory, so a command run from the
  wrong place can write to another project's backlog
- where the crew's "a worker has gone quiet" problem meets Beads' claim leases

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install agent-crew@agentic-engineering
claude plugin install beads-backlog@agentic-engineering
```

Useful on its own, but it exists to complete `agent-crew`.

## Requirements

`bd` on the PATH, and a Beads database for the repository you are working in. Without one, `bd`
will tell you so more clearly than this plugin could.
