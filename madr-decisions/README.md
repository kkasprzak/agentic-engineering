# madr-decisions

A decision record is dated. It says what was decided *then*, and that is the only thing it is good
for. When the code moves on, the record does not become wrong — it becomes superseded.

Agents get this backwards, because a document that no longer matches the code looks like a document
that needs updating. So they update it, and the account of what was decided is gone.

## The failure this was written after

An agent changed a record's original sentence to match today's code, then added a note beneath it
reading *"As written, this decision gave the event a third component"* — referring to the text it had
just deleted. The document now disagrees with itself, and a reader cannot tell which half to trust.

Its own commit message gives the misconception away:

> DD-014 no longer documents a ChatMessagePosted signature that does not exist.

There was nothing to sync. There was a new record to write.

## What this plugin does about it

**Generates the record instead of describing the format.** A model that already knows MADR can still
write a near-miss of it; one that starts from a generated skeleton cannot. The script picks the
number, the path and the filename, and writes the frontmatter with MADR's five keys and nothing else
— a sixth field of your own is how a format stops being a format.

**Supersedes by writing, not editing.** `--supersedes` creates the new record and changes exactly one
line of the old one: its status. Everything else in that file is history and is left byte-for-byte as
it was. This is the behaviour the plugin exists for, and it is the assertion its tests are built
around — `madr-decisions/tests/test-new-decision.sh`, which exits non-zero when anything fails. It
needs `perl` for its timeout and `python3` for the guard's suite; where either is missing the cases
that depend on it say so and are skipped rather than reported as passes.

**Moves a record along its lifecycle, and asks a person before it does.** `set-status.sh` makes
three moves — `proposed → accepted`, `proposed → rejected`, `accepted → deprecated` — and fills in
`decision-makers`, `consulted` and `informed`, which are usually unknown while a record is being
written and obvious once it is agreed. It changes the one line it was asked to and leaves `date`
alone.

Unlike the generator, **this script is not in the skill's `allowed-tools`**, so every run stops for
the user's approval. Accepting a record is what arms the guard below; if an agent could do it
unprompted it could lock its own work against everyone else. The approval prompt is the human
decision, enforced by the harness rather than requested in prose.

**Refuses the edit that caused all this, at the moment it is attempted.** Generating a good record
does nothing about an agent opening an accepted one six months later and bringing it up to date, and
by then no skill is loaded to object. A `PreToolUse` hook sits on `Edit` and `Write` and reads the
target's own status: `proposed` is a draft and stays editable, which is exactly what filling in a
fresh skeleton is; `accepted`, `rejected`, `deprecated` and `superseded by <id>` have been decided,
and the edit is refused with a message naming the command to run instead. No path list to maintain
and no configuration — the record says whether it is still open, and a human accepting it is what
locks it.

**It protects what this plugin generated, and only that.** A file qualifies when its name is four
digits and a slug *and* its frontmatter status is one MADR defines. That deliberately excludes a
status the plugin has never heard of and a four-digit prefix that is really a date, because a guard
that fires on somebody's blog post does not merely annoy — the refusal prints a runnable command,
and an agent that follows it rewrites that post's frontmatter. Records under another convention —
`ADR-0001-`, `001-`, a `## Status` section rather than frontmatter — are not protected at all.

The hole in that: a file written through the shell. The harness fires `PreToolUse` for the Bash tool
as a whole and not for a redirection inside it, so `sed -i` goes around the guard. Catching nine
spellings of that and missing the tenth would read as cover without being it, so the guard does not
try.

**Refuses to let reasons be reconstructed.** You can write a convincing rationale for almost any
choice, and nobody reading it next year can tell the difference between one that was sourced and one
that merely sounds right. The skill treats an unsourced driver as a thing to ask about rather than
fill in, because a record with invented reasoning is worse than no record — someone will build the
next decision on top of it.

**Keeps scope in the directory.**

```
docs/adr/           binds the whole system
docs/adr/<name>/    confined to one module or a group of them
```

No field records the scope, because a field can disagree with where the file actually sits.
Identifiers follow from it: `0014`, or `chat/0014` when narrowed. Numbering is per directory, so two
people working in different scopes cannot take the same number.

A narrowed record cannot supersede a system one — a module does not get to overrule a decision
binding other modules. The refusal says where the record belongs instead.

