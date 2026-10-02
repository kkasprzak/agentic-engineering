---
name: record-decision
description: >-
  Write down a decision as a MADR record, or record the one that supersedes it. Trigger on "write an
  ADR", "record this decision", "we should document this choice", "create a decision record", "this
  decision is out of date", "supersede ADR-NNNN", "that record no longer matches the code", and
  whenever a choice was made for reasons that will not survive in anyone's head. Not for writing a
  design doc, a spec, or an explanation of how something works.
---

# Recording a decision

**Goal:** a reader a year from now can tell what was decided, what it was decided instead of, and
why — and can tell whether it still holds.

**Constraints:** start from the script, never from memory. A record that has been accepted is
history: it is superseded, never rewritten.

You already know the MADR format, so this says nothing about its sections. What follows is what the
format does not carry.

## Gotchas

- **A decision record is not documentation of the code.** It is dated, and it says what was decided
  *then*. When the code moves on, the record does not become wrong — it becomes superseded. Rewriting
  its original sections to match today's code destroys the only copy of what was decided, and leaves
  a document that cannot be read as history any more.
- **The tell is in the commit message.** "The record no longer describes something that does not
  exist" means the author has mistaken a dated record for documentation to keep in sync. There is
  nothing to sync; there is a new record to write.
- **Amending while editing produces a document that contradicts itself.** Adding "as written, this
  decision said X" above a paragraph you just rewrote so it no longer says X is worse than either
  change alone: now the record disagrees with itself and a reader cannot tell which half to trust.
- **One decision per record.** Test it against the title: a section that cannot be read as a
  consequence of the title belongs in its own record. Three decisions in one document means none of
  them can be superseded without disturbing the other two.
- **If the fact is already in a javadoc, a test name or a type, link to it.** Copying it creates a
  second place to drift, and the code is the copy that stays true. A record explains *why that
  choice*, not *how it works* — the how is in the code and updates itself.
- **`Confirmation` is for how compliance is checked**, not for listing the tests that happened to be
  written. A fitness function, an ArchUnit rule, a review step. A list of test names goes stale on
  the first refactor and nobody updates it.

## Scope is the directory

```
docs/adr/           a decision that binds the whole system
docs/adr/<name>/    a decision confined to one module or a group of them
```

Nothing records the scope as a field, because a field can disagree with where the file actually
lives. Identifiers follow: `0014` at system scope, `chat/0014` when narrowed.

A narrowed record cannot supersede a system one. A module does not get to overrule a decision that
binds other modules — if it really changes, the new record belongs at system scope. The script
refuses and says so.

## Making one

```bash
scripts/new-decision.sh "Title"                        # system scope
scripts/new-decision.sh --scope chat "Title"           # narrowed
scripts/new-decision.sh --supersedes 0014 "Title"      # replaces 0014
```

It picks the number, the path and the filename, and writes the frontmatter with the five MADR keys
and nothing else. Superseding changes **one line** of the old record — its status — and leaves the
rest of that file exactly as it was.

Then fill the skeleton in. If `Considered Options` has one entry, there was no decision to record;
write it down somewhere cheaper.

## Status

`proposed` → `accepted` → `superseded by <id>`, with `rejected` and `deprecated` for the cases that
never land or simply stop mattering.

`RFC` is not one of these. An RFC is a different kind of document — speculative, pre-decision, open
for comment — and a record parked in that state is usually a decision that was made long ago and
never marked as such.
