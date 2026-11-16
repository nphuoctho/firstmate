# AI Native base: Pi Agent, Firstmate, Herdr, no-mistakes

A reusable starting kit for AI Native projects. One command sets up a machine. One script writes the no-mistakes config for any repo.

## Set up a machine

```sh
ai-native/setup.sh --check   # report what is missing, change nothing
ai-native/setup.sh           # install what is missing, never overwrite a tuned config
```

It installs:
- the Firstmate command-line tools (`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi`, `tasks-axi`) and `no-mistakes`;
- two shared Pi packages (`pi-web-access`, `cc-safety-net`) and the machine-wide no-mistakes config;
- `config/backend=herdr`, `config/crew-harness=pi`, and `config/crew-dispatch.json` (copied from `presets/`, only when missing).

`git`, `gh`, `node`, `npm`, `jq`, `tmux`, `herdr` and `pi` must already be installed; the script reports any that are not.
`FM_HOME` and `NM_HOME` move Firstmate's `config/` and `~/.no-mistakes`, so you can try the script in a sandbox.

## Add a project

```sh
ai-native/new-project.sh [--dry-run] [--verify] <repo-dir>             # detect the stacks
ai-native/new-project.sh [--dry-run] [--verify] <stacks> <repo-dir>    # name them: node, node:web,go:api
```

The script writes `<repo-dir>/.no-mistakes.yaml`. Commit it on the repo's default branch, then run `no-mistakes init`.
It never overwrites an existing file.

**Detection.** It looks for marker files in the repo root and one folder down:

