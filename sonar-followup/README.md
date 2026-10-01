# sonar-followup

A push to an open pull request is not the end of the job. The pipeline still has to run, the static
analysis still has to be read, and whatever your own commits introduced still has to be fixed. That
last part is usually remembered by a person — who has to notice the push happened, wait several
minutes, open SonarQube, and tell the agent to go back and fix it.

This plugin moves that from the person to the agent.

## What it does

Two pieces, each doing only its own job:

- **A hook** (`PostToolUse` on `Bash`) that fires after a `git push` from a branch with an **open**
  PR. It carries the PR number and nothing else: four lines naming the PR and pointing at the skill.
- **A skill**, `check-pr-analysis`, holding the actual procedure — wait for the pipeline, read the
  findings, **prove the analysis is not a stale run**, fix what your own commits caused, report.

The split matters. The hook's text enters context on every push, so it stays short; the skill body
is only read when it is actually needed, and can be edited as Markdown instead of as a quoted shell
heredoc. You can also invoke the skill yourself when no push triggered it.

On every other command the hook prints nothing and changes nothing.

## Requirements

- `gh`, authenticated — used to find the open PR for the current branch
- `jq`
- Some way for the agent to read the findings: the SonarQube MCP server, or the project's own CLI

If `gh` or `jq` is missing, the hook exits quietly instead of failing the tool call.

## Install

```
/plugin marketplace add kkasprzak/agentic-engineering
/plugin install sonar-followup@agentic-engineering
```

## Scope and known gap

The hook is filtered with `"if": "Bash(git *)"`, so it is not even spawned for non-git commands.
That filter uses permission-rule syntax, which matches on a **prefix only**. A push buried in a
command that starts with something else — `cd somewhere && git push` — will not match, and the
reminder is silently skipped. Commands that begin with `git` are covered, including multi-line ones
that end in a push.

It says "SonarQube / SonarCloud" because that is what it was built against. Nothing in the script is
specific to either; point step 2 at whatever analysis your pipeline publishes.
