# AI Native base: Pi Agent, Firstmate, Herdr, no-mistakes

A starting kit for AI Native projects. One script sets up a machine. Another writes the no-mistakes config for any repo.

- **Pi** is the coding agent that does the work.
- **Firstmate** is the supervisor: it hands tasks to workers, watches them and reports to you.
- **Herdr** is the terminal multiplexer where the primary session and the workers each get a pane.
- **no-mistakes** checks a change (review, lint, tests) before it is pushed and opens the pull request.

The primary session is the Pi session you talk to. Workers are the other Pi sessions Firstmate starts.

## Set up a machine

```sh
ai-native/setup.sh --check   # report what is missing, install nothing; exits 1 if anything is missing
ai-native/setup.sh           # install what is missing
```

Any other argument prints the usage and installs nothing.

Install these first. The script reports any that are missing:
- `git`, `gh`, `node`, `npm`, `jq`, `curl`;
- `herdr` (https://herdr.dev), `pi` (https://pi.dev) and `treehouse` (Firstmate needs it for the Herdr backend).

It then installs what is missing:
- `no-mistakes` and its machine-wide config (`no-mistakes/global-config.yaml`). A config the no-mistakes installer writes during the same run is replaced after saving a `config.yaml.bak.<time>` copy. Any config that already exists is never touched, with or without the line `# ai-native-kit-config`; setup prints the command to adopt `no-mistakes/global-config.yaml` by hand;
- the Firstmate command-line tools `gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi` and `tasks-axi`, with `setup hooks` run for the first three;
- two shared Pi packages, `pi-web-access` and `cc-safety-net` (the Pi package check is skipped, with a message, when `pi` is missing);
- the Herdr integration for `pi`, and for `omp` when it is installed, so Herdr shows whether each agent is working, blocked or done;
- `config/backend=herdr`, `config/crew-harness=pi` and `config/crew-dispatch.json` (copied from `presets/`), each only when missing.

An existing `config/crew-dispatch.json` that differs from the preset is left alone, and setup prints the `diff` command to compare them.

`--check` installs nothing and changes no settings, so it is the only fully safe dry look.
It can still create cache files: `pi list` creates `~/.pi/agent/` and `no-mistakes doctor` writes an update check under `NM_HOME`.
A real run in a sandbox needs all of `HOME`, `NPM_CONFIG_PREFIX`, `FM_HOME` and `NM_HOME` set to scratch folders, and a limited `PATH`.
`FM_HOME` and `NM_HOME` alone are not enough: `npm install -g`, `pi install` and the no-mistakes installer write under the real npm prefix, `~/.pi` and `~/.no-mistakes/bin`.

## Start the primary session

Open Herdr, go to this repo's folder and run `pi`.
Approve Pi's project trust prompt once, so Firstmate's extensions in `.pi/extensions/` load.

- Give the primary session your strongest model at `high` or `xhigh` effort with `/model`, because it keeps track of every project and worker.
- Run `/supervision-model` to put Firstmate's background supervision on a cheaper model and effort, for example Haiku 5.5 at `medium`, while your own conversation keeps its model.
- Run `/calm` to hide tool calls, so you see only your messages and the replies.

When you add a project, Firstmate asks how its changes are delivered.
Use a direct pull request while the project is a prototype.
Switch to no-mistakes once its changes are ones you would otherwise want a person to review.

## Run workers on Oh My Pi

Workers can use Oh My Pi (`omp`) instead of Pi.
Put `omp` in `config/crew-harness` and change `"harness": "pi"` to `"harness": "omp"` in every profile of `config/crew-dispatch.json`.
Firstmate starts each omp worker with `.omp/fm-worker-overlay.yml`, so it does not stop on prompts, and your own `~/.omp/agent/config.yml` is not changed.

- `config/crew-exclude-tools` does not work with omp: a list with any entry stops the worker from starting.
- omp workers load the MCP servers in your `~/.omp/agent/mcp.json` and can start omp's own sub-agents, up to your `task.maxConcurrency`.
- Keep the primary session on Pi, because omp has no `/calm` or `/supervision-model`.

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
- Python: ruff only when it is listed as a dependency (a `ruff.toml` or `[tool.ruff]` table alone is not enough, because `uv run ruff` would fail). pytest only when it is listed as a dependency that prepare installs. A Python repo with neither gets no config; name `python` to get the stock uv commands.
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

Packages installed for your user load in every Pi session: the primary, every worker and every no-mistakes agent.
The kit installs only two:

| Package | Use |
| --- | --- |
| pi-web-access | web search and page fetch |
| cc-safety-net | blocks destructive commands and reads of secret files |

`setup.sh` removes a user-level copy of these packages, because Firstmate already covers what they do or they cost too much in every session:

| Package | Why not |
| --- | --- |
| pi-mcp-adapter | Pi already has MCP built in (`pi mcp add`), and it loads server tools only when needed |
| pi-open-tui | replaces Pi's input box, so Firstmate cannot read it, and a message from Firstmate can land in the middle of what you are typing; use `/calm` instead |
| @juicesharp/rpiv-todo | Firstmate keeps its own backlog; the tool costs about 1.7k tokens per request |
| pi-lens | gives the agent live code feedback (language servers, linters, formatters, type checks, ast-grep), but uses about 0.6 to 1.2 GB of memory per session, and it can attach a wrong schema (for example AWS) to the no-mistakes YAML; no-mistakes already runs each repo's own lint and tests |
| pi-markdown-preview | about 0.8k tokens per request in every session |

If you want Markdown previews in the primary session only, install a pinned version for this folder: `pi install -l npm:pi-markdown-preview@0.27.0`.
That writes `.pi/settings.json` here, which workers never read because they run in their own copies of each repo.
Add `.pi/settings.json` and `.pi/npm/` to `.git/info/exclude` so they are never committed.

### Sub-agents (optional)

`pi-subagents` lets a Pi session hand parts of its task to sub-agents, like Claude Code's Agent tool or omp's built-in task tool.
The kit does not install it, and `setup.sh` leaves it alone if you do.

- Inside a worker it is fine: the sub-agents work in that worker's own copy of the repo, and Firstmate tracks the worker.
- The primary session must never use a sub-agent tool to do project work.
  That work has no durable record and no isolated copy of the repo, so Firstmate cannot see it and it is lost when the session restarts (see `docs/subagent-guard.md`).
- Claude Code primaries have a tool-level guard for this, but Pi and omp primaries do not yet, so the rule depends on the agent following it.
- Every sub-agent spends its own tokens, so a worker that fans out uses more quota.
- Installed for your user, it loads in every Pi session, including the no-mistakes agents.

cc-safety-net blocks destructive git commands a worker types, not Firstmate's own scripts.
In one sample it refused about 3.4 percent of real worker commands, mostly `git reset --hard`.
Loosening it (`workflow.worktree_mode`) is your call, made in your own terminal.

## Worker model tiers

`presets/crew-dispatch.json` (`shared_quota: true`, harness `pi`) tells Firstmate which model each kind of task gets:

| Work | Model |
| --- | --- |
| Mechanical edits (conflict resolution, version bump, typo, rename) | Sonnet 5.5, medium |
| Driving an existing pull request through no-mistakes, or other bookkeeping with no code | Haiku 5.5, medium |
| A clear bug fix in a few files that does not touch login, sessions, tokens, permissions or payments | Sonnet 5.5, medium |
| Multi-file or risky work, or any change to login, sessions, tokens, permissions, payments, data migrations or locking | Sonnet 5.5, high |
| Planning large or risky work, or a code review you asked for | Opus 5.5, xhigh |
| Scouts (read-only investigations), experiments, audits | Sonnet 5.5, high |
| Everything else (default) | Sonnet 5.5, medium |

## Working rules

- The primary session runs in Herdr. Workers open as Herdr panes and use Pi, or omp when you chose it.
- Herdr tests run only through `bin/fm-herdr-lab.sh` in an `fm-lab-*` session, never against your real Herdr session.
- Machine-specific settings live in `config/`, `data/` and `state/`. They are gitignored and never committed.

## Verification

- `ai-native/tests/new-project.test.sh` builds throwaway repos (node, python, go, rust, make C++, a monorepo, an empty repo) and checks detection and `--dry-run`. It also runs `setup.sh` in a sandbox HOME to check that an existing config is left alone.
  With stand-in `pi`, `herdr` and installers it checks the Herdr integration step, the removal of a user-level `pi-mcp-adapter`, and the note for a changed `config/crew-dispatch.json`.
- `setup.sh --check` on an empty sandbox lists what is missing and installs nothing. A second full run changes nothing, and a config with the kit marker or a hand-tuned config survives byte for byte.
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
So the kit installs none of the first three for your user.
Most of the remaining cost (about 12k tokens) is the skill list in `~/.agents/skills`; trimming it is up to you.