| Marker | Stack | Chosen from |
| --- | --- | --- |
| `package.json` | node | `packageManager` field, else `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `package-lock.json` |
| `pyproject.toml`, `requirements.txt` | python | `uv.lock` (uv), poetry, else pip in a `.venv` |
| `go.mod` | go | |
| `Cargo.toml` | rust | |
| `Makefile` plus C or C++ files | cpp | plain make, clang-format, clang-tidy |

It emits a command only when the tool or script exists:
- Node: only the `lint`, `typecheck`, `test` and `format` scripts in `package.json`.
- Python: ruff and pytest only if the repo configures or lists them.
- C++: `make test` only if the Makefile has a `test` target; clang-tidy only if there is a `.clang-tidy` file.

Several stacks in one repo are combined, each run inside its folder, for example `(cd 'web' && npm ci) && (cd 'svc' && go mod download)`.
A stack found in the root covers same-stack folders below it.
Whatever the script had to guess is printed at the end.

The command templates and ignore patterns come from `no-mistakes/stacks/*.yaml`; the script picks, adapts or drops each command based on what the detector finds. To add a stack, add a file there and a detector in the script.

**Options.**
- `--dry-run` prints what was detected and the file it would write, and writes nothing.
- `--verify` clones the repo with `git clone --local` into a temp directory and runs the generated prepare, lint and test commands there. Each is reported as ran, failed, or skipped, and the exit code is 1 on any failure. Only committed files are cloned.

Shipped stack commands:

| Stack | prepare | lint | test |
| --- | --- | --- | --- |
| node | `npm ci` (or the detected manager) | `npm run lint` and `typecheck` | `npm run test` |
| python | `uv sync --frozen` | `uv run ruff check .` | `uv run pytest -q` |
| go | `go mod download` | `gofmt -l` and `go vet` | `go test ./...` |
| rust | `cargo fetch --locked` | `cargo fmt --check` and `cargo clippy -D warnings` | `cargo test` |
| cpp | none | `clang-format --dry-run` and `clang-tidy` | `make test` |

## How to choose

- **Fixed, machine-wide.** `no-mistakes/global-config.yaml` becomes `~/.no-mistakes/config.yaml`: the agent, the models, the timeouts and `max_concurrent_runs`. Every repo on the machine shares it. Change it there, not per project.
- **Generated per project, committed to the default branch.** `.no-mistakes.yaml`: the `commands` and the `ignore_patterns`. no-mistakes reads the command fields only from the default branch, so merge the file before the first run.
- **Hand-edit when** the repo is already red at baseline (loosen or scope the lint command until it is clean), you need a pinned Node version (put it in `prepare`), or a monorepo needs different gates per folder (edit the composed commands).
- **Commands are required.** The run worktree has no `node_modules` or `.venv`. With no `prepare`, `lint` or `test` command, the step falls back to an agent that may not be able to run anything, and the run can pass without linting. The script leaves a command out only when the repo has nothing to run, and says so. Check each one.

Other settings: `ignore_patterns` use forms like `dist/**` and `*.lock`; `**/dist/**` matches nothing. Turn on `disable_project_settings: true` only for agent-orchestration repos like Firstmate. `max_concurrent_runs` is 6 and should stay at or above the number of crew lanes, because a run holds its slot while parked at a gate and while watching CI.

## Git rules

Commits use Conventional Commits and branches use Conventional Branch. See `rules/git-conventions.md`.
The template sets the commit message form for no-mistakes fix commits. No validation workflow is installed.

## Verification

- `setup.sh --check` on an empty sandbox lists what is missing and writes nothing. A second full run changes nothing, and a hand-edited config survives.
- Generated files load through the strict no-mistakes v1.106.1 config loader, not just `doctor`, which never reads them.
- `new-project.sh --verify` passes on clean fixtures and fails on a deliberate lint defect (Go, Rust, C++, Node).
- `bin/fm-lint.sh ai-native/*.sh` and `bin/fm-doc-audience-check.sh` pass.
- Not verified: a clean Python pass (ruff and pytest are not installed here), and yarn and bun runs. Their commands are only generated.

## Token cost of Pi packages

Each user-level Pi package adds tool schemas to every request of every crew member, including no-mistakes agents. These are estimates from payload size, not billed tokens.

| Package | Tool | Tokens per request |
| --- | --- | --- |
| `@juicesharp/rpiv-todo` | `todo` | about 1.7k |
| `pi-mcp-adapter` | `mcp` | about 1.1k |
| `pi-markdown-preview` | `preview_export` | about 0.8k |
| `pi-web-access` | `web_enable` | about 0.2k |
| `cc-safety-net` | none | 0 |

Firstmate's `--exclude-tools` only hides tools from crew Pi sessions it starts. It does not apply to no-mistakes agents, so it does not help while a package is installed at user level.
So the kit loads the first three only in the primary session.
Most of the remaining cost (about 12k tokens) is the user-level skill list in `~/.agents/skills`; trimming it is up to you.

## Pi packages

| Package | Runs in | Use |
| --- | --- | --- |
| pi-web-access | every session | web search and page fetch |
| cc-safety-net | every session | blocks destructive commands |
| pi-open-tui | primary | full-screen UI, set with `/open-tui` |
| pi-mcp-adapter | primary | MCP gateway; turns off Pi's built-in MCP |
| pi-markdown-preview | primary | export Markdown to PDF, HTML, PNG |
| @juicesharp/rpiv-todo | primary | to-do list |
| pi-lens | primary, optional | diagnostics, code navigation, ast-grep |

The first two are user-level and load for crew too.
The rest load only in the primary session through `ai-native/pi-primary.sh` (`LENS=1` adds pi-lens), and `setup.sh` removes any user-level copy.
- pi-open-tui replaces Pi's input box, so Firstmate cannot read it, and a steer notice can land in the middle of what you are typing.
- pi-lens uses about 0.6 to 1.2 GB of memory per crew member.
- todo, mcp and preview_export cost tokens on every request, as above.

cc-safety-net blocks destructive git commands a crew member types, not Firstmate's own scripts.
It refused about 3.4 percent of real crew commands, mostly `git reset --hard`.
Loosening it (`workflow.worktree_mode`) is your call and you apply it in your own terminal (see `data/pi-worker-compat/report.md`).
pi-lens can attach a wrong schema (for example AWS) to the no-mistakes YAML and report false errors. Trust `no-mistakes doctor`.

## Crew model tiers

`presets/crew-dispatch.json` (`shared_quota: true`, harness `pi`):

| Work | Model |
| --- | --- |
| Mechanical upkeep (rebase, version bump, rename) | Haiku 5.5, medium |
| Everything else (default) | Sonnet 5.5, medium |
| Scouts, scans, investigations, audits | Sonnet 5.5, high |
| Planning large or risky work, read-only code review | Opus 5.5, xhigh |

## Working rules

- The primary session runs in herdr. Crew members open as herdr panes and use Pi.
- Herdr tests run only through `bin/fm-herdr-lab.sh` in an `fm-lab-*` session, never against your real herdr session.
- Machine-specific settings live in `config/`, `data/` and `state/`. They are gitignored and never committed.
