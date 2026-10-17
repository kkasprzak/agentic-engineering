# Eval suite — taking a "deliver" request

One flow per suite. This one covers the moment a coordinator is handed planned work: "deliver
TASK-1". The questions are which skills it loads, in what order, and whether it dispatches to a
worker session or quietly does the work itself or through a subagent.

## Running it

```bash
make -C agent-crew/evals          # what each target does
make -C agent-crew/evals eval     # the full suite
make -C agent-crew/evals pilot    # one run per case
```

`run.sh` is the same wrapper as `madr-decisions/evals/run.sh`, including the Docker Desktop
workaround described there. Reports stay local (`--no-publish`).

The headline number is **Δ** — the with-plugin score minus the without-plugin score.

Run it by hand when a skill description, `coordinate-workers`, or `list-roles.sh` changes. A full
pass is 24 short sessions, about $4 and ten minutes.

First full pass (agent-crew 0.12.0, 2026-10-17): every with-plugin run scored 1.00. Without the
plugin, the agent implemented the task itself in every run of `01` and `02`.

| case | with | without | Δ |
|---|---|---|---|
| `01-deliver-item` | 1.00 | 0.14 | +0.86 |
| `02-deliver-epic` | 1.00 | 0.17 | +0.83 |
| `03-which-workers` | 1.00 | 0.00 | +1.00 |
| `04-neg-plain-task` | 1.00 | 1.00 | 0.00 |

## The cases

| case | what it tests |
|---|---|
| `01-deliver-item` | "Deliver TASK-1." loads the coordination skill, then the spawning skill, runs `list-roles.sh`, never calls `Agent`, and does not write the task's code itself. |
| `02-deliver-epic` | The same entry point phrased as an epic with two child items. |
| `03-which-workers` | "Which workers can I spawn?" runs `list-roles.sh` and names each role with what it is for. |
| `04-neg-plain-task` | Should not fire: a one-line typo fix is done directly, with no crew skill loaded. |

The tracker in the sandbox is a `TASKS.md` written by each case's scaffold. A beads store would need
`bd` and the beads-backlog plugin inside the sandbox; a markdown file tests the same decision
without them.

## How the graders work

There is no public reference for these grader types; the mechanics below were read from the Claude
Code 2.1.302 eval runner.

- **`tool_used` with `input_match`** is a regex over the call's input, so `tool: Skill,
  input_match: coordinate-workers` checks for that one skill, not for any skill.
- **`arm: both` is required on every `tool_used: Skill` grader that is meant to count.** Without it,
  under the default with/without ablation, the grader is shown as a "plugin fired" indicator and is
  excluded from the score in both arms. It looks like a check and moves nothing.
- **"Must not call X" is `min: 0, max: 0, arm: both`.** Leaving out `min` keeps it at 1.
- **`tool_order` compares the first matching call on each side** and fails if either never happened.

There is no cmux in the sandbox, so `spawn-worker.sh` exits 3 there. That is deliberate: the
correct outcome is a coordinator that says it could not start a worker, not one that falls back to
implementing the task. `coordinator-did-not-implement` (the task's file was not created) is the
outcome grader that catches the fallback, and it is the one the without-plugin arm fails on.

## What this suite does not measure

- **Competition from other plugins.** The sandbox loads only this plugin, so another skill that also
  reacts to "deliver" phrasing is not present. This measures whether these descriptions work, not
  whether they win.
- **The dispatch itself.** No worker is spawned, briefed or verified. Everything after the first
  spawn attempt is out of reach without cmux.
