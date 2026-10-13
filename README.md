# agentic-engineering

A Claude Code marketplace for building software with agents. It covers the parts of the job which
should not be improvised every time.

## Why this exists

Handing work to another Claude Code session is easy. Trusting what comes back is the hard part. It
fails in ways which look like success:

- a worker reported 440 unit and 174 integration tests. Real numbers were 1256 and 224. It counted
  report files instead of reading the build summary
- a worker reported a green build on a branch which could not compile from clean. Old artifacts
- a bug report came with a real stack trace **and** a false explanation of the cause. The fix was
  built on the explanation and had to be done again
- a worker rewrote production code with `sed`. The permission mode it started with tells sessions
  to prefer the shell for file edits
- a worker never started at all. It waited on a trust-this-folder prompt. From outside this looks
  the same as a slow start, if nobody looks at the screen

None of these is really a model failure. They are normal results of delegating without a contract.
Nobody said which number to read, nobody said what "done" means, nobody checked. Every rule here was
written on the day when one of these problems took me few hours.

## Plugins

### `agent-crew`

This plugin creates a crew: named workers with roles, addresses, and an identity which survives when
their context is wiped. You start one, give it work, check what comes back, and retire it.

| component | what it does |
|---|---|
| `coordinate-workers` *(skill)* | The coordinator side. How to write a task brief which still makes sense to a session with no memory of the conversation. What to put in the message and what to leave in the tracker. How to verify a report instead of believing it. When parallel work really helps, and what to do when a worker goes quiet. |
| `split-work` *(skill)* | The step between a decided plan and a plan you can dispatch. It turns a settled approach into items ordered by dependency. Each item can be started by a session which never saw the discussion. Size comes from how much an agent must hold in its head, not from hours. Items are checked against work which already exists, and shown for approval before anything is created. It decides what the items are. `coordinate-workers` says how to write one, and a backlog plugin creates them. |
| `spawn-worker` *(skill)* | The session mechanics. Start a worker in a cmux panel with a given role, clear its conversation between tasks but keep its name and address, and retire it. It refuses to drop a worktree which still holds uncommitted or unpushed work. |
| `agent-crew:developer` *(role)* | Implements one task end to end and reports honestly. Full builds, not filtered ones. Counts read from the build summary, with the number from before. A fix comes with a test which would catch the bug. When the brief turns out to be wrong, it stops instead of guessing. |
| `agent-crew:tester` *(role)* | Verifies someone else's work and reports what is true. Evidence for every claim, an explicit "inconclusive" instead of a false pass, and a judgement whether the tests would have failed before the fix. It reports findings, it does not fix them. |
| `agent-crew:solution-architect` *(role)* | Works out how a change should be made, before anyone writes it. Reads the code as it really is. Verifies the facts which the plan stands on, instead of taking them from somebody. Challenges the task when the task is wrong. Splits the work so it can land in steps, not in one big lump. Gives a decision with reasons, not a menu of options. Does not implement. |

The three roles are useful alone, with or without the session machinery. They are the worker side of
the same contract which the coordinator skill describes.

**An item which reads perfectly for you can be impossible to start.** You read it with the
conversation still in your head. This is why `split-work` tests every item against a session which
never saw the discussion, not against your own understanding. And why it sizes items by how much an
agent must hold, not by how long it would take you. It names no tracker. The items land where a
backlog plugin says.

### `beads-backlog`

