# madr-decisions

A decision record has a date. It says what was decided *then*, and this is the only thing it is good
for. When the code moves on, the record does not become wrong. It becomes superseded.

Agents get this backwards. A document which no longer matches the code looks like a document which
needs an update. So they update it, and the account of what was decided is gone.

## The failure this was written after

An agent changed the original sentence of a record to match current code. Then it added a note under
it: *"As written, this decision gave the event a third component"*. The note was pointing at text
which the same agent had just deleted. Now the document disagrees with itself, and a reader cannot
tell which half to trust.

Its own commit message shows the mistake:

> DD-014 no longer documents a ChatMessagePosted signature that does not exist.

There was nothing to sync. There was a new record to write.

## What this plugin does about it

**Generates the record instead of describing the format.** A model which already knows MADR can
still write something close but not exact. A model which starts from a generated skeleton cannot.
The script picks the number, the path and the filename, and writes the frontmatter with MADR five
keys and nothing more. A sixth field of your own is how a format stops being a format.

**Supersedes by writing, not by editing.** `--supersedes` creates the new record and changes exactly
one line of the old one, its status. Everything else in that file is history and stays byte for byte
as it was. This is the behaviour the plugin exists for, and it is the assertion its tests are built
around. The tests are in `madr-decisions/tests/`, three suites for the generator, the lifecycle
script and the guard hook. Each one exits non-zero when anything fails. They need `perl` for their
timeouts and `python3` for the guard suite. Where one of them is missing, the cases which depend on
it say so and are skipped, not reported as passes.

**Moves a record along its lifecycle, and asks a person first.** `set-status.sh` makes three moves
(`proposed → accepted`, `proposed → rejected`, `accepted → deprecated`) and fills in
`decision-makers`, `consulted` and `informed`. Those three are usually unknown while a record is
written and obvious once it is agreed. The script changes only the line it was asked to change and
leaves `date` alone.

Unlike the generator, **this script is not in the `allowed-tools` of the skill**, so running it
normally stops for your approval. Accepting a record is what arms the guard below. If an agent could
do it without asking, it could lock its own work against everybody else.

That covers the script, and only the script. Two things it does not cover, and the skill names both
of them where the agent will read them. A user who answers "do not ask again", or who allows `Bash`
broadly, stops being asked after the first time. And a `proposed` record is editable by design,
because this is how a skeleton gets filled in, so nothing blocks an `Edit` on its status line. The
prompt is a real gate on one path, not a guarantee on all of them.

**Refuses the edit which caused all this, in the moment it is tried.** Generating a good record does
nothing about an agent which opens an accepted one six months later and brings it up to date. By
then no skill is loaded to object. A `PreToolUse` hook reads the status of the target: `proposed` is
a draft and stays editable, which is exactly what filling in a fresh skeleton is; `accepted`,
`rejected`, `deprecated` and `superseded by <id>` are decided, and the edit is refused with a
message naming the command to run instead. No path list to maintain and nothing to configure. The
record says whether it is still open, and a person accepting it is what locks it.

**It protects what this plugin generated, and only that.** A file qualifies when its name is four
digits and a slug, **and** its frontmatter status is one which MADR defines. This excludes on
purpose a status the plugin never heard about, and a four digit prefix which is really a date. A
guard which fires on somebody blog post does not only annoy. The refusal prints a command which can
be run, and an agent which follows it rewrites the frontmatter of that post. Records under another
convention (`ADR-0001-`, `001-`, a `## Status` section instead of frontmatter) are not protected at
all.

**Both routes to a record are covered.** `Edit` and `Write` name their target, so those are simple.
A `Bash` call carries only a command string, and whether that string writes a given file cannot be
decided in general. So the shell side looks for a path shaped like a record, and acts only when the
command also looks like a write: a redirect, an in-place `sed` or `perl`, `tee`, `cp`, `mv`, a
`python` open for writing. Reading a record is never blocked.

This was argued the other way at the beginning: that catching nine spellings and missing the tenth
only looks like protection. Then a live Claude Code session was asked to accept a record. It reached
for `sed -i` on the first try, with a literal path, and nothing stopped it. The tenth spelling is
rare. The first one is what really happens.

What still gets through is a path which the shell builds at run time.
`F=docs/adr/0014-x.md; sed -i ... $F` has no record inside the command text, and the hook does not
run shells. It is in the known gaps.

**Refuses to let reasons be reconstructed.** You can write a convincing rationale for almost any
choice, and nobody reading it next year can see the difference between one which was sourced and one
which only sounds right. The skill treats a driver with no source as a thing to ask about, not to
fill in, because a record with invented reasoning is worse than no record. Somebody will build the
next decision on top of it.

**Keeps scope in the directory.**

```
docs/adr/           binds the whole system
docs/adr/<name>/    confined to one module or a group of them
```

