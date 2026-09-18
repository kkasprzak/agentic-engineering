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
| `spawn-worker` *(skill)* | The session mechanics. Start a worker in a cmux panel as a given role, clear its conversation between tasks while keeping its name and address, and retire it — refusing to discard a worktree that still holds uncommitted or unpushed work. |
| `agent-crew:backend-developer` *(role)* | Implements one scoped task end to end and reports honestly: full builds rather than filtered ones, counts read from the build summary with the before figure stated, a fix accompanied by a test that would have caught the bug, and a stop rather than a guess when the brief turns out to be wrong. |
| `agent-crew:tester` *(role)* | Verifies someone else's work and reports what is true — evidence for every claim, an explicit "inconclusive" over a false pass, and a judgement on whether the tests would have failed before the fix. Reports findings; does not fix them. |

The two roles are useful on their own, with or without the session machinery — they are the worker's
half of the same contract the coordinator skill describes.

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install agent-crew@agentic-engineering
```

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
- **It does not sandbox anything.** A role described as read-only still holds `Bash`. Read the tools
  a role actually grants before trusting a description, including the ones here.

## License

MIT
