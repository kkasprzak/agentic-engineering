# pipeline-watch

A push to an open pull request is not the end of the job. The pipeline still has to run, what it
reported still has to be read, and whatever your own commits introduced still has to be fixed.

That last part is normally a person's job: notice the push happened, wait several minutes, open the
dashboard, then tell the agent to go back and fix it. This plugin takes the person out of that loop
— it watches for the push and reacts on its own.

## What it does

Two pieces, each doing only its own half:

- **A hook** (`PostToolUse` on `Bash`) — the watching half. Fires after a `git push` from a branch
  with an **open** PR, carrying nothing but the PR number and a pointer at the skill.
- **A skill** — the reacting half. `check-sonar-analysis` holds the procedure: wait for the
  pipeline, read the findings, **prove the analysis is not a stale run**, fix what your own commits
  caused, report either way.

The split is deliberate. The hook's text enters context on every push, so it stays four lines; the
skill body is read only when it is needed, and is edited as Markdown rather than as a quoted shell
heredoc. You can also invoke the skill yourself when no push triggered it.

On every other command the hook prints nothing and changes nothing.

## The failure it was built for

A findings query answers instantly and looks authoritative. It is usually the **previous** commit's
analysis, because the pipeline takes minutes. Zero open findings proves nothing on its own, and
neither does a green quality-gate badge — both survive untouched from the run before.

So the skill refuses to report a result until something proves it belongs to the commit that was
just pushed: a timestamp after the push, findings that were open now showing `CLOSED`, or line
numbers matching the file as it currently stands.

## Scope

One check ships today: `check-sonar-analysis`, written against SonarQube and SonarCloud and named
for that rather than pretending to be general. The plugin is the namespace. A check for failing
tests or a coverage drop would sit beside it as another `check-*` skill, watched by the same hook.

## Requirements

- `gh`, authenticated — used to find the open PR for the current branch
- `jq`
- Some way for the agent to read the findings: the SonarQube MCP server, or the project's own CLI

If `gh` or `jq` is missing, the hook exits quietly instead of failing the tool call.

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install pipeline-watch@agentic-engineering
```

## Known gaps

- **The hook's filter matches on a prefix.** `"if": "Bash(git *)"` keeps it from being spawned for
  unrelated commands, but a push buried in a command starting with something else
  (`cd somewhere && git push`) will not match, and the reminder is silently skipped. Commands that
  begin with `git` are covered, including multi-line ones ending in a push.
- **It resolves the PR from the current directory**, not from the repository the push actually
  targeted. Those differ only when pushing with `git -C`, which is rare in normal use.
- **"Watch" is slightly ahead of the implementation.** The hook fires once, on the push; it does not
  hold a continuous watch. If a real monitor is added later, the name already fits.
