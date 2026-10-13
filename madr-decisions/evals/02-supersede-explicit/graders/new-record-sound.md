---
type: llm
focus: trace
weight: 1
---
Find the content of the NEW decision record the agent created under `docs/adr/` (its filename starts
with `0015-`). Judge that record's content against ALL of the following; every one must hold.

1. It states what is being decided NOW: that a chat event carries a correlation id as a component of
   the event alongside the type and the payload.
2. It reads as a decision of its own rather than a lightly edited copy of the record it replaces —
   it states the current decision in its own Decision Outcome instead of narrating what the old
   record used to say.
3. Its drivers are the ones the user gave: tracing a message across queues for consumers that never
   deserialise the body, and the incident that forced it. Putting the id inside the payload appears
   as a considered-and-rejected option.
4. No section is left holding unfilled skeleton placeholders in curly braces such as `{option 1}`,
   `{justification}` or `{consequence}`.

If no new record was created at all, fail.
