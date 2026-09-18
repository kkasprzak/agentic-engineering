---
name: coordinate-workers
description: >-
  Run work across several Claude Code worker sessions — write the task down, dispatch it, check what
  comes back, and fold it in. Use when you are handing work to other sessions and need it to survive
  their context being wiped, when a worker reports done and you have to decide whether to believe it,
  when deciding what can run in parallel, or when a worker has gone quiet mid-task. Pairs with
  spawn-worker, which starts and retires the sessions themselves.
  ONLY for a session that coordinates others. If your current task arrived as a message from another
  Claude session, you are a worker: report back, do not start coordinating.
---

# Coordinating workers

## The tracker

**Name your tracker here.** Everything below says "the tracker" and "a task item"; this paragraph is
the only place in the skill that names a real tool, so binding it to yours is a one-paragraph edit
rather than a search through the text. Write which tool it is and how to drive it — for example
*"the tracker is Linear, reached through the Linear MCP server"*, or *"the tracker is beads, driven
by the `bd` command; run `bd prime` once for its command reference"*.

Until you edit this paragraph, a coordinator will have to ask which tracker to use, which is the
cheapest possible failure and the reason this is a placeholder rather than a default.

Task items are where work and findings live. Messages are for pointing at them.

## The loop

Write the item → dispatch a short message naming it → verify what comes back → fold it in and record
what you learned. Each step below earns its place because skipping it cost something real.

## Writing the item

Write it for someone with no memory of this conversation, because that is what a worker is: a fresh
session whose context can be wiped between tasks. State the objective, the files and interfaces in
play, the acceptance criteria, and link outward for the reasoning rather than restating it.

**Corrections go into the item, not into a follow-up message.** When a decision changes after the
body is written, append it to the item and say plainly that it overrides the body where they
conflict. A correction that lives only in chat is invisible to the next reader, and to the same
worker after a restart.

Findings come back the same way. A defect a worker discovers becomes a tracker item with its
evidence, not a paragraph in a message that has to be retyped by whoever fixes it.

## Dispatching

The message is a pointer, not a copy. Name the item, then pull out the two or three things most
easily got wrong — the correction that overrides the body, the file they must not touch, the check
that matters most. Restating the item wastes their context and yours.

Answer in advance the questions that will otherwise stall them. Workers stop to ask permission for
things a coordinator cannot answer in time: whether to refactor, what to do when a brief looks
wrong, how far the scope reaches. Say it up front: make judgment calls inside the scope and report
them, stop and report anything outside it, skip optional refactoring and note what you would have
proposed.

Give them the numbers that let them recognise a wrong result — the current test totals, the branch
and commit they should be on. Without a reference figure, a worker cannot tell a broken run from a
normal one, and will report whatever it saw.

## Verifying what comes back

**Treat a report as a claim, not as evidence.** All of these happened in a single day:

- a worker reported 440 unit and 174 integration tests; the real figures were 1256 and 224
- a worker reported a green build on a branch that could not compile from clean
- a bug report contained a real stack trace *and* a false explanation of the cause; the fix built on
  the explanation and had to be redone

So check the things that are cheap to check: the commit is really on the remote, the item is really
closed, the diff touches only what the task covered, and the schema or contract gained only what was
intended. When a number looks wrong, run the build yourself rather than passing the figure on.

**A causal explanation needs its own evidence, even alongside a true observation.** That is the
lesson from the third case, and it generalises: the observed failure and the theory about why are
two separate claims arriving in one message.

Ask for shapes, not values. A report that carries live credentials can be blocked in transit by a
secrets hook and never reach you — and if it does reach you, the credentials are now in your context
and in anything you write from it.

## Running work in parallel

Parallel only helps when the work is genuinely separate. Before dispatching two workers, list the
files each will touch and check the intersection is empty; say so explicitly in both messages.
Naming the files a worker must leave alone prevented every collision; branch separation prevented
none of them.

Do not generalise from one comparison. "Everything after this is sequential" was wrong twice in one
day — recheck the overlap each time rather than carrying forward a conclusion.

When parallel work lands, fold it in one at a time: rebase, run the full build on the combined
result, then fast-forward. A clean rebase is not a green build.

Keep verification separate from implementation. Whoever wrote the code is the worst reviewer of it,
and a verifier who fixes what they find destroys the record of which finding came from where — they
report and stop.

## When a worker goes quiet

Workers stall: a usage limit resets mid-task, a background build is still running, or they are
waiting for permission nobody will grant. Diagnose before nudging — look at their working directory
for uncommitted changes and at the tracker for a claimed-but-open item — then tell them what you
found and what to do about it. That is faster than asking them what happened.

Idle notifications are mostly noise. They fire at every pause inside a task, including one that
simply finished a turn. The signal that work is done is the worker's own report.

## Gotchas

**A worker's placement is not what its panel implies.** Ask for its working directory and branch
before assigning anything. Two sessions in one day turned out to be somewhere other than expected.

**A green build is not necessarily a full build.** Stale compiled output can let a branch that
cannot compile report success. Require the clean, unfiltered build and a figure the worker can be
held to, and state the before figure so the after means something.

**Test counts read off report files can differ wildly from the build's own summary.** Say which one
you want. Here the report files omit every nested test and come out around a third of the true
figure.

**Nothing enforces a role's honesty about what it can do.** A worker described as read-only can
still hold a full shell. If it matters that something cannot be changed, do not rely on the role
description; check the tools it actually holds.
