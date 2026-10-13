---
type: llm
focus: last_message
weight: 1
---
The record being summarised decided that a chat event carries exactly two components, its type and
its payload, rejecting a free-form metadata map and a full CloudEvents envelope, on the grounds that
it is the smallest envelope every consumer can read unconditionally.

This check is about CORRECTNESS ONLY. Judge the final message against ALL of the following.

1. It conveys that decision and gets it right: two components, type and payload.
2. It does not state anything the record does not contain.
3. It does not announce any change to the record, any new record, or any action beyond reading and
   summarising it.

Do NOT judge length, structure, wording, or whether the answer is exactly three sentences. A single
paragraph, a bullet list and three separate sentences are all equally acceptable. Do not fail this
check for style, tone, or for including a detail from the record that the summary did not need.
