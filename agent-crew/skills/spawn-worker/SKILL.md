---
name: spawn-worker
description: >-
  Start and retire Claude Code worker sessions in cmux panels so they can be given work over
  SendMessage. Use when coordinating parallel work across several sessions — "spawn a worker",
  "give me another agent", "I need someone in this role", "start two workers on this", "shut that
  worker down", "close the agent and clean up its worktree", "wipe its context before the next
  task", or when you are about to hand a task to a session that does not exist yet. Also lists the
  worker roles it ships, with what each is for — "which workers can I spawn", "what roles are
  available", "who should take this task". Any agent definition the session can resolve works as a
  role. Retiring also clears up the worker's git
  worktree on request, and refuses to discard one still holding uncommitted or unpushed work.
  Clearing wipes a worker's conversation between tasks while keeping the session, its role and its
  address. Requires cmux.
  ONLY for a session that coordinates others. If your current task arrived as a message from
  another Claude session, you are a worker, not a coordinator, and this skill is not for you —
  report back instead of spawning help.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/spawn-worker.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/retire-worker.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/clear-worker.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/check-worker.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/list-roles.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/list-roles.sh)
---

# Spawn a worker

`${CLAUDE_SKILL_DIR}/scripts/spawn-worker.sh --role <agent> --name <name> --dir <path>` creates a cmux panel, launches
Claude Code in it as the named agent definition, and prints the surface ref.

## Choosing a role

`${CLAUDE_SKILL_DIR}/scripts/list-roles.sh` prints the roles this plugin ships: the exact `--role`
spelling, the effort each runs at, and its description. Pick by the description — it says what the
role is for and what it is not for. The listing is read from the plugin's own role files, so it is
never behind them.

`--role` is not limited to that list. It takes any agent definition the session can resolve —
user scope, project scope, managed scope, another plugin — spelled exactly as the Agent tool's list
of types spells it, which for a plugin role is `plugin-name:role-name`.

**A role's `model:` reaches a spawned session; its `effort:` does not, by itself.** Verified by
asking a running worker what it was on: the model came from the definition even though the script
passes no `--model`, while the effort was the machine default. So `spawn-worker.sh` reads `effort:`
from the role file and passes it as `--effort` — for the roles this plugin ships only, since those
are the files it can find. An explicit `--effort` wins. Any other role runs at the machine default
unless you pass one. The script's output says which effort was used and where it came from.

An invalid name is not silently ignored: the CLI refuses and prints every name it does recognise,
which is the fastest way to find out what a role is actually called here.

The script cannot tell you whether the worker actually registered — that is `ListAgents`, your tool,
not a shell command. So the loop is: run the script, confirm the name appears in `ListAgents`, then
message the worker and ask for its working directory and branch **before** assigning anything. Two
sessions in one day turned out to be somewhere other than where their panel implied.

## Choosing a working directory

Give each worker its own git worktree when they will build concurrently: a shared build output
directory means one agent's clean step deletes another's compiled artefacts mid-run. That is the
only reason worktrees matter here.

Separate *branches* are a different question and usually the wrong answer. They only help if
workers commit, and they cost a merge afterwards. For review or verification, put everyone on the
same commit and tell them not to commit; then what branch each worktree sits on stops mattering.
Git refuses the same branch in two worktrees, so a third reviewer ends up detached — which is fine
and requires no fix.

**When you do create a branch, pass `--no-track`.** `git worktree add -b <name> <start-point>` sets
the new branch to track the start point, so a worker whose `push.default` is `upstream` or `simple`
has a bare `git push` aimed at *your start point* — usually `origin/master`. Three workers in one
day hit this; each was stopped by branch protection, which is the only reason nothing landed on
master. A repository without that rule would have taken the commit.

Verified:

```bash
git worktree add -b probe path origin/master             # upstream: origin/master
git worktree add --no-track -b probe path origin/master  # no upstream configured
```