`agent-crew` names the moves, a backlog plugin knows how to make them. The crew says *the tracker*
and *a task item* on purpose, so the store stays a choice. Installing this one makes that choice
[Beads](https://github.com/gastownhall/beads), driven by `bd`. Change the plugin to change the
store. The crew stays the same.

| component | what it does |
|---|---|
| `drive-backlog` *(skill)* | Binds the crew's abstract backlog to beads, and then says as little as possible. `bd` is built agent-first and ships its own agent context (`bd prime`), so the skill points there instead of copying it. It carries what that help does not: the `--graph` plan schema, the way this plan fails quietly, which database `bd` is going to write to, and where the crew's "a worker has gone quiet" meets Beads' claim leases. Ships `validate-graph-plan.sh`, so the quiet failure is an exit code and not a number nobody reads. |

**A dry run which reports zero edges looks like success.** Dependencies written inside a node of a
graph plan parse without any error and create nothing. The plan lands as a pile of items with no
order. The only sign is a number in the dry run output which nobody reads. This one is the reason
why this plugin has a gotchas section.

### `madr-decisions`

A decision record has a date. It says what was decided *then*, and this is the only thing it is good
for. When the code moves on, the record does not become wrong. It becomes superseded.

| component | what it does |
|---|---|
| `record-decision` *(skill)* | Carries what MADR does not. That an accepted record is history and not documentation. That one record holds one decision. That the mechanism belongs in the code, and what was decided and why belongs in the record. That scope lives in the directory, not in a field which can disagree with it. It says nothing about the format itself. This was measured: a clean session reproduces MADR's five frontmatter keys and all eight headings without help. Ships `new-decision.sh`, so the record is generated and not recalled from memory, and superseding changes one line of the old file instead of rewriting it. Ships `set-status.sh` for the rest of the lifecycle, which is not in the skill's `allowed-tools`, so accepting a record stops for a person first. |
| *(hook)* | The part which fires when nobody asked for it. A `PreToolUse` hook reads the status of the record being edited: a draft stays editable, because this is how a skeleton gets filled in, and anything settled is refused with the command to run instead. It covers the shell as well as `Edit`, since a live session asked to accept a record reached for `sed -i` on its first try. |

**An agent which updates a decision to match the code is destroying it.** One rewrote the original
sentence of a record, then added a note under it: "as written, this decision gave the event a third
component". It was pointing at text which it had just deleted. Now the document disagrees with
itself. Its own commit message shows the mistake: *"DD-014 no longer documents a ChatMessagePosted
signature that does not exist."* There was nothing to sync. There was a new record to write. This is
the same failure as the green build on a branch which could not compile, just in a different form.
The work looks done because the file changed.

### `peer-review`

A verdict on work which already exists. The reviewed thing can be different every time (a plan, a
document, an uncommitted diff, the work on current branch), so the command picks a target and gives
the reviewer only a path.

| component | what it does |
|---|---|
| `/peer-review:fresh-eyes` *(command)* | Picks the target if you did not name one (a document from the conversation, the uncommitted diff, or the branch diff against the default branch of the repository). It says which one it picked, and relays what comes back word for word, also when the answer is a plain "nothing found". |
| `peer-review:fresh-eyes-review` *(agent)* | Reads the artifact and reports blunders, oversights, missing things, logical problems and bugs. Read-only by construction: no edit tools, and the only shell it has is `git log`, `diff`, `show` and `status`. |
| `/peer-review:primitive-obsession` *(command)* | Picks the target the same way, and gives it to a reviewer with one lens: a string, number, boolean or map with fixed keys which stands in for a concept that has a name in the domain. Works for any language. Relays the report word for word. |
| `peer-review:type-review` *(agent)* | Asks eight questions about every primitive in the artifact. Can it hold an illegal value? Is it compared, or used in a calculation? Do several fields mean one thing? How many states can be built, and how many are valid? Can two arguments be swapped? Does the type already exist? Then it names the remedy. On a plan, "do not introduce this primitive". On a diff, Fowler's *Replace Primitive with Object*. It does not report primitives at the edge of the subsystem, open sets which are a string on purpose, or values local to one algorithm. Same tools as fresh-eyes, so it reports and does not fix. |

**The reviewer gets no context on purpose.** No summary of the design, no reason why it was built
this way, no list of your worries. A helpful introduction gives your own thinking back to you, and
the review becomes an echo. This is exactly the problem which fresh eyes should solve. This is also
why it reports and does not fix. What to do with a finding is a decision, and the reviewer is not
the person who makes it.

**The second lens exists because the question was always asked by hand.** "Is this string really a
domain concept?" came up three times in two days on one project. Each time it found a missing type,
and each time it depended on somebody who remembered to ask. A reviewer with a lens is still not an
echo, because it gets a question and not your reasoning. So the question can be a step in the
process, and not a habit.

### `pipeline-watch`

The second reviewer is the pipeline. Nobody has to ask it for an opinion, it has one the moment you
push. The cost is that somebody must remember to read it, few minutes after they stopped thinking
about the change. This plugin watches for the push and reacts without being asked.

| component | what it does |
|---|---|
| *(hook)* | The watching half. Fires after `git push` from a branch with an **open** PR. It carries only the PR number and a pointer to the skill, four lines, because this text goes into context on every push. It is not even started for commands which are not `git`, and it is silent when the branch has no open PR, or the PR is already merged. |
| `check-sonar-analysis` *(skill)* | The reacting half. Waits for the pipeline, reads the findings, and refuses to report anything before it proves that the analysis belongs to the commit which was just pushed. Fixes what the agent's own commits introduced. Names what was already there and leaves it alone. Ships `wait-for-analysis.sh`, so waiting is a script and not a polling loop written again every time. |

**Zero findings is not an answer.** A findings query replies immediately and usually describes the
*previous* commit, because the pipeline needs minutes. An empty result looks exactly like a clean
one. A green quality gate badge looks the same, it survives from the run before. The skill accepts
one of three proofs instead: a timestamp after the push, findings which were open and now show
`CLOSED`, or line numbers which match the file as it is now. This is the same failure as the green
build on a branch which could not compile. An old artifact in the shape of success.

`check-sonar-analysis` has SonarQube in the name because it was written against SonarQube. The
plugin is the namespace. A check for failing tests or a coverage drop would sit next to it as
another `check-*` skill, watched by the same hook.

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install agent-crew@agentic-engineering
claude plugin install beads-backlog@agentic-engineering
claude plugin install madr-decisions@agentic-engineering
claude plugin install peer-review@agentic-engineering
claude plugin install pipeline-watch@agentic-engineering
```

The plugins are independent, you can install any of them alone. `beads-backlog` is one exception to
mention. It is useful alone, but it exists to complete `agent-crew`.

## Requirements

`spawn-worker` drives [cmux](https://www.cmux.dev/), a terminal based on Ghostty with vertical tabs
and notifications for AI coding agents. Without it this skill does nothing. The script checks and
exits instead of failing in the middle.

```bash
brew install --cask cmux
```

The coordination skill and the roles have no dependencies and work anywhere.

## Configure your tracker

`coordinate-workers` does not name a tracker on purpose. It says "the tracker" and "a task item"
everywhere, and binds to a real tool in exactly one paragraph at the top of the skill. Edit that
paragraph to name yours (Linear, Jira, GitHub issues, beads, a markdown file). Everything else keeps
working without changes, and this is the point of keeping the binding in one place.

## What it does not do, on purpose

This tooling starts autonomous Claude Code sessions which hold a full shell. Some things which it
refuses to do are the most important parts of it:

- **It will not answer a trust-this-folder prompt for you.** When you spawn into a directory which
  the CLI did not see before, it stops on that prompt. The script detects it, reports it and exits.
  Pressing Enter there gives read, write and execute in that directory. This is not a decision for
  a spawn script.
- **It will not let a worker spawn more workers.** Workers start with the coordination skills
  denied, so a fan-out cannot start itself. Delegation in a loop produces work for which nobody is
  responsible.
- **It will not throw away unpushed work of a worker.** Retiring refuses to remove a worktree which
  holds uncommitted changes, or commits which never reached a remote. It prints what it found and
  makes you pass `--force-worktree` after you looked. The manual command destroys it silently.
- **It will not clear a worker in the middle of a task, and it will not type into a panel which
  shows a chooser instead of a prompt.** An Enter sent there answers whatever question was on screen.
- **It will not put a name or a label into a command line if you did not check it first.** Worker names,
  roles and labels are typed into a live shell and submitted, so they are limited to plain tokens.
  No spaces, no leading hyphen, nothing which could add a flag or a starting prompt. A name taken
  from a task brief is rejected, not executed.
- **It will not act when a name matches more than one panel.** It lists the candidates and stops.
  The alternative is to take the first one from the terminal list, and then an accident decides
  which worker gets closed.
- **It does not sandbox anything.** A role described as read-only still has `Bash`. Read which tools
  a role really gives before you trust a description. This includes the descriptions here.

## License

MIT
