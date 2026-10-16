## Parent-session delegation policy

This policy is for the parent session only. A child agent must not delegate, fan out, or launch other agents; it should complete its assigned bounded task or escalate when blocked.

- Work directly in the parent session by default, including reconnaissance, implementation, validation, and review. Task size or complexity alone is not a reason to delegate.
- Use subagents only when the user explicitly requests delegation, parallel agents, or a workflow that requires them. Do not launch agents merely because they might be useful or cheaper.
- When delegation is requested, use the fewest agents needed, with concise, bounded handoffs. Prefer a cost-conscious model and fresh context for routine work.
- Do not duplicate delegated work. Keep one writer for edits; do not add fanout or independent review passes unless requested.
- If a worker is blocked, handle the blocker or ask the user rather than launching replacement agents automatically.
