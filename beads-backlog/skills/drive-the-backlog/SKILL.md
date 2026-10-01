---
name: drive-the-backlog
description: >-
  Binds agent-crew's abstract backlog to Beads: when the crew says "a task item", it means a bead,
  driven by `bd`. Trigger on "create a task/issue/bead", "what is ready to pick up", "claim this",
  "close that one", "is there already work for this", "stwórz zadanie", "weź zadanie", "zamknij
  zadanie", and whenever a coordinator needs to act on the backlog rather than talk about it. The
  store side only — how work should be cut into items is a separate job.
---

# The backlog is Beads

Wherever `agent-crew` says *the tracker* or *a task item*, it means a bead, reached through `bd`.
That is the whole binding.

**`bd` documents itself for agents.** Run `bd prime` for its workflow context and `bd --help` or
`bd <command> --help` for anything specific. Do not work from memory of its flags — it is built
agent-first and its own help is better than a copy of it would be.

What follows is only what `bd --help` will not tell you.

## The graph plan schema, and how it fails quietly

`bd create --graph plan.json` creates a set of items and their dependencies in one call. Its help
names the flag but not the shape, and the shape has a trap in it:

```json
{
  "nodes": [
    { "key": "expand",   "title": "Add the new column alongside the old" },
    { "key": "migrate",  "title": "Backfill and switch readers" },
    { "key": "contract", "title": "Drop the old column" }
  ],
  "edges": [
    { "from_key": "migrate",  "to_key": "expand",  "type": "blocks" },
    { "from_key": "contract", "to_key": "migrate", "type": "blocks" }
  ]
}
```

`key` is a local handle for wiring edges; Beads assigns the real ids.

- **Dependencies written inside a node do nothing.** A `deps` array on a node parses without
  complaint and creates **zero edges**. The dry run then says `3 issue(s) and 0 edge(s)` — which
  reads as success unless you look at the second number. Only the top-level `edges` array works.
- **Unknown fields are dropped with a warning, not an error**, and the run continues. Wrong field
  names cost you silently.

So: always `--dry-run` first, and **read the edge count**, not the absence of an error.

## Know which database you are about to write to

`bd` does not resolve its database from the current directory. Run it from an unrelated path and it
can still find and write to another project's backlog. `bd where` and `bd context` answer which one
is active — worth one call before the first write of a session.

## The lease is the recovery path for a quiet worker

A claim is a lease rather than a flag, so `agent-crew`'s "a worker has gone quiet mid-task" has a
mechanical answer here instead of a human noticing something parked in `in_progress`. `bd reclaim`
is that answer; `bd heartbeat` is how a worker that is still alive keeps its claim.
