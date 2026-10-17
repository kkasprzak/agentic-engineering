---
type: llm
focus: last_message
---
Judge the final message against ALL of the following.

1. It names a developer, a tester and a solution-architect role.
2. For each, it says what the role is for, consistent with: the developer implements one scoped
   task; the tester verifies someone else's work and does not fix it; the solution-architect decides
   how a change should be made and does not implement.
3. It does not present any other role as one this plugin ships. Saying that `--role` also accepts
   agent definitions from elsewhere is correct and must not fail this check.

Do NOT judge length, structure or wording.
