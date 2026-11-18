#!/usr/bin/env bash
# Fast checks for ai-native/new-project.sh on throwaway repos (detection and --dry-run, never --verify),
# plus setup.sh argument and config-preservation checks in a sandbox HOME. A fixture is skipped when a
# tool it needs is missing.
# Usage: ai-native/tests/new-project.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NP="$HERE/new-project.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
pass=0 fail=0 skip=0

ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/        | /'; }
skipped() { skip=$((skip + 1)); printf '  skip  %s (%s)\n' "$1" "$2"; }

# yget <repo> <python expr over d>: parses the proposed .no-mistakes.yaml (--dry-run) and prints the value.
yget() {
  "$NP" --dry-run "$1" 2>/dev/null | awk '/^---$/ { n++; next } n == 1' |
    python3 -c 'import sys, yaml; d = yaml.safe_load(sys.stdin); print(eval(sys.argv[1]))' "$2"
}
# ycheck <label> <repo> <python expr> <want>
ycheck() { local got; got="$(yget "$2" "$3" 2>&1)"; if [ "$got" = "$4" ]; then ok "$1"; else bad "$1: got '$got', wanted '$4'"; fi; }
HAVE_YAML=0; python3 -c 'import yaml' 2>/dev/null && HAVE_YAML=1

# repo <name> [file...]: a git repo whose files are given as path=content pairs, committed.
repo() {
  local d="$TMP/$1" kv
  shift
  mkdir -p "$d"
  git -C "$d" init -q
  for kv in "$@"; do
    mkdir -p "$d/$(dirname "${kv%%=*}")"
    printf '%b' "${kv#*=}" >"$d/${kv%%=*}"
  done
  git -C "$d" add -A
  git -C "$d" commit -q --allow-empty -m fixture
  printf '%s' "$d"
}

# check <label> <repo> <want-exit> <grep-pattern> [args...]: runs --dry-run, expects the exit code and a match in stdout+stderr.
check() {
  local label=$1 d=$2 want=$3 pat=$4 out rc
  shift 4
  out="$("$NP" --dry-run "$@" "$d" 2>&1)"; rc=$?
  if [ "$rc" != "$want" ]; then bad "$label: exit $rc, wanted $want" "$out"
  elif ! grep -qE -- "$pat" <<<"$out"; then bad "$label: no match for /$pat/" "$out"
  else ok "$label"; fi
}

echo "new-project.sh fixtures"

if command -v jq >/dev/null 2>&1; then
  d="$(repo node-npm 'package.json={"scripts":{"lint":"x","test":"y"}}' 'package-lock.json={}')"
  check "node npm" "$d" 0 'node \(npm, from package-lock.json\)'
  check "node npm uses npm ci" "$d" 0 'prepare: "npm ci"'
  check "node npm uses the lint script" "$d" 0 'lint: "npm run lint"'
  check "node,node names one stack once" "$d" 0 'named twice' node,node
  out="$("$NP" --dry-run node,node "$d" 2>&1)"
  if grep -q 'npm ci && npm ci' <<<"$out"; then bad "node,node repeats the command"; else ok "node,node writes the command once"; fi
  d="$(repo mono 'web/package.json={"scripts":{"test":"y"}}' 'web/package-lock.json={}' 'svc/go.mod=module x\n')"
  check "monorepo has node and go" "$d" 0 "cd 'svc'.*cd 'web'"
else
  skipped "node and monorepo fixtures" "jq not installed"
fi

