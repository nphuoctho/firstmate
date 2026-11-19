## Git conventions

- Commit messages follow Conventional Commits 1.0.0 (https://www.conventionalcommits.org/en/v1.0.0/): `<type>(<optional scope>): <description>`, for example `fix(auth): refresh the token before it expires`. Use `!` or a `BREAKING CHANGE:` footer for breaking changes.
- Branch names follow Conventional Branch (https://conventionalbranch.org/). Firstmate already chose this task's branch name; keep it.
- Pull request titles follow the same Conventional Commits form, as described at https://flank.github.io/flank/pr_titles/, for example `feat(usage): show reset times`. Write the title and description in clear, plain English that a newcomer can follow.

## Check before you report done

Before you report done, find the checks this project already defines for itself (type checking, linting, static analysis, formatting checks; look at its scripts, task runner, CI workflow and contributor docs) and run them, then fix everything they report. Tests passing is not enough on its own. Do not install new tools to do this; if the project defines no such checks, say so in your report.