## What it does not contain

A description of the MADR format. That was measured rather than assumed: a session with no template
and no hints reproduced MADR's five frontmatter keys and all eight headings in order, then wrote a
correct document unaided. Carrying a copy here would spend context to no effect and go stale against
the real template.

It also carries no immutability rule of MADR's own, because MADR has none — its `date` field is
documented as *"when the decision was last updated"*. The rule in this skill follows AWS instead:

> When the team accepts an ADR, it becomes immutable. If new insights require a different decision,
> the team proposes a new ADR.

## Where this departs from MADR, and why

Checked against MADR's template and its own decision records, so that the next person can tell this
plugin's rules from the format's.

**MADR requires nothing at all.** Its template says of the frontmatter: *"These are optional
metadata elements. Feel free to remove any of them."* Its status list —
`{proposed | rejected | accepted | deprecated | … | superseded by ADR-0123}` — ends in an ellipsis
on purpose, and [ADR-0008](https://github.com/adr/madr/blob/main/docs/decisions/0008-add-status-field.md),
where MADR decided to have a status field at all, describes no lifecycle, no permitted transitions
and no field that must change alongside the status. So:

| this plugin | MADR | why |
|---|---|---|
| three transitions, everything else refused | no transitions defined | a closed set catches mistakes; an open one cannot |
| `date` is the day the record was written and never changes | *"when the decision was last updated"* | a record is dated history here, so the date of the decision is the useful one |
| `superseded by 0014` | `superseded by ADR-0123` | identifiers are directory-relative here, and `chat/0014` has no natural `ADR-` form |
| a record is immutable once accepted | no such rule | see above |

One thing worth adopting that is not here yet: [ADR-0009](https://github.com/adr/madr/blob/main/docs/decisions/0009-support-links-between-adrs-inside-an-adrs.md)
decided that a link from one record to another belongs in **More Information**, written as an
ordinary markdown link. That is MADR's own answer to the missing back-reference listed under known
gaps.

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install madr-decisions@agentic-engineering
```

## Requirements

Bash and `python3`, no packages and no network. `python3` is there for one job: the guard hook parses
the harness's JSON with it rather than grepping for a file path, because a path may contain spaces,
quotes or backslashes and the grep version works until the day it does not. **Without `python3` the
guard cannot read its input, so it allows the edit** — it says so on stderr rather than failing
closed, because a guard that wedges every session is worse than one that is honest about being
inert. The test suites additionally want `perl`.

Verified on macOS (bash 3.2, BSD tools) and on Linux under both GNU and BusyBox userlands. Windows
is untested and the guard is probably inert there: `file_path` arrives with backslashes, which the
filename check does not recognise.

## Known gaps

- **A record nobody promotes stays a draft, and a draft is editable.** `set-status.sh` exists now,
  and the permission prompt is what makes acceptance a person's decision — but nothing *reminds*
  anybody to run it. The skill tells the agent to say a record is waiting, and that is all the
  prompting there is. A record left at `proposed` for a year is unprotected for a year, which is
  correct behaviour for a draft and a trap for a decision somebody forgot to confirm.

- **A rejected replacement strands the record it superseded.** `--supersedes` flips the old record
  as soon as the new one is written, while the new one is still only `proposed`. If a human then
  rejects it, the old decision — which still holds — reads `superseded by <a rejected proposal>`,
  and the generator refuses to supersede it again because its chain already points somewhere. Fix it
  by hand: set the old record back to `accepted` and mark the rejected one as what it is.

- **Scope containment is not expressible.** If a scope logically contains another, the script cannot
  tell from the paths and will refuse the supersession. Write the new record at system scope.
- **No index is generated.** The list of records and their statuses is still maintained by hand.
- **Nothing validates a record's contents after it is written.** Certainty about the *shape* comes
  from generating the skeleton, and the guard hook protects a record once it is settled — but
  nothing reads a filled-in record and judges whether what it says is any good. Nothing could.
- **A record written entirely through the shell bypasses both.** The generator is not involved and
  the guard never fires, since `PreToolUse` does not see inside a Bash command.
- **A new record does not say what it supersedes.** The old record gains `superseded by <id>`; the
  new one carries no pointer back. Following the chain forwards works, backwards does not.
