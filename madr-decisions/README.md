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
around.

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

## Install

```bash
claude plugin marketplace add kkasprzak/agentic-engineering
claude plugin install madr-decisions@agentic-engineering
```

## Requirements

Nothing. Plain bash, no packages, no network.

## Known gaps

- **Scope containment is not expressible.** If a scope logically contains another, the script cannot
  tell from the paths and will refuse the supersession. Write the new record at system scope.
- **No index is generated.** The list of records and their statuses is still maintained by hand.
- **Nothing validates a record after it is written.** Certainty here comes from generating a correct
  skeleton, not from checking the result — a deliberate choice, since a check fires after the damage
  and a generator prevents it.
