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

**Constraints:** every reason in the record is sourced, not reconstructed. The skeleton comes from
the script and is filled in place. A record that has been accepted is history: it is superseded,
never rewritten.

You already know the MADR format, so this says nothing about its sections. What follows is what the
format does not carry.

## Gotchas

- **A reason that merely sounds plausible is worse than no record at all.** You can write a
  convincing rationale for almost any choice, and nobody reading it next year can tell the
  difference. Every driver, option and consequence must come from the code, the conversation, or the
  person who decided. **If you cannot source one, ask — do not fill the gap.** This is the easiest
  way to produce a document that looks like work and is actually a liability.
- **Fill the skeleton in place; do not rewrite the file.** The script already wrote the frontmatter,
  the headings and the numbering. Open what it printed and replace the `{placeholders}` — nothing
  else. Rewriting the file from scratch means retyping the parts that were generated precisely so
  they would not have to be retyped, and that is where a near-miss of the format creeps back in.
- **A decision record is not documentation of the code.** It is dated, and it says what was decided
  *then*. When the code moves on, the record does not become wrong — it becomes superseded.
  Rewriting its original sections to match today's code destroys the only copy of what was decided.
- **The tell is in the commit message.** "The record no longer describes something that does not
  exist" means the author has mistaken a dated record for documentation to keep in sync. There is
  nothing to sync; there is a new record to write.
- **Amending while editing produces a document that contradicts itself.** Adding "as written, this
  decision said X" above a paragraph you just rewrote so it no longer says X is worse than either
  change alone: now the record disagrees with itself and a reader cannot tell which half to trust.
- **One decision per record.** Test it against the title: a section that cannot be read as a
  consequence of the title belongs in its own record. When that test fires, **say so and ask** before
  creating the second record — what is worth recording separately is the author's call, not yours.
- **If the fact is already in a javadoc, a test name or a type, link to it.** Copying it creates a
  second place to drift, and the code is the copy that stays true. A record explains *why that
  choice*, not *how it works*.
- **`Confirmation` describes how compliance is checked, and only if it already is.** Naming an
  ArchUnit rule or a test that does not exist states a fact that is false. If the check is not
  written yet, either drop the section or say plainly that it is a commitment rather than a
  description — never let it read as something already in place.

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

The script lives beside this skill, at `scripts/new-decision.sh` **relative to the skill directory**,
not to the repository you are working in. Run it from the repository root, since the paths it writes
are relative to where it is invoked.

```bash
<skill>/scripts/new-decision.sh "Title"                   # system scope
<skill>/scripts/new-decision.sh --scope chat "Title"      # narrowed
<skill>/scripts/new-decision.sh --supersedes 0014 "Title" # replaces 0014
<skill>/scripts/new-decision.sh --print "Title"           # skeleton to stdout, writes nothing
```

It picks the number, the path and the filename, and writes the frontmatter with the five MADR keys
and nothing else. Superseding changes **one line** of the old record — its status — and leaves the
rest of that file exactly as it was.

`--print` is also how you check a record you have already filled in still matches the skeleton:
diff it against the file.

Then open the file it named and fill it in. If `Considered Options` has one entry, there was no
decision to record; write it down somewhere cheaper.

**`decision-makers`, `consulted` and `informed` are optional.** Leave them empty unless you actually
know who they were — a name you inferred is the same failure as a reason you invented.

**If you find a record that is still all placeholders**, it was generated and abandoned. Fill it or
delete it; do not create a second one beside it.

## Status

A freshly written record stays at `proposed`. **Promoting it to `accepted` is a human decision** and
is not part of writing it — do not set it yourself.

The rest of the lifecycle is `rejected` and `deprecated` for the cases that never land or stop
mattering, and `superseded by <id>`, which the script writes for you.

`RFC` is not one of these. An RFC is a different kind of document — speculative, pre-decision, open
for comment — and a record parked in that state is usually a decision that was made long ago and
never marked as such.