No field records the scope, because a field can disagree with where the file really sits.
Identifiers follow from it: `0014`, or `chat/0014` when narrowed. Numbering is per directory, so two
people working in different scopes cannot take the same number.

A narrowed record cannot supersede a system one. A module does not overrule a decision which binds
other modules. The refusal says where the record belongs instead.

## What it does not contain

A description of the MADR format. This was measured, not assumed: a session with no template and no
hints reproduced MADR five frontmatter keys and all eight headings in order, then wrote a correct
document without help. A copy here would spend context for nothing and go stale against the real
template.

It also carries no immutability rule from MADR, because MADR has none. Its `date` field is
documented as *"when the decision was last updated"*. The rule in this skill comes from AWS instead:

> When the team accepts an ADR, it becomes immutable. If new insights require a different decision,
> the team proposes a new ADR.

## Where this departs from MADR, and why

Checked against the MADR template and against their own decision records, so the next person can see
which rules belong to this plugin and which to the format.

**MADR requires nothing at all.** Its template says about the frontmatter: *"These are optional
metadata elements. Feel free to remove any of them."* Its status list,
`{proposed | rejected | accepted | deprecated | … | superseded by ADR-0123}`, ends with an ellipsis
on purpose. And [ADR-0008](https://github.com/adr/madr/blob/main/docs/decisions/0008-add-status-field.md),
where MADR decided to have a status field at all, describes no lifecycle, no allowed transitions and
no field which must change together with the status. So:

| this plugin | MADR | why |
|---|---|---|
| three transitions, everything else refused | no transitions defined | a closed set catches mistakes, an open one cannot |
| `date` is the day the record was written and never changes | *"when the decision was last updated"* | a record is dated history here, so the date of the decision is the useful one |
| `superseded by 0014` | `superseded by ADR-0123` | identifiers are relative to the directory here, and `chat/0014` has no natural `ADR-` form |
| a record is immutable once accepted | no such rule | see above |

One thing worth taking which is not here yet: [ADR-0009](https://github.com/adr/madr/blob/main/docs/decisions/0009-support-links-between-adrs-inside-an-adrs.md)
decided that a link from one record to another belongs in **More Information**, written as an
ordinary markdown link. This is the MADR answer to the missing back reference listed in known gaps.

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install madr-decisions@agentic-engineering
```

## Requirements

Bash and `python3`, no packages and no network. `python3` is there for one job: the guard hook parses
the JSON from the harness with it, instead of grepping for a file path, because a path can contain
spaces, quotes or backslashes and the grep version works until the day it does not. **Without
`python3` the guard cannot read its input, so it allows the edit.** It says so on stderr instead of
failing closed, because a guard which blocks every session is worse than one which is honest about
being inert. The test suites want also `perl`.

Verified on macOS (bash 3.2, BSD tools) and on Linux, under GNU and under BusyBox. Windows is not
tested and the guard is probably inert there. `file_path` arrives with backslashes, which the
filename check does not recognise.

## Known gaps

- **A record which nobody promotes stays a draft, and a draft is editable.** `set-status.sh` exists
  now, and the permission prompt is what makes acceptance a decision of a person. But nothing
  *reminds* anybody to run it. The skill tells the agent to say that a record is waiting, and this is
  all the prompting there is. A record left at `proposed` for a year is unprotected for a year. For a
  draft this is correct. For a decision which somebody forgot to confirm it is a trap.

- **A rejected replacement strands the record it superseded.** `--supersedes` flips the old record as
  soon as the new one is written, while the new one is still only `proposed`. If a person then
  rejects it, the old decision, which still holds, reads `superseded by <a rejected proposal>`. The
  generator refuses to supersede it again, because its chain already points somewhere.

  **Nothing in the plugin undoes this.** `set-status.sh` refuses every move out of `superseded by`,
  and the guard refuses the `Edit`, so "fix it by hand" means a shell edit, which is the one route
  this plugin otherwise tells you not to take. Narrow transitions cannot reopen a record, by
  definition. Closing this needs a decision about reversal which nobody made yet.

- **Scope containment cannot be expressed.** If one scope logically contains another, the script
  cannot see it from the paths and will refuse the supersession. Write the new record at system
  scope.
- **No index is generated.** The list of records and their statuses is still maintained by hand.
- **Nothing validates the contents of a record after it is written.** Certainty about the *shape*
  comes from generating the skeleton, and the guard hook protects a record once it is settled. But
  nothing reads a filled record and judges whether what it says is any good. Nothing could.
- **A shell command which builds its path at run time gets past the guard.** The hook reads the
  command text, so `sed -i ... docs/adr/0014-x.md` is refused, but
  `F=docs/adr/0014-x.md; sed -i ... $F` is not. It does not run shells and cannot resolve variables.
- **A record written entirely through the shell still goes around the generator**, which is not
  involved at creation unless somebody runs it.
- **A new record does not say what it supersedes.** The old record gets `superseded by <id>`, the new
  one carries no pointer back. Following the chain forward works, backward does not.