With no upstream the worker's first `git push -u origin HEAD` creates the remote branch and points
the local one at it, which is what you wanted anyway. Fix it at creation rather than telling each
worker to push carefully — a rule that has to be remembered by every worker is a rule that will be
missed by one.

## Looking at one that stopped

`${CLAUDE_SKILL_DIR}/scripts/check-worker.sh --name <worker> [--name <worker> ...]` prints each
worker's screen, blank runs collapsed. It finds panels the same way the other scripts do, by tab
title.

It does not say what the screen means; `coordinate-workers` carries that table. Reach for it only for
a worker that stopped without reporting — a worker that is `busy` in `ListAgents` needs no
inspection, and a viewport is large enough that reading one is not free.

## Retiring one

`${CLAUDE_SKILL_DIR}/scripts/retire-worker.sh --name <name>` finds the panel by title and closes it. Add
`--remove-worktree` to clear the directory up too.

The directory comes from a record `spawn-worker.sh` writes at launch, because cmux does not report
a panel's working directory. A worker spawned without one — before this record existed, or in a
panel other than the one now carrying its name — makes `--remove-worktree` exit 7 having closed
nothing; retire it without the flag and remove the worktree by hand once you have checked it.

It refuses to remove a worktree holding uncommitted changes or commits that never reached a remote,
and prints what it found. Override with `--force-worktree` only once you have looked. The manual
equivalent is `git worktree remove --force`, which discards a worker's unpushed work without
mentioning it.

Queued idle notices can still arrive after the panel closes; that is not an orphaned process.

## Clearing one between tasks

`${CLAUDE_SKILL_DIR}/scripts/clear-worker.sh --name <worker> [--label <task>]` wipes a worker's
conversation without ending the session, so the same worker can take an unrelated task without
dragging the last one's context behind it.

**The role survives; the conversation does not.** Verified by planting a passphrase, clearing, and
asking for it back: the passphrase was gone and the role's rules came back verbatim. Send the next
brief in full afterwards — a cleared worker has no memory even of what you told it when you spawned
it.

`--label` puts the current task in the panel header, as `<worker> · <task>`. Without it a clear
leaves the header showing the agent name, so every worker in the same role looks identical. **This
renames the session, so the SendMessage address changes with it** — the script prints the new one.
The tab title keeps the bare worker name, which is why `--name` still finds the panel afterwards.

`/clear` is a CLI command rather than a tool, so it cannot be delivered by `SendMessage` — it has to
be typed into the panel. That is why this is a script and not a message, and why it checks the screen
first: **typing Enter at a dialog answers the dialog.** It refuses while the worker is mid-turn
(exit 5) or while anything other than the plain input box is showing, and `--force` skips both
checks. That guard has already caught a panel sitting on a trust-this-folder prompt, where a blind
Enter would have granted it.

## Gotchas

**A dead turn stays dead, and the panel gives no sign of it.** When a turn ends on a connection
error the session prints `API Error: …`, closes with `· done HH:MM` and returns to a clean prompt,
where it waits indefinitely — reconnecting the network does not revive it. So a panel sitting at a
prompt is not evidence that the worker finished. `coordinate-workers` covers how to tell the two
apart and how to restart one.

**`--type agent-session` looks right and is a dead end.** It creates cmux's own agent surface, which
never registers as a peer session, so `SendMessage` cannot reach it. Only a `terminal` surface
running the `claude` CLI works.

**The address comes from `claude -n`, not from the panel title.** `cmux rename-tab` relabels the
window only. Without `-n` the session is auto-named after its directory and you are back to
guessing which `ListAgents` row is yours.

**`/rename` changes the address, not just the label.** Typed into the panel it renames the session,
and `ListAgents` immediately lists the worker under the new name — messages to the old one stop
arriving. The listing shows `says it was <old> until <n>s ago` for a short while, which is the only
grace you get. So a renaming scheme that drops the worker's identity leaves you unable to say who
is doing the work; keep the identity in the name and append the task to it.

