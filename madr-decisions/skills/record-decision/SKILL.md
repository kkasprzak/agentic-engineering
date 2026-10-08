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
  convincing rationale for almost any choice, and nobody reading it next year can tell it apart from
  one that was sourced. **If you cannot source a reason, ask — do not fill the gap.** The next
  decision gets built on top of this one, which is what makes an invented reason a liability rather
  than merely a waste. Where to look is below.
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

## Where the reasons come from

Code shows what was built. It never shows what was considered and dropped, and that is the part most
easily invented. Sources differ in whether they hold it at all.

**Written at the time, and holds the alternatives.** A whole record can come from one of these.

1. **A review thread where someone challenged the choice.** The best of all: written, adversarial,
   already tied to the code. What the reviewer pushed back on is exactly what a future reader will
   try to "fix" back, which is the most valuable thing a record can say.
2. **A conversation where the decision was made.** Test it for what was *decided*, not what was
   *discussed* — people float an option and move on without choosing anything.
3. **An architect's plan.** Holds the approach and the rejections by construction, but it is one
   person's reasoning untested by disagreement, and it mixes design decisions with sequencing ones.
   Only the design decisions belong in a record; the sequence is dead once the work lands.
4. **An abandoned branch or a reverted commit.** Proves an option was really tried, and gives a
   result rather than a prediction.

**Recalled afterwards.** Usable, but say in the record that it was.

5. **The person, asked.** The only source for a driver that lives nowhere else — "we thought we
   could do X, the framework does not allow it". People also rationalise after the fact, and the
   further from the decision, the more they do.

**Never held the reasoning.** These cannot source `Considered Options` at all.

6. The code as it stands. It fixes the outcome accurately and the alternatives not at all.
7. A ticket, a commit message, general good practice, or your own sense of what seems reasonable.

**When the only source is from the last group, say so in the record** — leave `Considered Options`
empty with a note, or do not write the record yet. An empty section is honest. A filled one nobody
can check is a falsehood with a very long shelf life.

### A thread with an agent counts, with one extra rule

It is written at the time, and it often holds options that were *tested* rather than merely floated,
which puts it above most sources. But most of what it holds is the agent's own output, and an option
an agent raised that nobody engaged with was never considered by anyone.

**An option counts as considered when a person engaged with it, or when evidence killed it.**
Everything else is noise produced along the way. This matters more here than for a meeting
transcript, where every participant could decide — and it matters most when the agent writing the
record is the one that generated the options, because it cannot tell its own suggestion apart from
someone else's decision.

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