if [ "$HAVE_YAML" = 1 ]; then
d="$(repo py-uv 'pyproject.toml=[project]\nname="a"\ndependencies=["ruff>=0.5","pytest"]\n' 'uv.lock=\n')"
ycheck "python uv sets the ruff lint command" "$d" 'd["commands"]["lint"]' 'uv run ruff check .'
d="$(repo py-dev 'pyproject.toml=[project.optional-dependencies]\ndev = ["pytest", "ruff"]\n')"
ycheck "pip installs the dev extra, so its one-line ruff counts" "$d" 'd["commands"]["lint"]' '.venv/bin/ruff check .'
d="$(repo py-extra-uv 'pyproject.toml=[project]\nname="a"\ndependencies=["pytest"]\n[project.optional-dependencies]\ndev = ["ruff"]\n' 'uv.lock=\n')"
ycheck "uv sync skips extras, so ruff there sets no lint" "$d" 'd["commands"].get("lint")' 'None'
d="$(repo py-extra-req 'requirements.txt=pytest\n' 'pyproject.toml=[project.optional-dependencies]\ndev = ["ruff"]\n')"
ycheck "requirements.txt prepare skips the pyproject extra, so no lint" "$d" 'd["commands"].get("lint")' 'None'
d="$(repo py-req 'requirements.txt=ruff==0.5\npytest\n')"
ycheck "python requirements sets the venv ruff command" "$d" 'd["commands"]["lint"]' '.venv/bin/ruff check .'
d="$(repo py-toolruff 'pyproject.toml=[project]\nname="a"\ndependencies=["pytest"]\n[tool.ruff]\nline-length=100\n' 'uv.lock=\n')"
ycheck "ruff table alone sets no lint" "$d" 'd["commands"].get("lint")' 'None'
d="$(repo py-rufftoml 'requirements.txt=pytest\n' 'ruff.toml=# Ruff settings\nline-length=100\n')"
ycheck "ruff.toml with a Ruff comment sets no lint" "$d" 'd["commands"].get("lint")' 'None'
else
  skipped "python command fixtures" "python3 yaml module not installed"
fi
if [ "$HAVE_YAML" = 1 ]; then
d="$(repo py-pip-groups 'pyproject.toml=[project]\nname="a"\ndescription="wraps ruff"\n[dependency-groups]\ndev = ["ruff", "pytest"]\n')"
check "pip does not install dependency-groups, so no command is set" "$d" 1 'python found in .*no ruff or pytest'
d="$(repo py-uv-groups 'pyproject.toml=[project]\nname="a"\n[dependency-groups]\ndev = [\n  "ruff",\n  "pytest",\n]\n' 'uv.lock=\n')"
ycheck "uv installs the dev group, so ruff counts" "$d" 'd["commands"]["lint"]' 'uv run ruff check .'
d="$(repo py-poetry 'pyproject.toml=[tool.poetry.group.dev.dependencies]\nruff = "^0.5"\npytest = "^8"\n' 'poetry.lock=\n')"
ycheck "poetry dev group counts" "$d" 'd["commands"]["lint"]' 'poetry run ruff check .'
d="$(repo py-poetry-legacy 'pyproject.toml=[tool.poetry]\nname="a"\n[tool.poetry.dev-dependencies]\nruff = "^0.5"\npytest = "^7"\n' 'poetry.lock=\n')"
ycheck "poetry legacy dev-dependencies count" "$d" 'd["commands"]["lint"]' 'poetry run ruff check .'
d="$(repo py-poetry2 'pyproject.toml=[project]\nname="a"\ndependencies=["pytest"]\n[tool.poetry.group.dev.dependencies]\nruff = "^0.5"\n' 'poetry.lock=\n')"
ycheck "poetry 2 project dependencies count" "$d" 'd["commands"]["test"]' 'poetry run pytest -q'
d="$(repo py-pytest-cfg 'pyproject.toml=[project]\nname="a"\ndependencies=["ruff"]\n[project.optional-dependencies]\ntest = ["pytest"]\n[tool.pytest.ini_options]\naddopts="-q"\n' 'uv.lock=\n')"
ycheck "pytest config and an extra do not set a test command" "$d" 'd["commands"].get("test")' 'None'
fi
d="$(repo py-none 'requirements.txt=flask\n')"
check "python without ruff or pytest says python was found" "$d" 1 'python found in .*no ruff or pytest'
d="$(repo py-toolruff2 'pyproject.toml=[project]\nname="a"\ndependencies=["pytest"]\n[tool.ruff]\nline-length=100\n' 'uv.lock=\n')"
check "ruff table without the dependency says so" "$d" 0 'ruff is configured but not listed as a dependency'
if "$NP" --dry-run "$d" 2>&1 | grep -q 'ruff is not configured'; then bad "contradictory ruff notes"; else ok "ruff notes do not contradict"; fi

