---
name: split-work
description: >-
  Turn a plan that has already been decided into tracker items an agent with no memory of the
  conversation can pick up, ordered by dependency and confirmed before anything is created. Trigger
  on "break this into tasks", "turn the plan into items", "create the work items for this", "what
  order do we do this in", "prepare this for dispatch", "rozbij to na zadania", "zrób z tego
  zadania", "co po kolei". Not for deciding the approach — that comes first, from a
  solution-architect — and not for sizing work for a refinement conversation.
---

# Splitting decided work into items

**Goal:** a set of items whose order is explicit and each of which a fresh session can start
without being told anything that is not written down.

**Constraints:** nothing is created until the shape is agreed. The reasoning stays in the parent and
is linked, never copied into each item.

This skill decides *what the items are*. Writing the body of one is covered by
`coordinate-workers` under "Writing the item"; creating them, linking dependencies and finding what
already exists is the backlog provider's job. Load it rather than inventing commands.

## Gotchas

- **An item that reads perfectly to you can be unstartable.** You are reading it with the
  conversation still in your head. The test is not "is this clear" but "could a session that never
  saw the discussion begin it". Anything that fails that test is the whole failure mode this skill
  exists for.
- **Work almost certainly already exists.** Check before proposing anything, and when you find an
  overlapping epic, say so and ask whether to reopen, extend or supersede it. A second epic for the
  same scope splits the history quietly and neither half is wrong enough to notice.
- **Time is the wrong size rule.** Three hours in one file is easier for an agent than thirty
  minutes spread across eight modules. Size by the **working set** — how much has to be held at
  once — and let duration follow. A unit that cannot be verified without pulling in more context is
  too big regardless of how quick it looks.
- **Creating is the expensive step.** A topology is free to rearrange while it is still text and
  costly once items exist with ids and edges pointing at them. Present it and wait; do not create
  "a first batch" to save a round trip.
- **"Would it still work if we stopped here?"** Ask it of every item. Either answer is fine — some
  changes only make sense atomically — but an unrecorded answer is what turns a half-finished
  sequence into a broken repository nobody expected.
- **Rollback notes on code-only items are noise.** Write them where reversal is genuinely hard:
  database migrations, infrastructure, a contract someone else consumes.

## Shaping the set

Prefer a vertical slice that changes a little of each layer over a horizontal one that finishes a
layer. For a breaking change, the shape is expand → migrate → contract, so that each step leaves
something that runs.

Prefer a dependency over a duplicate. Two items that both set up the same thing will diverge the
moment one is edited.

Carry into an item only the constraints, risks and validation that change how **that** item is
executed. Everything else belongs to the parent, and the item links to it. If you find yourself
re-explaining the architecture, that is the signal to link instead.

## Before creating

Present the proposed shape inline — the parent, the item titles, and the dependency edges — and
wait for approval. Then create, through the provider.
