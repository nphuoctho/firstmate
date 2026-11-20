## Git conventions

Everything you need is below; you do not need to open any of the source pages.

### Commit messages (Conventional Commits 1.0.0)

Write every commit message in this shape:

```
<type>(<optional scope>): <description>

<optional body>

<optional footer(s)>
```

- **type** says what kind of change it is. Use one of these, in lowercase:
  - `feat` adds something new a user can use.
  - `fix` repairs a bug.
  - `docs` changes documentation only.
  - `refactor` restructures code without changing what it does.
  - `perf` makes something faster or lighter.
  - `test` adds or fixes tests.
  - `build` changes the build system or dependencies.
  - `ci` changes CI configuration or scripts.
  - `style` changes formatting only (spacing, semicolons), not meaning.
  - `chore` is housekeeping that touches no product code.
  - `revert` undoes earlier commits; put the reverted hashes in a footer such as `Refs: 676104e, a215868`.
- **scope** is optional: one short noun in parentheses naming the part of the code, for example `fix(parser):`.
- **description** comes right after `: ` (colon and one space). Keep it short, say what the change does, and do not end it with a period.
- **body** is optional. Leave one blank line after the description, then explain why the change was needed and anything a reviewer should know. Several paragraphs are fine.
- **footers** are optional and come after one more blank line. Each is `Token: value` (or `Token #value`), with hyphens instead of spaces in the token, for example `Reviewed-by: Z` or `Refs: #123`.
- **Breaking changes** must be marked, in either or both of these ways:
  - put `!` right before the colon: `feat(api)!: remove the v1 endpoints`;
  - add a footer in capitals: `BREAKING CHANGE: the config file now uses YAML`.
- If one commit would need two types, split it into two commits.

Examples:

```
feat(lang): add Polish language
docs: correct spelling of CHANGELOG
fix: prevent racing of requests

Introduce a request id and dismiss responses other than the latest one.

Refs: #123
```

### Branch names (Conventional Branch 1.1.0)

Firstmate already chose this task's branch name; keep it. It follows `<type>/<description>`:

- Types: `feature/` (or `feat/`) for new features, `bugfix/` (or `fix/`) for bug fixes, `hotfix/` for urgent fixes, `release/` for release preparation, `chore/` for non-code work such as dependencies or docs. `main`, `master` and `develop` are trunk branches and have no prefix.
- The description uses only lowercase letters, numbers, hyphens between words, and dots (for versions such as `release/v1.2.0`). No capitals, spaces, underscores or other symbols, and no doubled, leading or trailing hyphens or dots.
- Include a ticket number when there is one, in lowercase: `feature/issue-123-new-login`.
- If you ever must create another branch yourself, follow the same rules.

### Pull request titles and descriptions

- The PR title uses the same shape as a commit message, without body or footers: `<type>(<optional scope>): <description>`, for example `feat(usage): show reset times` or `fix: rate limit exceeded`. Pick the type the same way as for commits; mark breaking changes with `!`.
- Every PR that is not a draft needs a title in this form.
- Write the title and description in clear, plain English that a newcomer can follow: what changed, why, and how it was checked.

## Check before you report done

Before you report done, find the checks this project already defines for itself (type checking, linting, static analysis, formatting checks; look at its scripts, task runner, CI workflow and contributor docs) and run them, then fix everything they report. Tests passing is not enough on its own. Do not install new tools to do this; if the project defines no such checks, say so in your report.
