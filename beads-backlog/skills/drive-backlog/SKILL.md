---
name: drive-backlog
description: >-
  Binds agent-crew's abstract backlog to Beads: when the crew says "a task item", it means a bead,
  driven by `bd`. Trigger on "create a task/issue/bead", "what is ready to pick up", "claim this",
  "close that one", "is there already work for this", "link these two", "stwórz zadanie", "weź
  zadanie", "zamknij zadanie", and whenever a coordinator needs to act on the backlog rather than
  talk about it. The store side only — how work should be cut into items is a separate job.
---

# The backlog is Beads

Wherever `agent-crew` says *the tracker* or *a task item*, it means a bead, reached through `bd`.
That is the whole binding.

**`bd` documents itself for agents.** Run `bd prime` for its workflow context, and
`bd <command> --help` for anything specific. Do not work from memory of its flags — it is built
agent-first and its own help is better than a copy of it would be.

What follows is only what that help does not say.

## Gotchas

- **A graph plan fails quietly.** Dependencies written as a `deps` array inside a node parse
  without complaint and create **zero edges**. The dry run then reports `3 issue(s) and 0 edge(s)`,
  which reads as success unless you look at the second number. Only a top-level `edges` array
  creates dependencies.
- **Unknown fields are dropped with a warning, not an error**, and the run continues — so a
  misspelled key buys you a silently different graph.
- **`bd` does not resolve its database from the current directory.** Run from an unrelated path it
  can still find, and write to, another project's backlog. `bd where` and `bd context` say which
  one is active; worth one call before the first write of a session.
- **A dry run validates structure only.** Its own output says a live create may still be rejected
  once dependencies resolve. Passing is necessary, not sufficient.
- **A claim is a lease, not a flag.** That is what makes `agent-crew`'s "a worker has gone quiet"
  recoverable mechanically: `bd reclaim` returns stale claims to ready, and `bd heartbeat` is how a
  worker that is still alive keeps its own.

## The graph plan

`bd create --graph plan.json` creates a set of items and their dependencies in one call. The flag's
help names the file but not its shape:

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

**Run `scripts/validate-graph-plan.sh plan.json` before creating.** It dry-runs the plan and
compares what the plan declares against what would actually be created, so the silent cases above
become an exit code instead of a number nobody reads. Exit 2 means the graph would land wrong.
