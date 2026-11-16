#!/usr/bin/env bash
# Fast checks for ai-native/new-project.sh on throwaway repos. Detection and --dry-run only: nothing is
# installed and --verify is never run. A fixture is skipped when a tool it needs is missing.
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

d="$(repo py-uv 'pyproject.toml=[project]\nname="a"\ndependencies=["ruff>=0.5","pytest"]\n' 'uv.lock=\n')"
check "python uv sets the ruff lint command" "$d" 0 'lint: "uv run ruff check \."'
d="$(repo py-dev 'requirements.txt=x\n' 'pyproject.toml=[project.optional-dependencies]\ndev = ["pytest", "ruff"]\n')"
check "python one-line dev array sets the ruff lint command" "$d" 0 'lint: "\.venv/bin/ruff check \."'
d="$(repo py-req 'requirements.txt=ruff==0.5\npytest\n')"
check "python requirements" "$d" 0 '\.venv/bin/ruff'
d="$(repo py-none 'requirements.txt=flask\n')"
check "python without ruff or pytest says python was found" "$d" 1 'python found in .*no ruff or pytest'
d="$(repo py-toolruff 'pyproject.toml=[project]\nname="a"\ndependencies=["pytest"]\n[tool.ruff]\nline-length=100\n' 'uv.lock=\n')"
check "ruff table without the dependency sets no lint" "$d" 0 'ruff is configured but not listed as a dependency'
out="$("$NP" --dry-run "$d" 2>&1)"
if grep -q '^  lint: "' <<<"$out"; then bad "ruff table alone set a lint command"; else ok "no lint command from a ruff table alone"; fi

d="$(repo py-rufftoml 'requirements.txt=pytest\n' 'ruff.toml=# Ruff settings\nline-length=100\n')"
check "ruff.toml with a Ruff comment is not a dependency" "$d" 0 'ruff is configured but not listed as a dependency'
out="$("$NP" --dry-run "$d" 2>&1)"
if grep -q '^  lint: "' <<<"$out"; then bad "ruff.toml comment set a lint command"; else ok "no lint command from a ruff.toml comment"; fi

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
if grep -q 'path: "\*\*"' "$d/.no-mistakes.yaml" && grep -q 'Conventional Branch' "$d/.no-mistakes.yaml"; then ok "generated file has the review instruction"; else bad "no review path instruction in generated file"; fi
if "$NP" "$d" >/dev/null 2>&1; then bad "second write overwrote the file"; else ok "second write refuses"; fi

# setup.sh must reject an unknown argument before doing anything.
out="$("$HERE/setup.sh" --chek 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q usage <<<"$out" && ! grep -q 'versions' <<<"$out"; then ok "setup.sh rejects an unknown argument"; else bad "setup.sh --chek: exit $rc" "$out"; fi

# setup.sh must leave a hand-tuned config without the kit marker byte-identical.
sb="$(mktemp -d)"; mkdir -p "$sb/nm" "$sb/fm"
printf 'agent: claude\nmax_concurrent_runs: 2\n' >"$sb/nm/config.yaml"; cp "$sb/nm/config.yaml" "$sb/orig"
out="$(HOME="$sb" NM_HOME="$sb/nm" FM_HOME="$sb/fm" PATH="$PATH" "$HERE/setup.sh" --check 2>&1)"
if cmp -s "$sb/orig" "$sb/nm/config.yaml" && ! grep -q 'MISSING: no-mistakes global config' <<<"$out" && grep -q 'left alone' <<<"$out"; then ok "--check leaves a tuned config alone"; else bad "--check mishandled a tuned config" "$out"; fi
cp "$sb/orig" "$sb/nm/config.yaml"
printf '# no-mistakes global configuration\n\n# Agent to use.\nagent: auto\nci_timeout: 4h\nlog_level: info\n' >"$sb/nm/config.yaml"
out="$(HOME="$sb" NM_HOME="$sb/nm" FM_HOME="$sb/fm" PATH="$PATH" "$HERE/setup.sh" --check 2>&1)"
if grep -q 'MISSING: no-mistakes global config' <<<"$out"; then ok "--check flags the untouched installer default"; else bad "--check missed the installer default" "$out"; fi
rm -rf "$sb"

printf '%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" = 0 ]
