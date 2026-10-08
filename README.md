# agentic-engineering

A Claude Code marketplace for building software with agents — the parts of the job that should not
be improvised every time.

## Why this exists

Handing work to another Claude Code session is easy. Trusting what comes back is the hard part, and
it fails in ways that look like success:

- a worker reported 440 unit and 174 integration tests. The real figures were 1256 and 224 — it had
  counted report files instead of reading the build's own summary
- a worker reported a green build on a branch that could not compile from clean. Stale artefacts
- a bug report arrived with a real stack trace **and** a false explanation of the cause. The fix was
  built on the explanation and had to be redone
- a worker rewrote production source with `sed`, because the permission mode it was launched under
  tells sessions to prefer the shell for file edits
- a spawned worker never started at all. It sat on a trust-this-folder prompt, indistinguishable
  from a slow launch unless somebody looked at the screen

None of these are model failures in the interesting sense. They are the ordinary consequences of
delegating without a contract: nobody said which number to read, nobody said what "done" has to
survive, nobody checked. Every rule in this marketplace was written the day a specific one of these
cost an afternoon.

## Plugins

### `agent-crew`

A crew is what this plugin creates: named workers with roles, addresses, and an identity that
survives having their context wiped. You stand one up, hand it work, check what it brings back, and
retire it.

| component | what it does |
|---|---|
| `coordinate-workers` *(skill)* | The coordinator's half. How to write a task brief that still makes sense to a session with no memory of the conversation, what to put in the dispatch message and what to leave in the tracker, how to verify a report instead of believing it, when parallel work actually helps, and what to do when a worker goes quiet. |
| `split-work` *(skill)* | The step between a decided plan and a dispatchable one. Turns a settled approach into items ordered by dependency, each startable by a session that never saw the discussion — sized by the working set it has to hold rather than by hours, checked against work that already exists, and presented for approval before anything is created. It decides what the items are; `coordinate-workers` says how to write one, and a backlog plugin creates them. |
| `spawn-worker` *(skill)* | The session mechanics. Start a worker in a cmux panel as a given role, clear its conversation between tasks while keeping its name and address, and retire it — refusing to discard a worktree that still holds uncommitted or unpushed work. |
| `agent-crew:backend-developer` *(role)* | Implements one scoped task end to end and reports honestly: full builds rather than filtered ones, counts read from the build summary with the before figure stated, a fix accompanied by a test that would have caught the bug, and a stop rather than a guess when the brief turns out to be wrong. |
| `agent-crew:tester` *(role)* | Verifies someone else's work and reports what is true — evidence for every claim, an explicit "inconclusive" over a false pass, and a judgement on whether the tests would have failed before the fix. Reports findings; does not fix them. |
| `agent-crew:solution-architect` *(role)* | Works out how a change should be made before anyone writes it — reads the code as it actually is, verifies the facts the plan will rest on rather than inheriting them, challenges the framing when the task is the wrong one, and sequences the work so it can land in steps instead of one lump. Produces a decision with its reasons, not a menu. Does not implement. |

The three roles are useful on their own, with or without the session machinery — they are the worker's
half of the same contract the coordinator skill describes.

**An item that reads perfectly to you can be unstartable**, because you are reading it with the
conversation still in your head. That is why `split-work` tests each item against a session that
never saw the discussion rather than against your own understanding, and why it sizes by the working
set an item forces an agent to hold rather than by how long it would take you. It names no tracker:
the items land wherever a backlog plugin says they do.

### `beads-backlog`

