# AI Native base: Pi Agent, Firstmate, Herdr, no-mistakes

A starting kit for AI Native projects. One script sets up a machine. Another writes the no-mistakes config for any repo.

- **Pi** is the coding agent that does the work.
- **Firstmate** is the supervisor: it hands tasks to workers, watches them and reports to you.
- **Herdr** is the terminal multiplexer where the primary session and the workers each get a pane.
- **no-mistakes** checks a change (review, lint, tests) before it is pushed and opens the pull request.

The primary session is the Pi session you talk to. Workers are the other Pi sessions Firstmate starts.

## Set up a machine

```sh
ai-native/setup.sh --check   # report what is missing, change nothing; exits 1 if anything is missing
ai-native/setup.sh           # install what is missing
```

Any other argument prints the usage and installs nothing.

Install these first. The script reports any that are missing:
- `git`, `gh`, `node`, `npm`, `jq`, `curl`;
- `herdr` (https://herdr.dev), `pi` (https://pi.dev) and `treehouse` (Firstmate needs it for the Herdr backend).

It then installs what is missing:
- `no-mistakes` and its machine-wide config (`no-mistakes/global-config.yaml`). The installer's untouched default config (or one the installer writes during the same run) is replaced after saving a `config.yaml.bak.<time>` copy. A config with the line `# ai-native-kit-config`, or any other config you edited, is never touched; setup says so and you can copy `no-mistakes/global-config.yaml` over it by hand;
- the Firstmate command-line tools `gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi` and `tasks-axi`, with `setup hooks` run for the first three;
- two shared Pi packages, `pi-web-access` and `cc-safety-net` (the Pi package check is skipped, with a message, when `pi` is missing);
- `config/backend=herdr`, `config/crew-harness=pi` and `config/crew-dispatch.json` (copied from `presets/`), each only when missing.

`--check` is the only fully safe dry look.
A real run in a sandbox needs all of `HOME`, `NPM_CONFIG_PREFIX`, `FM_HOME` and `NM_HOME` set to scratch folders, and a limited `PATH`.
`FM_HOME` and `NM_HOME` alone are not enough: `npm install -g`, `pi install` and the no-mistakes installer write under the real npm prefix, `~/.pi` and `~/.no-mistakes/bin`.

`ai-native/pi-primary.sh` starts the primary session with the primary-only packages. It needs network on first launch, to download them.

## Add a project

```sh
ai-native/new-project.sh [--dry-run] [--verify] <repo-dir>             # detect the stacks
ai-native/new-project.sh [--dry-run] [--verify] <stacks> <repo-dir>    # name them: node, node:web,go:api
```

The script writes `<repo-dir>/.no-mistakes.yaml`. Commit it on the repo's default branch, then run `no-mistakes init`.
It never overwrites an existing file and prints the commit and branch rules inline when it writes one. The generated file also has a review instruction for them.

It looks for marker files in the repo root and one folder down:

| Marker | Stack | Chosen from |
| --- | --- | --- |
| `package.json` | node | `packageManager` field, else `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `package-lock.json` |
| `pyproject.toml`, `requirements.txt` | python | `uv.lock` (uv), poetry, else pip in a `.venv` |
| `go.mod` | go | |
| `Cargo.toml` | rust | |
| `Makefile` plus committed C or C++ files | cpp | plain make, clang-format, clang-tidy |

"Committed" means `git ls-files` lists a `.c`, `.cc`, `.cpp`, `.cxx`, `.h`, `.hh`, `.hpp` or `.hxx` file.

It writes a command only when the tool or script exists:
- Node: only the `lint`, `typecheck`, `test` and `format` scripts in `package.json`.
- Python: ruff only when it is listed as a dependency (a `ruff.toml` or `[tool.ruff]` table alone is not enough, because `uv run ruff` would fail). pytest only when the repo mentions it. A Python repo with neither gets no config; name `python` to get the stock uv commands.
- C++: `make test` only if the Makefile has a `test` target; clang-tidy only if there is a `.clang-tidy` file.

Several stacks in one repo are combined, each run inside its folder, for example `(cd 'web' && npm ci) && (cd 'svc' && go mod download)`.
A stack found in the root covers same-stack folders below it.
Whatever the script had to guess is printed at the end.

Options:
- `--dry-run` prints what was detected and the file it would write, and writes nothing.
- `--verify` clones the repo with `git clone --local` into a temp directory and runs the generated prepare, lint and test commands there. Only committed files are cloned. Each step is reported as passed, FAILED, or skipped. A step whose tool is not installed prints `skipped: <tool> not installed`. The exit code is 1 if any step failed or was skipped for a missing tool. With `--dry-run` it still verifies the repo as it is.

Stock commands per stack, from `no-mistakes/stacks/*.yaml`. To add a stack, add a file there and a detector in the script.

| Stack | prepare | lint | test |
| --- | --- | --- | --- |
| node | `npm ci` (or the detected manager) | `npm run lint` and `typecheck` | `npm run test` |
| python | `uv sync --frozen` | `uv run ruff check .` | `uv run pytest -q` |
| go | `go mod download` | `gofmt -l` and `go vet` | `go test ./...` |
| rust | `cargo fetch --locked` | `cargo fmt --check` and `cargo clippy -D warnings` | `cargo test` |
| cpp | none | `clang-format --dry-run` and `clang-tidy` | `make test` |

## Which file holds what

- `no-mistakes/global-config.yaml` becomes `~/.no-mistakes/config.yaml`: the agent, the models, the timeouts and `max_concurrent_runs`. Every repo on the machine shares it. Change it there, not per project.
- `.no-mistakes.yaml` is generated per project and committed to the default branch. It holds the `commands` and the `ignore_patterns`. no-mistakes reads the command fields only from the default branch, so merge the file before the first run.

Hand-edit `.no-mistakes.yaml` when:
- the repo already fails at baseline: loosen or scope the lint command until it passes;
- you need a pinned Node version: put it in `prepare`;
- a monorepo needs different checks per folder: edit the combined commands.

Keep the commands. no-mistakes runs in a temporary checkout with no `node_modules` or `.venv`. Without a `prepare`, `lint` or `test` command, that check falls back to an agent that may not be able to run anything, and the run can pass without linting.
The script leaves a command out only when the repo has nothing to run, and says so.

Other settings:
- `ignore_patterns` use forms like `dist/**` and `*.lock`. `**/dist/**` matches nothing.
- `disable_project_settings: true` is only for repos that run agents themselves, like Firstmate, so the checking agent does not take a supervisor role from their `AGENTS.md`.
- `max_concurrent_runs` is 6. A run keeps its slot while it waits for your answer and while it watches CI, so keep it at or above the number of workers you run in parallel.

## Git rules

Commits use Conventional Commits and branches use Conventional Branch. See `rules/git-conventions.md`, which also says how to use them with Firstmate.
The template sets the commit message form for the fix commits no-mistakes makes. No validation workflow is installed.

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

The first two are installed for your user and load in worker sessions too.
The rest load only in the primary session through `ai-native/pi-primary.sh` (`LENS=1` adds pi-lens), and `setup.sh` removes any user-level copy.
- pi-open-tui replaces Pi's input box, so Firstmate cannot read it, and a steer notice can land in the middle of what you are typing.
- pi-lens uses about 0.6 to 1.2 GB of memory per worker.
- `todo`, `mcp` and `preview_export` cost tokens on every request (see the table at the end).
- pi-lens can attach a wrong schema (for example AWS) to the no-mistakes YAML and report false errors. Trust `no-mistakes doctor`.

cc-safety-net blocks destructive git commands a worker types, not Firstmate's own scripts.
In one sample it refused about 3.4 percent of real worker commands, mostly `git reset --hard`.
Loosening it (`workflow.worktree_mode`) is your call, made in your own terminal.

## Worker model tiers

`presets/crew-dispatch.json` (`shared_quota: true`, harness `pi`) tells Firstmate which model each kind of task gets:

| Work | Model |
| --- | --- |
| Mechanical upkeep (rebase, version bump, rename) | Haiku 5.5, medium |
| Everything else (default) | Sonnet 5.5, medium |
| Scouts (read-only investigations), scans, audits | Sonnet 5.5, high |
| Planning large or risky work, read-only code review | Opus 5.5, xhigh |

## Working rules

- The primary session runs in Herdr. Workers open as Herdr panes and use Pi.
- Herdr tests run only through `bin/fm-herdr-lab.sh` in an `fm-lab-*` session, never against your real Herdr session.
- Machine-specific settings live in `config/`, `data/` and `state/`. They are gitignored and never committed.

## Verification

- `ai-native/tests/new-project.test.sh` builds throwaway repos (node, python, go, rust, make C++, a monorepo, an empty repo) and checks detection and `--dry-run`. It installs nothing and runs in about a second.
- `setup.sh --check` on an empty sandbox lists what is missing and writes nothing. A second full run changes nothing, and a config with the kit marker or a hand-tuned config survives byte for byte.
- Generated files load through the strict no-mistakes v1.106.1 config loader, not just `doctor`, which never reads them.
- `new-project.sh --verify` passes on clean fixtures (Go, Rust, C++, Node, Python with uv and with pip) and fails on a deliberate lint defect. yarn and bun commands are generated but were never run.
- `bin/fm-lint.sh ai-native/*.sh` and `bin/fm-doc-audience-check.sh` pass.

## Token cost of Pi packages

Each user-level Pi package adds tool schemas to every request of every worker, including the no-mistakes agents. These are estimates from payload size, not billed tokens.

| Package | Tool | Tokens per request |
| --- | --- | --- |
| `@juicesharp/rpiv-todo` | `todo` | about 1.7k |
| `pi-mcp-adapter` | `mcp` | about 1.1k |
| `pi-markdown-preview` | `preview_export` | about 0.8k |
| `pi-web-access` | `web_enable` | about 0.2k |
| `cc-safety-net` | none | 0 |

Firstmate's `--exclude-tools` only hides tools from the worker sessions it starts. It does not apply to no-mistakes agents, so it does not help while a package is installed for your user.
So the kit loads the first three only in the primary session.
Most of the remaining cost (about 12k tokens) is the skill list in `~/.agents/skills`; trimming it is up to you.
