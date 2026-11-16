# Git conventions

Commits follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
Branches follow [Conventional Branch 1.1.0](https://conventionalbranch.org/).
No PR-title or commit validation workflow is installed on purpose, so both are conventions, not checks.

## Commits

```
<type>[(scope)][!]: <description>

[body]

[footer(s)]
```

- Types: `feat` (new feature, SemVer minor) and `fix` (bug fix, SemVer patch) are required by the spec.
  Other types are allowed. The common set is `build`, `chore`, `ci`, `docs`, `style`, `refactor`, `perf`, `test`, and `revert`.
- Scope is an optional noun in parentheses that names the part of the code, such as `fix(parser):`.
- The description follows the colon and one space. Keep it short.
- A body starts one blank line after the description and is free text.
- A breaking change is marked with `!` right before the colon (`feat(api)!: drop v1 routes`), with a `BREAKING CHANGE: <description>` footer, or both. The footer token must be uppercase. `BREAKING-CHANGE` means the same. It is a SemVer major, whatever the type.
- Footers come one blank line after the body. Each is `Token: value` or `Token #value`, with `-` in place of spaces in the token (`Reviewed-by: Z`, `Refs: #123`).
- Casing is not significant except for `BREAKING CHANGE`. Pick one and keep it.

## Branches

Shape: `<type>/<short-kebab-description>`.

- Types: `feature` (alias `feat`), `bugfix` (alias `fix`), `hotfix`, `release`, `chore`.
  The spec also lists agent prefixes: `ai`, `claude`, `codex`, `copilot`, `cursor`.
- Trunk branches `main`, `master` and `develop` take no prefix.
- The description uses lowercase `a-z`, digits and hyphens. Dots are allowed, mostly for versions (`release/v1.2.0`).
  No spaces, underscores or uppercase. No doubled, leading or trailing hyphens or dots, and no dot next to a hyphen.
- Put a ticket number in the name when there is one: `feature/issue-123-new-login`.
- The spec sets no length limit. Keep names short enough to read in a branch list.
- A type outside the list is invalid under the spec. A team may add its own types, but must document them.

## What the kit wires in

`no-mistakes/project.no-mistakes.yaml` sets `commit.fix_message` to `chore(no-mistakes-{{.Step}}): {{.Summary}}`.
Every fix commit no-mistakes makes then has the Conventional Commits form, and so does the catch-all commit of its push step.
The loader accepts this template and rejects unknown placeholders.

The same file leaves `pr.title_format` unset on purpose.
With no format, no-mistakes already writes Conventional Commits PR titles.
Setting a format would replace that.

Nothing can enforce the rest from this repo.
No-mistakes has no setting for branch names, and your own commits and PR titles are only as good as the person or agent writing them.
Point agents at this file instead.