`agent-crew` names the moves; a backlog plugin knows how to make them. The crew says *the tracker*
and *a task item* on purpose, so the store stays a choice — installing this one makes that choice
[Beads](https://github.com/gastownhall/beads), driven by `bd`. Swap the plugin to change store; the
crew does not change.

| component | what it does |
|---|---|
| `drive-backlog` *(skill)* | Binds the crew's abstract backlog to beads, and then gets out of the way — `bd` is built agent-first and ships its own agent context (`bd prime`), so the skill points there rather than copying it. What it does carry is what that help does not: the `--graph` plan schema, the way that plan fails quietly, which database `bd` is actually about to write to, and where the crew's "a worker has gone quiet" meets Beads' claim leases. Ships `validate-graph-plan.sh`, so the quiet failure is an exit code rather than a number nobody reads. |

**A dry run that reports zero edges reads as success.** Dependencies written inside a node of a
graph plan parse without complaint and create nothing, so the plan lands as a pile of unordered
items and the only tell is a number in the dry-run output nobody reads. That one is why this plugin
has a gotchas section at all.

### `madr-decisions`

A decision record is dated. It says what was decided *then*, and that is the only thing it is good
for — when the code moves on, the record does not become wrong, it becomes superseded.

| component | what it does |
|---|---|
| `record-decision` *(skill)* | Carries what MADR does not: that an accepted record is history rather than documentation, that one record holds one decision, that the mechanism belongs in the code while what was decided and why belongs in the record, and that scope lives in the directory rather than in a field that can disagree with it. Says nothing about the format itself — that was measured, and a clean session reproduces MADR's five frontmatter keys and all eight headings unaided. Ships `new-decision.sh`, so the record is generated rather than recalled, and superseding changes one line of the old file instead of rewriting it. |

**An agent updating a decision to match the code is destroying it.** One rewrote a record's original
sentence, then added a note beneath reading "as written, this decision gave the event a third
component" — referring to text it had just deleted. The document now disagrees with itself. Its own
commit message gives the misconception away: *"DD-014 no longer documents a ChatMessagePosted
signature that does not exist."* There was nothing to sync; there was a new record to write. This is
the same failure as the green build on a branch that could not compile, wearing a different costume:
the work looks done because the artifact changed.

### `peer-review`

A verdict on work that already exists. The thing being reviewed varies — a plan, a document, an
uncommitted diff, the current branch's work — so the command resolves a target and hands the
reviewer nothing but a path.

| component | what it does |
|---|---|
| `/peer-review:fresh-eyes` *(command)* | Picks the target if you did not name one — a document from the conversation, the uncommitted diff, or the branch diff against the repository's default branch — says which it picked, and relays what comes back verbatim, including a plain "nothing found". |
| `peer-review:fresh-eyes-review` *(agent)* | Reads the artifact and reports blunders, oversights, omissions, logical problems and bugs. Read-only by construction: no edit tools, and the only shell it holds is `git log`, `diff`, `show` and `status`. |

**The reviewer is given no context on purpose.** Not a summary of the design, not why it was built
that way, not what you were worried about. A helpful preamble hands your own reasoning straight back
to you and the review becomes an echo — which is exactly the failure a fresh pair of eyes exists to
avoid. This is also why it reports rather than fixes: what to do about a finding is a decision, and
the reviewer is not the one making it.

### `pipeline-watch`

The other reviewer is the pipeline, and nobody has to ask it for an opinion — it has one the moment
you push. The cost is that reading it is a chore somebody has to remember, minutes after the moment
they stopped thinking about the change. This plugin watches for the push and reacts on its own.

| component | what it does |
|---|---|
| *(hook)* | The watching half. Fires after a `git push` from a branch with an **open** PR, and carries nothing but the PR number and a pointer at the skill — four lines, because this text enters context on every push. Not even spawned for commands that are not `git`, and silent when the branch has no open PR or the PR is already merged. |
| `check-sonar-analysis` *(skill)* | The reacting half. Waits for the pipeline, reads the findings, and refuses to report anything until it has proved the analysis belongs to the commit that was just pushed. Fixes what the agent's own commits introduced; names what was already there and leaves it alone. Ships `wait-for-analysis.sh`, so waiting is a script rather than a polling loop improvised fresh each time. |

**Zero findings is not an answer.** A findings query replies instantly and usually describes the
*previous* commit, because the pipeline takes minutes — and an empty result looks exactly like a
clean one. So does a green quality-gate badge, which survives from the run before. The skill accepts
one of three proofs instead: a timestamp after the push, findings that were open now showing
`CLOSED`, or line numbers matching the file as it currently stands. This is the same failure as the
green build on a branch that could not compile — a stale artefact wearing the shape of success.

`check-sonar-analysis` is named for SonarQube because that is what it was written against. The
plugin is the namespace: a check for failing tests or a coverage drop would sit beside it as another
`check-*` skill, watched by the same hook.

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install agent-crew@agentic-engineering
claude plugin install beads-backlog@agentic-engineering
claude plugin install madr-decisions@agentic-engineering
claude plugin install peer-review@agentic-engineering
claude plugin install pipeline-watch@agentic-engineering
```

The plugins are independent — install any one on its own. `beads-backlog` is the exception worth
naming: it is useful alone, but it exists to complete `agent-crew`.

## Requirements

`spawn-worker` drives [cmux](https://www.cmux.dev/) — a Ghostty-based terminal with vertical tabs
and notifications for AI coding agents — and does nothing without it: the script checks and exits
rather than failing halfway.

```bash
brew install --cask cmux
```

The coordination skill and both roles have no dependencies and work anywhere.

## Configure your tracker

`coordinate-workers` deliberately does not name a tracker. It says "the tracker" and "a task item"
throughout, and binds to a real tool in exactly one paragraph at the top of the skill — edit that
paragraph to name yours (Linear, Jira, GitHub issues, beads, a markdown file). Everything else keeps
working unchanged, which is the point of putting the binding in one place.

## What it deliberately does not do

This tooling starts autonomous Claude Code sessions that hold a full shell. Some of what it refuses
to do is the most important thing about it:

- **It will not answer a trust-this-folder prompt for you.** Spawning into a directory the CLI has
  not seen before stops on that prompt; the script detects it, reports it, and exits. Pressing Enter
  there grants read, write and execute in that directory, and that is not a spawn script's decision.
- **It will not let a worker spawn more workers.** Workers launch with the coordination skills
  denied, so a fan-out cannot start itself. Recursive delegation produces work nobody is accountable
  for.
- **It will not discard a worker's unpushed work.** Retiring refuses to remove a worktree holding
  uncommitted changes or commits that never reached a remote, prints what it found, and makes you
  pass `--force-worktree` once you have looked. The manual equivalent destroys it silently.
- **It will not clear a worker mid-task,** or type into a panel that is showing a chooser rather
  than a prompt — an Enter sent there answers whatever was being asked.
- **It will not put a name or label you did not vet into a command line.** Worker names, roles and
  labels are typed into a live shell and submitted, so they are restricted to plain tokens — no
  spaces, no leading hyphen, nothing that could add a flag or a starting prompt. A name lifted out
  of a task brief is rejected rather than executed.
- **It will not act when a name matches more than one panel.** It lists the candidates and stops,
  because the alternative — taking whichever the terminal happened to list first — decides which
  worker gets closed by accident.
- **It does not sandbox anything.** A role described as read-only still holds `Bash`. Read the tools
  a role actually grants before trusting a description, including the ones here.

## License

MIT
