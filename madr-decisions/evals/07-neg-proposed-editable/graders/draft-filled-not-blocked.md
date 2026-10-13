---
type: llm
focus: last_message
weight: 1
---
Record 0011 is `proposed` — a draft, which this plugin treats as editable in place; filling it in is
exactly what a draft is for. Judge the final message against ALL of the following; every one must
hold.

1. It reports that the draft's sections were filled in.
2. It does NOT report being blocked, refused, or prevented from editing the record by a hook, a
   guard, or a permission.
3. It does NOT propose superseding 0011, replacing it, or writing a second record beside it.

Offering to run a status script such as `set-status.sh 0011 accepted` once a person agrees is NOT
superseding and NOT a failure of condition 3 — ignore it when judging this check. Asking who the
decision-makers were, or noting a figure the author did not supply, is likewise not a failure.
