# sonar-followup

A push to an open pull request is not the end of the job. The pipeline still has to run, the static
analysis still has to be read, and whatever your own commits introduced still has to be fixed. That
last part is usually remembered by a person — who has to notice the push happened, wait several
minutes, open SonarQube, and tell the agent to go back and fix it.

This plugin moves that from the person to the agent.

## What it does

After any `git push` from a branch that has an open PR, the agent is told, by the harness rather
than by you:

1. Wait for the pipeline — specifically the job that runs the analysis.
2. Read the findings for that PR.
3. **Check the analysis is the new one.** Compare the findings' timestamps and line numbers against
   the commit just pushed. A stale run reported as clean is the failure this step exists for.
4. Fix what its own commits introduced, push again, repeat.
5. Say what happened either way.

On every other command it prints nothing and changes nothing.

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