d="$(repo go 'go.mod=module x\n')"
check "go" "$d" 0 'go vet'
d="$(repo rust 'Cargo.toml=[package]\nname="a"\n' 'Cargo.lock=\n')"
check "rust" "$d" 0 'cargo fetch --locked'
d="$(repo cpp 'Makefile=test:\n\ttrue\n' 'a.cxx=int main(){}\n')"
check "make with a committed .cxx file" "$d" 0 'cpp \(make\)'
d="$(repo cpp-uncommitted 'Makefile=test:\n\ttrue\n')"
printf 'int main(){}\n' >"$d/a.cc"
check "make with only an uncommitted C++ file says committed" "$d" 1 'no committed C or C\+\+ files'
d="$(repo empty)"
check "empty repo" "$d" 1 'found no known stack'

# Real write: file mode, pointer to the rules, no overwrite.
d="$(repo write 'go.mod=module x\n')"
out="$("$NP" "$d" 2>&1)"
mode="$(stat -c %a "$d/.no-mistakes.yaml" 2>/dev/null || stat -f %Lp "$d/.no-mistakes.yaml")"
if [ "$mode" = 644 ]; then ok "written file has mode 644"; else bad "written file mode is $mode"; fi
if grep -q 'Conventional Commits' <<<"$out" && grep -q 'Conventional Branch' <<<"$out" && grep -q -- '--branch-prefix' <<<"$out"; then ok "write prints the git rules inline"; else bad "git rules not printed" "$out"; fi
if grep -q 'git-conventions.md' <<<"$out"; then bad "output points into the kit checkout"; else ok "output has no kit path"; fi
if [ "$HAVE_YAML" = 1 ]; then
  got="$(python3 -c 'import sys, yaml; p = yaml.safe_load(open(sys.argv[1]))["review"]["path_instructions"][0]; print(p["path"], "Conventional Commits" in p["instructions"], "Conventional Branch" in p["instructions"])' "$d/.no-mistakes.yaml" 2>&1)"
  if [ "$got" = '** True True' ]; then ok "generated file has the review path instruction"; else bad "review path instruction wrong: $got"; fi
fi
if "$NP" "$d" >/dev/null 2>&1; then bad "second write overwrote the file"; else ok "second write refuses"; fi

# setup.sh must reject an unknown argument before doing anything.
out="$("$HERE/setup.sh" --chek 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q usage <<<"$out" && ! grep -q 'versions' <<<"$out"; then ok "setup.sh rejects an unknown argument"; else bad "setup.sh --chek: exit $rc" "$out"; fi

# setup.sh must leave a hand-tuned config without the kit marker byte-identical.
sb="$(mktemp -d)"; mkdir -p "$sb/nm" "$sb/fm"
printf '# no-mistakes global configuration\n\n# Agent to use for code generation.\nagent: auto\n\nci_timeout: 1h\nlog_level: info\n' >"$sb/nm/config.yaml"; cp "$sb/nm/config.yaml" "$sb/orig"
out="$(HOME="$sb" NM_HOME="$sb/nm" FM_HOME="$sb/fm" PATH="$PATH" "$HERE/setup.sh" --check 2>&1)"
if cmp -s "$sb/orig" "$sb/nm/config.yaml" && ! ls "$sb/nm"/config.yaml.bak* >/dev/null 2>&1 && ! grep -q 'MISSING: no-mistakes global config' <<<"$out" && grep -q 'left alone' <<<"$out"; then ok "--check leaves a tuned config alone"; else bad "--check mishandled a tuned config" "$out"; fi
printf '# ai-native-kit-config\nagent: pi\n' >"$sb/nm/config.yaml"; cp "$sb/nm/config.yaml" "$sb/orig"
out="$(HOME="$sb" NM_HOME="$sb/nm" FM_HOME="$sb/fm" PATH="$PATH" "$HERE/setup.sh" --check 2>&1)"
if cmp -s "$sb/orig" "$sb/nm/config.yaml" && ! grep -q 'left alone' <<<"$out"; then ok "a kit config is untouched and not flagged"; else bad "kit config mishandled" "$out"; fi
rm -rf "$sb"

