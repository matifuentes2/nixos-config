---
description: Go, commit and push unstaged changes, open a PR, resolve conflicts
argument-hint: "[target-branch]"
---
Go. When done, commit and push unstaged changes. If the optional target-branch argument (`$1`) was provided, open the PR targeting that branch. Otherwise, target `develop` (or `dev` if `develop` does not exist). Write the title and description in Spanish, with technical jargon in English. If a merge conflict arises, solve it.

Before writing or updating the PR description:
- Inspect the branch diff, commits, and relevant code changes.
- Identify the current intent of the PR, especially if the implementation evolved from the initial request.
- Preserve accurate useful context from any existing PR description, but remove stale claims, TODOs, or implementation details that are no longer true.

The PR description should be easy to follow and should include:
- A concise summary of the current intent of the PR.
- The main code or behavior changes, grouped in readable bullets.
- Clear examples that showcase the changes and the value they offer. Prefer short before/after examples, usage examples, workflow examples, or user-facing behavior examples when applicable.
- Validation performed, if known or executed.
- Any relevant caveats, follow-ups, or rollout notes.

PR description formatting is mandatory so it renders properly in the GitHub PR web UI:
- Write the PR body as Markdown with real newline characters, never with literal escaped sequences like `\n`.
- Do not pass a multiline body directly through a quoted `--body "...\n..."` argument.
- Create a temporary Markdown file with a single-quoted heredoc and pass it with `gh pr create --body-file <file>` (or `gh pr edit --body-file <file>` when updating an existing PR), for example:

```sh
body_file="$(mktemp)"
cat > "$body_file" <<'EOF'
## Resumen
- Describe el estado actual del PR y su intención.

## Cambios principales
- Explica el cambio técnico principal.
- Explica cualquier ajuste de comportamiento relevante.

## Ejemplos y valor
- Antes: el flujo requería un paso manual o generaba un resultado ambiguo.
- Ahora: el flujo queda explícito, validado o automatizado, reduciendo errores.

## Validación
- `comando de validación ejecutado`

## Notas
- Caveats, follow-ups o rollout notes relevantes, si aplica.
EOF
gh pr create --base "$base_branch" --head "$branch" --title "$title" --body-file "$body_file"
```

Before reporting completion, verify the stored PR body renders as intended and does not contain literal escape sequences:

```sh
gh pr view <PR> --json body --jq .body
```

If literal `\n` or other escaped formatting artifacts appear in the output, fix the PR body before finishing.
