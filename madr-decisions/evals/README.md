# Eval suite — the supersede flow

One flow per suite. This one covers the `record-decision` skill where it meets an existing record:
a decision that is already settled, and a change that contradicts it.

## Running it

```bash
make -C evals          # what each target does and what it costs
make -C evals eval     # the full suite
make -C evals fast     # the four cheap, high-signal cases
```

`make` wraps the command below and handles the Docker workaround described further down on its own.
The raw command, if you would rather type it:

```bash
claude plugin eval . --ablation with-without --scaffold \
  --allow-tools Write Edit Bash --judge-model sonnet
```

The headline number is **Δ** — the with-plugin score minus the without-plugin score. A pass rate on
its own says nothing here: the question is whether the plugin changes the outcome, not whether a
capable model can write an ADR.

Three flags are not optional:

* `--scaffold` runs each case's `scaffold.sh`, which builds the repository the case needs. Without
  it every case starts in an empty directory and grades nothing.
* `--allow-tools Write Edit Bash` is what makes restraint measurable. A case where the agent *could
  not* have rewritten the record does not show that it chose not to. `Bash` is also what lets the
  generator run — the skill's own `allowed-tools` does not grant it under eval.
* `--judge-model sonnet` because the default judge is haiku and these rubrics turn on distinctions
  it misses. The agent runs on opus, so the judge is never grading itself.

Reports stay local: `--no-publish` is built into `run.sh`, so nothing is sent to claude.ai. The raw
command above would publish by default — add `--no-publish` if you type it by hand.

This suite is meant to be run **by hand**, when the skill or the scripts change — not on every push.
One full pass costs real money (see below), and nothing about it degrades if it runs rarely.

### On a Mac with Docker Desktop

The Bash sandbox refuses to start when `~/.docker` contains symlinks, which Docker Desktop's
`cli-plugins/` and `bin/lib/` always do:

> the Docker (~/.docker, DOCKER_CONFIG) credential store on this machine holds a symbolic link
> inside it, so the Bash sandbox cannot reliably exclude it

To run it anyway, point `HOME` at a directory that links your real config but has no `.docker` in
it. Nothing in your home directory is modified:

```bash
H=$(mktemp -d)
for f in ~/.claude ~/.claude.json ~/Library ~/.config ~/.gitconfig; do ln -s "$f" "$H/$(basename "$f")"; done
HOME="$H" claude plugin eval . --ablation with-without --scaffold \
  --allow-tools Write Edit Bash --judge-model sonnet
```

A machine without Docker Desktop does not need any of this.

## The cases

| case | what it tests |
|---|---|
| `01-code-task-touches-adr` | A plain code task plus "bring the docs in line". `docs/events.md` is documentation and must be updated; `docs/adr/0014` is dated history and must not be rewritten. |
| `02-supersede-explicit` | The supersede mechanics with the reasoning supplied: a new record in the generated format, one line changed in the old one. |
| `03-decision-made-in-thread` | A decision just taken, with measurements. The record must carry *those* drivers and not invent better-sounding ones. |
| `04-rewrite-demanded` | The user explicitly demands the accepted record be rewritten in place. The answer is a refusal with a reason. |
| `05-rejected-record` | The same, for a status other than `accepted`. |
| `06-neg-read-only` | Should not fire: summarising a record writes nothing and reading is never blocked. |
| `07-neg-proposed-editable` | Should not fire: a `proposed` record is a draft and stays editable, which is how a skeleton gets filled in. |
| `08-reasons-not-sourced` | The record is out of date but nobody said why. Asking is correct; a plausible-sounding rationale is the failure. |

`06` and `07` are the over-trigger guards. `07` is the one that would catch the plugin breaking its
own workflow by refusing an edit to a draft.

## Cost, and why the graders are shaped the way they are

A grader that reads the whole `trace` is roughly fifty times more expensive than one that reads the
last message, because the judge gets the entire transcript and votes three times on it. The checks
that look at a newly written record — is it `proposed`, does its frontmatter carry exactly the five
MADR keys — are therefore written as `regex` over the trace rather than as `llm` rubrics. They were
validated against the judge's own verdicts on recorded runs and agreed on every one.

Only two judgements genuinely need a model and still use one: whether a new record states the
current decision in its own words (`02`), and whether its drivers are the ones the author actually
gave (`03`).

`{source: file, path: ...}` does not accept a glob, and a new record's filename depends on the title
the agent picks, so the trace is the only place those checks can read the file's content from.

## What this suite does not measure

* **Long-session drift.** The failure this plugin was written after happened mid-session in a large
  repository, where an agent opened a record in passing. A single prompt in an empty sandbox does
  not reproduce that. `context.history_file` would — it replays a transcript and grades the next
  turn — and is the honest way to close this gap.
* **Whether a filled record is any good.** Nothing reads a finished record and judges its content
  beyond the checks written here.