**The panel title and the session name drift apart, and that is useful.** `cmux rename-tab` is
untouched by anything happening inside the session, so the tab is the one stable handle — these
scripts resolve panels by it for exactly that reason. The session name can then carry the current
task without breaking lookup.

**`send` types, `send-key Enter` submits.** Sending the command alone leaves it sitting in the
prompt, and the panel looks like a launch that silently did nothing.

**Registration trails the launch, but by less than it looks.** Measured: the prompt appears about
three and a half seconds in, and the peer is listed shortly after — so an absent name right after
launch means "not yet", not "failed". The script waits for the prompt rather than sleeping a fixed
span, because a flat wait is paid again on every spawn.

**A directory the CLI has not seen before stops the launch dead.** It asks "Is this a project you
trust?" and waits, so the worker never starts and never registers — indistinguishable from
registration lag unless you read the screen. The script detects this and exits 6 rather than
answering: `Enter` there grants read, write and execute in that directory, which is a decision for
whoever owns the machine, not for a spawn script.

**Confirm `--agent` took effect without `-n` in the mix.** The agent name shows in the startup
header, but `-n` replaces that header with the session name, so you cannot see both at once. When
you need to prove a role is active, launch once without `-n` and read the header.

**`--permission-mode auto` tells the worker to edit files with the shell.** It is needed — without
it a worker stalls on permission prompts nobody will answer — but it carries an instruction to
prefer `Bash` over `Edit`/`Write` for file work, and a worker applying that to production source
produces `sed` and `python` substitutions instead of edits. Granting `Write` and `Edit` in the role's
`tools` does not counter it; those tools are available and simply go unused. What does counter it is
a line in the role body telling the worker to disregard it for shipped code — verified by spawning
one and watching which tool it actually called.

**A launch flag beats a hook.** A skill denied by `--disallowed-tools` stays denied even when a
`UserPromptSubmit` hook instructs the session to load it. Useful for containment; a trap if you
deny a skill some hook depends on.

**A role's `tools` list can only grant what the harness already offers.** Naming a tool that is
disabled in this environment is silently a no-op, not an error — `Glob` and `Grep` are both absent
here, and a role listing them still comes up without them. Have a new worker call a tool you are
unsure of rather than trusting the list or its own account of what it holds; a session asked to
describe its tools contradicted itself inside one sentence, while a session asked to *use* one
produced an unambiguous `No such tool available`.

**`Bash` in a role's `tools` list is unrestricted shell.** Writing `Bash(git log:*)` there grants
the whole tool — the parentheses are a permission specifier, not a narrowing of the list. So a role
that omits `Write` and `Edit` is *not* read-only if it has `Bash`, and neither is one whose
description says it only reads. `Skill` is a second write path, since the catalogue includes skills
that deploy and mutate external state. A role that must run builds cannot also be incapable of
writing; say which of the two you actually need.

## Keeping workers from spawning workers

The script denies the coordination skills by default — this one and `coordinate-workers` — with a
`--disallowed-tools 'Skill(...)'` flag each. They compose with `--agent` and leave the rest of the
catalogue available. That is the hard guard. `--guard` takes a comma-separated list if you need a
different set.

`coordinate-workers` grants nothing on its own, so denying it is not about capability: it exists so a
worker that reads it does not start dispatching its peers, which makes a report impossible to trace
back to whoever was accountable for it.

Two softer ones back it up, but only for roles written that way: a definition whose `tools` omits
`Agent` cannot fan out through subagents either, and a role body can say so in words. Neither is
automatic — check the definition you are about to spawn rather than assuming, because a role someone
else wrote may grant `Agent` without meaning to.

Do not reach for `--disable-slash-commands` or dropping `Skill` from the role's tools — workers
genuinely need the rest of the catalogue.

