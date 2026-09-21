## Parent-session delegation policy

This policy is for the parent session only. A child agent must not delegate, fan out, or launch other agents; it should complete its assigned bounded task or escalate when blocked.

- Before doing substantial reconnaissance or a well-scoped implementation, the parent delegates it to one capable, cost-conscious role when delegation is useful.
- Prefer the cheap role model for routine bounded work. Use concise, scoped handoffs and request concise outputs.
- Do not duplicate delegated work. Keep one writer for edits; do not require fanout or review passes.
- The parent handles tiny tasks, ambiguous decisions, and final synthesis.
- If a cheap worker is blocked, the parent handles the blocker or escalates rather than silently duplicating the worker's task.
- Prefer fresh context for workers and other routine bounded agents; use forked context for oracle advice when inherited decisions matter.
