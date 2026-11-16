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

- Types: use `feat` for a new feature (SemVer minor) and `fix` for a bug fix (SemVer patch).
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
The fix commits no-mistakes makes then have the Conventional Commits form, and so does the catch-all commit of its push step.
Two kinds are exempt: commits made by its rebase step, and commits on its `no-mistakes/evidence` branch.
The loader accepts this template and rejects unknown placeholders.

The same file leaves `pr.title_format` unset on purpose.
With no format, no-mistakes already writes Conventional Commits PR titles.
Setting a format would replace that.

Nothing can enforce the rest from this repo.
No-mistakes has no setting for branch names, and your own commits and PR titles are only as good as the person or agent writing them.
Point agents at this file instead.

## Using it with Firstmate

Firstmate names each worker's branch `<prefix><task-id>`, and the default prefix is `fm/`.
`fm/` is not a Conventional Branch type, so by default the branches workers create break the rule above.
Two ways to fix that:

- Per task: pass `--branch-prefix <type>/` when the task is briefed and spawned, with the type that fits the work: `feature/`, `bugfix/`, `hotfix/`, `release/` or `chore/`.
- Per project: register the project with a `branch=<prefix>` token in its registry entry, for example `[no-mistakes branch=chore/]`.
  That sets one prefix for every task in the project, so the per-task flag is the better fit when the work varies.
  `bin/fm-project-mode.sh` documents the token, and `bin/fm-project-mode.sh --branch-prefix <project>` prints the prefix in force.

A worker's own commit messages and PR titles are only as good as the brief.
Tell the worker to follow this file.
