# Set up a home with an AI agent

After cloning Firstmate, open your agent in the clone and paste the prompt below.
Fill in the two choices first: setup seeds config from them and never overwrites a file that already has content.

| Backend | Worker harness |
| --- | --- |
| `t3code` | leave empty (workers run `claude`) |
| `herdr`, `tmux` or another backend | `claude`, `pi`, `pi-signed` or `omp` |

## Prompt

```text
Set up this Firstmate home.

Choices:
- Runtime backend: <t3code | herdr | tmux>
- Worker harness: <claude | pi | pi-signed | omp, or empty for t3code>

Steps:
1. Write the backend to config/backend. If a worker harness is given, write it to config/crew-harness; otherwise leave that file absent.
   Do this before running setup: setup seeds config/crew-dispatch.json from these files and never overwrites it later.
2. Run setup/setup.sh --check and show me what is missing.
3. Install what you can (setup/setup.sh installs the axi tools, Pi packages and config presets), then run setup/setup.sh again until it prints OK.
   Anything that needs my account, such as a login, token or sign-in, stays on the list for me. Do not work around it.
4. Write these project defaults to data/captain.md:
   - Register every new remote-backed project as no-mistakes with yolo off and the feature/ branch prefix ([no-mistakes branch=feature/]). Do not ask each time.
   - Adding a project is one turn: clone, register, no-mistakes init, no-mistakes doctor.
   - Never add no-mistakes config files to a project repo. Let the no-mistakes agents work out how to lint and test.
     After a project's first run reaches a PR, save what they ran under repository_overrides in ~/.no-mistakes/config.yaml, keyed by the project's origin URL, and tell me.
   - A project with no CI checks at all registers as direct-PR instead, with the reason.
   - Never merge without my explicit word.
5. Report: what setup changed, what is still missing, and the exact command I need to run for each login or token.
```

## What you may still need to do yourself

- `gh auth login`, so workers can push and open pull requests.
- On `t3code`: run the T3 Code server with telemetry off (`T3CODE_TELEMETRY_ENABLED=false t3 serve ...`) and sign in with `bin/fm-t3-mcp.mjs login --access full-access`. See [docs/t3code-backend.md](../docs/t3code-backend.md).
- A model login for each harness you use (Claude Code, Pi or omp).

## After setup

Add a project with one sentence:

```text
add project https://github.com/<owner>/<repo>
```

Then give it work in plain words, for example `<repo>: add a contact form`.
Firstmate sends a worker, no-mistakes reviews, tests and opens the PR, and you decide whether to merge.
