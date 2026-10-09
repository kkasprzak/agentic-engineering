---
name: coordinate-workers
description: >-
  Run work across several Claude Code worker sessions — write the task down, dispatch it, check what
  comes back, and fold it in. Use when you are handing work to other sessions and need it to survive
  their context being wiped, when a worker reports done and you have to decide whether to believe it,
  when deciding what can run in parallel, or when a worker has stopped mid-task without reporting —
  including one blocked by a connection error or a dialog nobody will answer. Pairs with
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

**When you cannot write the item yet, that is the signal to dispatch differently.** If you do not
know which files are in play, or whether the change can land in steps, or whether the task as stated
is even the right one, you are not ready to brief a developer — and briefing one anyway produces a
confident implementation of the wrong shape. Send a `solution-architect` first. Its output is the
items the rest of this loop consumes: an approach, a sequence, what was rejected and why, and the
questions it could not settle. Verify those the same way you verify any other report; a plan is no
more trustworthy for being about the future.

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

**Send it with `notify_when_idle: true`.** A worker whose turn dies sends no report, and the report
is otherwise your only signal — so without the flag you wait on a session that is never coming back.
*Knowing when a worker has stopped* covers what to do when the notice arrives.

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

## Knowing when a worker has stopped

A worker whose turn dies never reports, so waiting for its report is waiting forever. `ListAgents`
does not settle it either: a worker that finished and one whose turn died both read `idle`. It is
worth a call to rule out the ones still `busy`, and worth nothing beyond that.

The subscription from *Dispatching* is what closes it. The notice fires once, when that session goes
idle — measured on a five-step task, which produced one notice quoting the fifth step, not the first.
It says the worker stopped, not that it succeeded.

So when it arrives, ask one question: **did a report come too?** A report means the work is done, and
you verify it the way you verify any other. No report means the worker stopped without finishing.

**Then look at the panel.** `spawn-worker` ships `check-worker.sh --name <worker>`, which prints the
screen; load that skill for the path and the permission to run it.

| on screen | state | what to do |
|---|---|---|
| `Waiting for API response · will retry in …` | backing off, will return by itself | leave it alone |
| `API Error: …`, then `· done HH:MM`, then a clean prompt | the turn died | resume it |
| a spinner `…(24s` with no `done` | working | nothing |
| `do you want`, `allow this`, `❯ 1.` | waiting on a dialog | a message queues behind it — this one needs the panel |
| a usage or quota limit, with or without a reset time | waiting on the clock | leave it; resume after the reset |
| anything else, unreadable, or empty | **unknown** | say so; never read it as "fine" |

The first and last rows are the ones that cost you something to get wrong. A retry countdown is a
recovery in progress, so treat it as working rather than stopped. And a screen matching no row is a
finding, not a pass — the script prints what is there precisely so you can say you do not recognise
it.

**Look soon after the notice.** The screen is the current view, not a history: whatever that session
does next pushes the explanation off the top. Observed on a panel checked later, after it had taken
further work — the error that had been plainly visible was gone.

**Resuming is a message, not a keystroke.** `SendMessage` to a stopped worker starts a new turn —
verified on a session sitting on a dead turn, which went to `busy`, finished the work and reported
back. The dialog is the exception, since a message only drains at the worker's next tool round.

**Put `notify_when_idle: true` on the resume as well.** The subscription is one-shot and you have
just spent it. Without a fresh one the second stall produces no notice, which is the failure you are
in the middle of fixing.

Say what you found when you resume one, rather than asking it what happened. Its working directory
and the tracker tell you whether the task is half-landed — uncommitted changes, an item claimed but
still open — and a worker that has just lost a turn knows less about that than you do.

**Resume once per cause, then escalate.** Note each resume against the task. A second stall with the
same cause is not a blip and is not yours to absorb: stop resuming and say so to whoever is
accountable. Resuming without a limit turns a failure loop into something that reads as progress in
a report — the same defect as a test that passes with and without the fix.

**A worker wedged mid-turn never produces the notice**, because it never goes idle. That is the gap
in all of this, and it is a real one. No threshold in minutes belongs here — it would be wrong for
the next project — but `busy` far longer than the task warrants is worth a look, and it costs one
`ListAgents` to see.

**Treat the first notice of a session as a test that the signal reaches you at all.** `SendMessage`
says it subscribes *"provided that session runs in the same permission class as this one (or is one
this session spawned) or asserts none; otherwise it is shown to your user in the transcript"* —
and `spawn-worker` launches workers under `--permission-mode auto`, which a coordinator need not be
in. Only the matching case was ever exercised here. If no notice arrives from a worker you know has
finished, assume it went to your user and say so, rather than waiting on it.

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