# Stubbed pi, herdr and installers, so setup.sh can do a real run without touching the machine.
# HERDR_STATUS and PI_LIST set what the stubs report; every other call is logged to $sb/log.
sb="$(mktemp -d)"; mkdir -p "$sb/nm" "$sb/fm/config" "$sb/bin"
printf '# ai-native-kit-config\nagent: pi\n' >"$sb/nm/config.yaml"
for t in gh-axi chrome-devtools-axi lavish-axi quota-axi tasks-axi no-mistakes omp; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/log"\n' "$t" "$sb" >"$sb/bin/$t"
done
cat >"$sb/bin/herdr" <<EOF
#!/bin/sh
case "\$1 \$2" in "integration status") [ -z "\$HERDR_FAIL" ] || exit 1; printf '%b' "\$HERDR_STATUS" ;; *) echo "herdr \$*" >>"$sb/log" ;; esac
EOF
cat >"$sb/bin/pi" <<EOF
#!/bin/sh
case "\$1" in list) printf '%b' "\$PI_LIST" ;; *) echo "pi \$*" >>"$sb/log" ;; esac
EOF
chmod +x "$sb/bin"/*
base_list='  npm:pi-web-access\n  npm:cc-safety-net\n'
run_setup() { HOME="$sb" NM_HOME="$sb/nm" FM_HOME="$sb/fm" PATH="$sb/bin:$PATH" HERDR_STATUS="$1" PI_LIST="$2" "$HERE/setup.sh" ${3:+"$3"} 2>&1; }

out="$(run_setup 'pi: not installed (x)\nomp: outdated (v9 < v10) (x)\n' "$base_list" --check)"
if grep -q 'MISSING: herdr integration for pi' <<<"$out" && grep -q 'MISSING: herdr integration for omp' <<<"$out" && ! grep -q 'integration install' "$sb/log" 2>/dev/null; then ok "--check reports a missing or outdated herdr integration"; else bad "herdr integration not reported" "$out"; fi
out="$(run_setup 'pi: current (v9) (x)\nomp: current (v10) (x)\n' "$base_list" --check)"
if ! grep -q 'herdr integration' <<<"$out"; then ok "a current herdr integration is not flagged"; else bad "current herdr integration flagged" "$out"; fi
out="$(run_setup 'pi: not installed (x)\nomp: current (v10) (x)\n' "$base_list")"
if grep -qx 'herdr integration install pi' "$sb/log" && ! grep -q 'install omp' "$sb/log" && [ -d "$sb/.pi/agent/extensions" ]; then ok "a real run installs the missing herdr integration"; else bad "herdr integration not installed" "$out"; fi

: >"$sb/log"
out="$(HERDR_FAIL=1 run_setup '' "$base_list")"
if grep -q 'skipped: Herdr integration check' <<<"$out" && ! grep -q 'MISSING: herdr' <<<"$out" && ! grep -q 'herdr integration install' "$sb/log"; then ok "a failing herdr integration status skips the check"; else bad "failed herdr status mishandled" "$out"; fi

out="$(run_setup 'pi: current (v9) (x)\nomp: current (v10) (x)\n' "$base_list  npm:pi-mcp-adapter\n" --check)"
if grep -q 'remove user-level pi-mcp-adapter' <<<"$out"; then ok "--check flags a user-level pi-mcp-adapter"; else bad "pi-mcp-adapter not flagged" "$out"; fi

printf '{}\n' >"$sb/fm/config/crew-dispatch.json"
out="$(run_setup 'pi: current (v9) (x)\nomp: current (v10) (x)\n' "$base_list" --check)"
if grep -q 'crew-dispatch.json differs from the preset' <<<"$out" && [ "$(cat "$sb/fm/config/crew-dispatch.json")" = '{}' ]; then ok "a changed dispatch config gets a note and is kept"; else bad "dispatch drift mishandled" "$out"; fi
cp "$HERE/presets/crew-dispatch.json" "$sb/fm/config/crew-dispatch.json"
out="$(run_setup 'pi: current (v9) (x)\nomp: current (v10) (x)\n' "$base_list" --check)"
if ! grep -q 'differs from the preset' <<<"$out"; then ok "a dispatch config equal to the preset gets no note"; else bad "preset copy flagged" "$out"; fi
rm -rf "$sb"

printf '%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" = 0 ]
