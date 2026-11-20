# Standard setup

One command sets up a machine and a Firstmate home the same way every time.

```sh
setup/setup.sh --check   # report what is missing, change nothing; exits 1 if anything is missing
setup/setup.sh           # install and seed what is missing
```

Any other argument prints the usage and does nothing.
To have an AI agent do the whole setup, paste the prompt in [run.md](run.md).
Run it whenever you set up a new machine or a new Firstmate home.
It is safe to run again, because it only fills gaps.
A step that fails is reported as missing and the rest of the setup still runs, so the run ends with `INCOMPLETE` and exit code 1.
`FM_HOME` points it at a different Firstmate home (the default is this repo).

Install these first.
The script reports any that are missing:
`git`, `gh`, `node`, `npm`, `jq`, `curl` and `treehouse` (install with `curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh`).

The setup picks no runtime backend.
It reads the home's backend (`FM_BACKEND`, else the first line of `config/backend`) and worker harness (see "Worker model choice") and asks only for what they need:

- `herdr` (https://herdr.dev) when the backend is `herdr`;
- `pi` (https://pi.dev) when workers run on `pi` or `pi-signed`.

A runtime tool the backend does not need is only noted when missing.
Without `pi` or `jq`, the Pi package and settings steps are skipped with a message.
`node` and `npm` are needed only because the axi command-line tools (small programs the agent runs to reach GitHub, a browser, quota, review boards and the backlog; listed below) and the Pi packages install through them.
The setup assumes no project language or stack, and the presets name none.

## What the standard contains

### Command-line tools

| Tool | Use |
| --- | --- |
| `gh-axi` | GitHub |
| `chrome-devtools-axi` | browser work |
| `quota-axi` | model quota |
| `lavish-axi` | visual review boards |
| `tasks-axi` | the backlog |

They are installed with `npm install -g`.
`setup hooks` is run for `gh-axi`, `chrome-devtools-axi` and `lavish-axi`.
The script also installs the Herdr integration for `pi`, so Herdr shows whether the agent is working, blocked or done.

### Pi packages

These are installed for your user, so they load in every Pi session (the primary, workers and the no-mistakes agents):

| Package | Use |
| --- | --- |
| `cc-safety-net` | blocks destructive commands and reads of secret files |
| `pi-web-access` | web search and page fetch |
| `git:github.com/DietrichGebert/ponytail` | Ponytail, the small-change coding style |

Codemode (a Pi feature that lets the agent run a short script which calls several tools in one go) is also on for every session.
Setup adds `"+codemode"` to `defaultTools` in your user-level Pi settings (`~/.pi/agent/settings.json`) and keeps every other key.

These are installed for the primary Firstmate session only.
They are written to this home's `.pi/settings.json` with `pi install -l`, which workers never read because they run in their own copies of each repo:

| Package | Use |
| --- | --- |
| `pi-markdown-preview` | Markdown previews |
| `pi-context-view@0.8.4` | `/context` |
| `@juicesharp/rpiv-todo@2.15.0` | a todo list tool |
| `nphuoctho/pi-usage-bars` (pinned commit) | `/usage` |

The same file also lists Ponytail with its extensions and skills switched off.
That keeps Ponytail on for workers and no-mistakes, which use the user-level copy, and off in the primary session.
The four packages above cost tokens or memory in every session they load in.
So the script removes a user-level copy if it finds one, and never installs them at user level.
`pi-lens` is dropped entirely: the script removes any user-level copy and any copy in the home's `.pi/settings.json`, and leaves an old `.pi-lens.json` alone.
`.pi/settings.json`, `.pi/npm/` and `.pi/git/` are added to the home's `.git/info/exclude`, so they are never committed.

### Firstmate config

Files are copied from `presets/` into the home's `config/` only when the file is missing or empty.
A file with content is never overwritten.
When it differs from the preset, setup prints a `diff` command so you can compare.

| File | What it does |
| --- | --- |
| `crew-dispatch.json` | picks the model for each worker (see below) |
| `brief-include.md` | git rules and a check-before-done step added to every worker's instructions |
| `supervision-branch-model`, `supervision-branch-effort` | Haiku 5.5 at `medium` for Firstmate's background supervision; read only when the primary session runs on Pi |
| `park-on-review`, `auto-land`, `pr-register-scan` | empty files; each one switches that Firstmate option on |

### Git rules

`brief-include.md` tells every worker to follow these rules.
On a `no-mistakes` project it tells the worker to leave the checks to the pipeline, so they do not run twice.
On a `direct-PR` or `local-only` project it tells the worker to run whatever checks the project itself defines before reporting done.
The git rules are:
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) for commit messages;
- [Conventional Branch 1.1.0](https://conventionalbranch.org/) for branch names (Firstmate picks the name);
- pull request titles in the Conventional Commits form, without body or footers, written in plain English.

Firstmate's default ship branch prefix is `fm/`, which is not a Conventional Branch type, so register each project with `branch=feature/` (the annotation `bin/fm-project-mode.sh --branch-prefix` reads) for branch names to conform.

The include summarizes these rules, so workers do not fetch the linked pages.

### Worker model choice

All workers run Claude models on shared quota.
The preset holds the rules; the worker harness is the home's choice, so setup seeds the rules on the harness this home uses:

| The home has | Harness in the seeded file | Model names |
| --- | --- | --- |
| `config/crew-harness` set to `pi`, `pi-signed` or `omp` | that harness | `anthropic/claude-...` |
| `config/crew-harness` set to `claude` | `claude` | `claude-...` |
| no `config/crew-harness` (or `default`) and backend `t3code` | `claude` (T3 Code runs only Claude and Codex workers) | `claude-...` |
| neither | `pi` | `anthropic/claude-...` |

Any other `config/crew-harness` (for example `codex`) cannot run the preset's Claude models, so setup seeds nothing and says so; write `config/crew-dispatch.json` by hand.
Set `config/crew-harness` before the first setup run: an existing `crew-dispatch.json` is never overwritten.

Firstmate asks six questions in order and stops at the first yes.
When torn between two answers it picks the more careful one.

| Question | Model |
| --- | --- |
| 1. Is the job to review work someone just finished? | Opus 5.5, high |
| 2. Is the job to find something out, with a report as the result? | Sonnet 5.5, high |
| 3. Is it unclear how to do it, with a plan for another worker as the result? | Opus 5.5, high |
| 4. Would a mistake be hard to notice, hard to undo, or cause real harm? | Sonnet 5.5, high |
| 5. Does it follow a known pattern and need almost no judgment? | Haiku 5.5, medium |
| 6. Everything else | Sonnet 5.5, medium |

## Adding projects

Register each project with `[no-mistakes branch=feature/]` (or another mode) and run `no-mistakes init` and `no-mistakes doctor` in its clone.
No per-project no-mistakes configuration is needed: its agents work out how to lint and test the project, and nothing is added to the project repo.

## Changing the standard

- Setup re-creates a preset or option file that is missing or empty, so a file you deleted on purpose comes back on the next run. Examples: deleting `config/supervision-branch-model` ("Follow main" in `/supervision-model`) or deleting `config/park-on-review` or `config/auto-land` (which switches that option off). To keep such a choice, make it again after each setup run, for example pick "Follow main" again in `/supervision-model` or delete the option file again.
- Change a preset in `presets/` to change the standard for new setups.
  Homes that already have the file keep theirs, so edit their `config/` file too.
- Package versions live in `presets/pi-primary-settings.json`.
  After changing one, run `setup/setup.sh`: Pi replaces the old version of the same package.
- A user-level `defaultTools` that is empty or names plain tools (not `+name` entries) is not changed.
  Setup prints a note, and you add `+codemode` yourself.

## Checks

Before changing setup, run these two checks (nothing runs them automatically):

```sh
bash setup/tests/setup.test.sh
bin/fm-lint.sh setup/setup.sh setup/tests/setup.test.sh
```

`setup/tests/setup.test.sh` needs no network and installs nothing.
It checks that the presets are valid JSON, that the dispatch preset passes Firstmate's own validation (also as seeded for T3 Code, omp and a harness it does not fit), and that the brief builder emits `brief-include.md`.
It also checks that `--check` and a real run behave as described, including with `npm` or `jq` missing.
It uses a scratch home with stand-in `pi`, `herdr` and installers.

`--check` installs nothing and changes no settings.
It can still create cache files, for example `pi list` creates `~/.pi/agent/`.
A real run in a sandbox needs `HOME`, `NPM_CONFIG_PREFIX` and `FM_HOME` set to scratch folders and a limited `PATH`.
That is because `npm install -g` and `pi install` write under the real npm prefix and `~/.pi`.
