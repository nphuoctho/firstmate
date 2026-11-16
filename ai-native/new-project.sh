#!/usr/bin/env bash
# Write a .no-mistakes.yaml for a repo, built from what the repo actually contains.
#
# Usage:
#   ai-native/new-project.sh [--dry-run] [--verify] <repo-dir>                 detect the stacks
#   ai-native/new-project.sh [--dry-run] [--verify] <stacks> <repo-dir>        use the stacks you name
#
# <stacks> is a comma list of names from ai-native/no-mistakes/stacks/, each optionally followed by
# :<subdir>, for example "node" or "node:web,go:api". Named stacks take the verified commands as they
# are, with no adaptation to the repo.
#
# Detection looks for marker files in the repo root and one directory level down:
#   package.json              node    (pnpm, yarn, bun or npm, from packageManager or the lockfile)
#   pyproject.toml,
#   requirements.txt          python  (uv, poetry or pip)
#   go.mod                    go
#   Cargo.toml                rust
#   Makefile + C/C++ files    cpp
# It emits a command only when its tool or script exists. A stack found in the root also covers any
# same-stack folder below it. Anything it had to guess is listed at the end.
#
# --dry-run  print the detection and the proposed file; write nothing.
# --verify   clone the repo with `git clone --local` into a temp directory and run the generated
#            prepare, lint and test commands there. Each is reported as ran, FAILED or skipped.
#            Only committed files are cloned. Exit status is 1 if any step failed.
#
# The command sets come from ai-native/no-mistakes/stacks/*.yaml. Never overwrites an existing
# .no-mistakes.yaml.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS="$HERE/no-mistakes/stacks"
BASE="$HERE/no-mistakes/project.no-mistakes.yaml"
MARK='# @@STACK@@'

list() { for f in "$STACKS"/*.yaml; do basename "$f" .yaml; done | tr '\n' ' '; }
die() { printf 'new-project.sh: %s\n' "$*" >&2; exit 1; }

DRY=0
VERIFY=0
args=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --verify) VERIFY=1 ;;
    -h | --help) sed -n '2,/^set -e/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option '$a'" ;;
    *) args+=("$a") ;;
  esac
done

case "${#args[@]}" in
  1) mode=auto; repo="${args[0]}"; named="" ;;
  2) mode=named; named="${args[0]}"; repo="${args[1]}" ;;
  *) die "usage: new-project.sh [--dry-run] [--verify] [<stacks>] <repo-dir>   (stacks: $(list))" ;;
esac
[ -d "$repo" ] || die "not a directory: $repo"
repo="$(cd "$repo" && pwd)"
out="$repo/.no-mistakes.yaml"
if [ -e "$out" ]; then
  if [ "$DRY" = 1 ]; then printf 'note: %s already exists; a real run would refuse to overwrite it.\n' "$out"; else die "$out already exists; not overwriting"; fi
fi
grep -qxF "$MARK" "$BASE" || die "marker line missing in $BASE"

# ---- stack snippets: the single source of truth for commands and ignore patterns

snip_cmd() { sed -n "s/^  $2: \"\\(.*\\)\"\$/\\1/p" "$STACKS/$1.yaml" | head -n 1; }
snip_ignores() { sed -n 's/^  - "\(.*\)"$/\1/p' "$STACKS/$1.yaml"; }

# ---- collected results

E_STACK=() E_DIR=() E_PREP=() E_LINT=() E_TEST=() E_FMT=() E_LABEL=()
NOTES=()
note() { NOTES+=("$*"); }

add_entry() { # stack dir label prepare lint test format
  E_STACK+=("$1"); E_DIR+=("$2"); E_LABEL+=("$3")
  E_PREP+=("$4"); E_LINT+=("$5"); E_TEST+=("$6"); E_FMT+=("$7")
}
where() { if [ "$1" = . ]; then printf 'the repo root'; else printf '%s/' "$1"; fi; }
path_of() { if [ "$1" = . ]; then printf '%s' "$repo"; else printf '%s/%s' "$repo" "$1"; fi; }

# ---- per-stack detection. Each takes a directory relative to the repo ("." or "name").

detect_node() {
  local dir=$1 d pkg pm label how run lock prep lint test fmt tc s
  d="$(path_of "$dir")"; pkg="$d/package.json"
  command -v jq >/dev/null 2>&1 || die "jq is needed to read package.json"
  jq -e . "$pkg" >/dev/null 2>&1 || { note "$(where "$dir"): package.json is not valid JSON; node skipped"; return; }
  pm=""; how=""
  s="$(jq -r '.packageManager // ""' "$pkg")"; s="${s%%@*}"
  case "$s" in npm | pnpm | yarn | bun) pm="$s"; how="packageManager field" ;; esac
  if [ -z "$pm" ]; then
    if [ -e "$d/pnpm-lock.yaml" ]; then pm=pnpm; how="pnpm-lock.yaml"
    elif [ -e "$d/yarn.lock" ]; then pm=yarn; how="yarn.lock"
    elif [ -e "$d/bun.lock" ] || [ -e "$d/bun.lockb" ]; then pm=bun; how="bun lockfile"
    elif [ -e "$d/package-lock.json" ]; then pm=npm; how="package-lock.json"
    else pm=npm; how="no lockfile"; note "$(where "$dir"): no lockfile or packageManager field, so npm is a guess and prepare uses 'npm install'."
    fi
  fi
  run="$pm run "
  lock=0
  case "$pm" in
    npm) [ -e "$d/package-lock.json" ] || [ -e "$d/npm-shrinkwrap.json" ] && lock=1 ;;
    pnpm) [ -e "$d/pnpm-lock.yaml" ] && lock=1 ;;
    bun) { [ -e "$d/bun.lock" ] || [ -e "$d/bun.lockb" ]; } && lock=1 ;;
    yarn) [ -e "$d/yarn.lock" ] && lock=1 ;;
  esac
  if [ "$lock" = 0 ] && [ "$how" != "no lockfile" ]; then note "$(where "$dir"): no $pm lockfile, so prepare uses '$pm install'."; fi
  case "$pm" in
    npm) if [ "$lock" = 1 ]; then prep="$(snip_cmd node prepare)"; else prep="npm install"; fi ;;
    pnpm) if [ "$lock" = 1 ]; then prep="pnpm install --frozen-lockfile"; else prep="pnpm install"; fi ;;
    bun) if [ "$lock" = 1 ]; then prep="bun install --frozen-lockfile"; else prep="bun install"; fi ;;
    yarn) if [ "$lock" = 0 ]; then prep="yarn install"
      elif [ -e "$d/.yarnrc.yml" ]; then prep="yarn install --immutable"; else prep="yarn install --frozen-lockfile"; fi ;;
  esac
  has_script() { jq -e --arg n "$1" '(.scripts[$n] // "") | type == "string" and . != ""' "$pkg" >/dev/null 2>&1; }
  lint=""
  if has_script lint; then lint="${run}lint"; fi
  tc=""
  for s in typecheck type-check check-types; do if has_script "$s"; then tc="$s"; break; fi; done
  if [ -n "$tc" ]; then lint="${lint:+$lint && }${run}$tc"; fi
  test=""
  if has_script test && ! jq -e '.scripts.test | test("no test specified")' "$pkg" >/dev/null 2>&1; then test="${run}test"; fi
  fmt=""
  if has_script format; then fmt="${run}format"
  elif jq -e '[.dependencies, .devDependencies] | map(. // {}) | add | has("prettier")' "$pkg" >/dev/null 2>&1; then fmt="$(snip_cmd node format)"
  fi
  [ -n "$lint" ] || note "$(where "$dir"): package.json has no lint or typecheck script, so no lint command is set."
  [ -n "$test" ] || note "$(where "$dir"): package.json has no real test script, so no test command is set."
  label="node ($pm, from $how)"
  add_entry node "$dir" "$label" "$prep" "$lint" "$test" "$fmt"
}

detect_python() {
  local dir=$1 d py req pm how runner prep lint test fmt files f
  d="$(path_of "$dir")"; py="$d/pyproject.toml"; req="$d/requirements.txt"
  files=()
  for f in "$py" "$req" "$d/tox.ini" "$d/setup.cfg" "$d/pytest.ini" "$d/ruff.toml" "$d/.ruff.toml"; do [ -e "$f" ] && files+=("$f"); done
  if [ -e "$d/uv.lock" ]; then pm=uv; how="uv.lock"
  elif [ -e "$d/poetry.lock" ] || { [ -e "$py" ] && grep -q '^\[tool\.poetry' "$py"; }; then pm=poetry; how="poetry"
  else pm=pip; how="no lock file"
  fi
  case "$pm" in
    uv) runner="uv run "; prep="$(snip_cmd python prepare)" ;;
    poetry) runner="poetry run "; prep="poetry install --no-interaction" ;;
    pip)
      runner=".venv/bin/"
      if [ -e "$req" ]; then prep="python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
      else prep="python3 -m venv .venv && .venv/bin/pip install -e ."; fi
      note "$(where "$dir"): no uv.lock or poetry.lock, so pip in a .venv is a guess."
      ;;
  esac
  lint=""; test=""; fmt=""
  if [ -e "$d/ruff.toml" ] || [ -e "$d/.ruff.toml" ] || { [ -e "$py" ] && grep -qi 'ruff' "$py"; } || { [ -e "$req" ] && grep -qi 'ruff' "$req"; }; then
    lint="$(snip_cmd python lint)"; lint="${lint/#uv run /$runner}"
    fmt="$(snip_cmd python format)"; fmt="${fmt/#uv run /$runner}"
  fi
  if [ "${#files[@]}" -gt 0 ] && grep -qsi 'pytest' "${files[@]}"; then
    test="$(snip_cmd python test)"; test="${test/#uv run /$runner}"
  fi
  [ -n "$lint" ] || note "$(where "$dir"): ruff is not configured, so no lint command is set."
  [ -n "$test" ] || note "$(where "$dir"): pytest is not configured, so no test command is set."
  if [ -z "$lint$test" ]; then
    return 0
  fi
  add_entry python "$dir" "python ($pm, from $how)" "$prep" "$lint" "$test" "$fmt"
}

detect_go() {
  local dir=$1
  add_entry go "$dir" "go" "$(snip_cmd go prepare)" "$(snip_cmd go lint)" "$(snip_cmd go test)" "$(snip_cmd go format)"
}

detect_rust() {
  local dir=$1 d prep
  d="$(path_of "$dir")"; prep="$(snip_cmd rust prepare)"
  if [ ! -e "$d/Cargo.lock" ]; then prep="cargo fetch"; note "$(where "$dir"): no Cargo.lock, so prepare uses 'cargo fetch' instead of '--locked'."; fi
  add_entry rust "$dir" "rust" "$prep" "$(snip_cmd rust lint)" "$(snip_cmd rust test)" "$(snip_cmd rust format)"
}

detect_cpp() {
  local dir=$1 d test lint
  d="$(path_of "$dir")"
  if [ -z "$(git -C "$d" ls-files -- '*.c' '*.cc' '*.cpp' '*.h' '*.hpp' 2>/dev/null | head -n 1)" ]; then
    note "$(where "$dir"): Makefile has no tracked C or C++ files under it, so it is not treated as a C/C++ project."
    return
  fi
  test=""
  if grep -Eqs '^test[[:space:]]*:' "$d/Makefile"; then test="$(snip_cmd cpp test)"
  else note "$(where "$dir"): Makefile has no 'test' target, so no test command is set."; fi
  lint="$(snip_cmd cpp lint)"
  if [ ! -e "$d/.clang-tidy" ] && [ ! -e "$repo/.clang-tidy" ]; then
    lint="${lint%% && *}" # keep only the clang-format part: clang-tidy stops with "no checks enabled" without a config
    note "$(where "$dir"): no .clang-tidy file, so lint runs clang-format only."
  fi
  add_entry cpp "$dir" "cpp (make)" "" "$lint" "$test" "$(snip_cmd cpp format)"
}

# ---- build the entry list

SKIP_DIRS=" node_modules vendor dist build target third_party venv "

if [ "$mode" = auto ]; then
  dirs=(.)
  for p in "$repo"/*/; do
    [ -d "$p" ] || continue
    n="$(basename "$p")"
    case "$SKIP_DIRS" in *" $n "*) continue ;; esac
    case "$n" in *[!A-Za-z0-9._-]*) note "folder '$n' has characters outside A-Za-z0-9._- ; not scanned."; continue ;; esac
    dirs+=("$n")
  done
  found=" "
  for dir in "${dirs[@]}"; do
    d="$(path_of "$dir")"
    for stack in node python go rust cpp; do
      case "$stack" in
        node) [ -e "$d/package.json" ] || continue ;;
        python) [ -e "$d/pyproject.toml" ] || [ -e "$d/requirements.txt" ] || continue ;;
        go) [ -e "$d/go.mod" ] || continue ;;
        rust) [ -e "$d/Cargo.toml" ] || continue ;;
        cpp) [ -e "$d/Makefile" ] || continue ;;
      esac
      if [ "$dir" != . ] && case "$found" in *" $stack:. "*) true ;; *) false ;; esac; then
        note "$dir/ has a $stack marker, but the root already has one; the root commands are assumed to cover it."
        continue
      fi
      before=${#E_STACK[@]}
      case "$stack" in node) detect_node "$dir" ;; python) detect_python "$dir" ;; go) detect_go "$dir" ;; rust) detect_rust "$dir" ;; cpp) detect_cpp "$dir" ;; esac
      [ "${#E_STACK[@]}" -gt "$before" ] && found="$found$stack:$dir "
    done
  done
  if [ "${#E_STACK[@]}" -eq 0 ]; then for n in "${NOTES[@]}"; do printf '  - %s\n' "$n" >&2; done; fi
  [ "${#E_STACK[@]}" -gt 0 ] || die "found no known stack in $repo (markers: package.json, pyproject.toml, requirements.txt, go.mod, Cargo.toml, Makefile with C/C++ files). Name one: $(list)"
else
  IFS=',' read -r -a items <<<"$named"
  for item in "${items[@]}"; do
    stack="${item%%:*}"; dir="."
    case "$item" in *:*) dir="${item#*:}" ;; esac
    case "$stack" in *[!a-z0-9_-]* | "") die "invalid stack name '$stack' (stacks: $(list))" ;; esac
    [ -f "$STACKS/$stack.yaml" ] || die "unknown stack '$stack' (stacks: $(list))"
    while [ "${#dir}" -gt 1 ] && [ "${dir%/}" != "$dir" ]; do dir="${dir%/}"; done
    case "$dir" in *[!A-Za-z0-9._/-]* | "" | /* | .. | ../* | */../* | */.. | ./* | */./* | */. | *//*) die "invalid folder '$dir'" ;; esac
    [ -d "$repo/$dir" ] || die "no folder '$dir' in $repo"
    add_entry "$stack" "$dir" "$stack (named)" "$(snip_cmd "$stack" prepare)" "$(snip_cmd "$stack" lint)" "$(snip_cmd "$stack" test)" "$(snip_cmd "$stack" format)"
  done
  note "stacks were named, so their commands are the stock ones and were not checked against the repo."
fi

# ---- compose the yaml block

join_cmd() { # which: PREP LINT TEST FMT
  local i c res=""
  for i in "${!E_STACK[@]}"; do
    case "$1" in PREP) c="${E_PREP[$i]}" ;; LINT) c="${E_LINT[$i]}" ;; TEST) c="${E_TEST[$i]}" ;; FMT) c="${E_FMT[$i]}" ;; esac
    [ -n "$c" ] || continue
    if [ "${E_DIR[$i]}" != . ]; then c="(cd '${E_DIR[$i]}' && $c)"; fi
    res="${res:+$res && }$c"
  done
  printf '%s' "$res"
}
yaml_q() { local s=${1//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; }

PREP="$(join_cmd PREP)"; LINT="$(join_cmd LINT)"; TEST="$(join_cmd TEST)"; FMT="$(join_cmd FMT)"

block="$(
  printf '# Written by ai-native/new-project.sh (%s). Detected:' "$mode"
  for i in "${!E_STACK[@]}"; do printf ' %s in %s;' "${E_LABEL[$i]}" "${E_DIR[$i]}"; done
  printf '\n# A command left out here is not run by the gate. Check each one below.\ncommands:\n'
  [ -z "$PREP" ] || printf '  prepare: %s\n' "$(yaml_q "$PREP")"
  [ -z "$LINT" ] || printf '  lint: %s\n' "$(yaml_q "$LINT")"
  [ -z "$TEST" ] || printf '  test: %s\n' "$(yaml_q "$TEST")"
  [ -z "$FMT" ] || printf '  format: %s\n' "$(yaml_q "$FMT")"
  printf 'ignore_patterns:\n'
  seen=$'\n'
  for i in "${!E_STACK[@]}"; do
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      case "$pat" in */*) [ "${E_DIR[$i]}" = . ] || pat="${E_DIR[$i]}/$pat" ;; esac
      case "$seen" in *$'\n'"$pat"$'\n'*) continue ;; esac
      seen="$seen$pat"$'\n'
      printf '  - %s\n' "$(yaml_q "$pat")"
    done < <(snip_ignores "${E_STACK[$i]}")
  done
)"

compose() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$MARK" ]; then printf '%s\n' "$block"; else printf '%s\n' "$line"; fi
  done <"$BASE"
}

# ---- report

printf 'detected:\n'
for i in "${!E_STACK[@]}"; do printf '  %s in %s\n' "${E_LABEL[$i]}" "$(where "${E_DIR[$i]}")"; done

if [ "$DRY" = 1 ]; then
  printf '\nproposed %s:\n---\n' "$out"
  compose
  printf '%s\n' '---'
else
  tmp="$(mktemp "$repo/.no-mistakes.yaml.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  compose >"$tmp"
  # ln fails if the target appeared meanwhile, so a racing file is never replaced.
  ln "$tmp" "$out" 2>/dev/null || die "$out appeared meanwhile; not overwriting"
  printf 'wrote %s. Commit it on the default branch, then run: no-mistakes init\n' "$out"
fi

if [ "${#NOTES[@]}" -gt 0 ]; then
  printf '\nguessed or skipped, please check:\n'
  for n in "${NOTES[@]}"; do printf '  - %s\n' "$n"; done
fi

# ---- verify

[ "$VERIFY" = 1 ] || exit 0
printf '\nverify (git clone --local, then run each command in the clone):\n'
work="$(mktemp -d)"
trap 'rm -rf "$work"; [ -z "${tmp:-}" ] || rm -f "$tmp"' EXIT
git clone --local -q "$repo" "$work/clone" 2>"$work/clone.log" || { cat "$work/clone.log" >&2; die "git clone --local failed (does the repo have a commit?)"; }
failed=0 prep_ok=1
for step in prepare lint test; do
  case "$step" in prepare) c="$PREP" ;; lint) c="$LINT" ;; test) c="$TEST" ;; esac
  if [ -z "$c" ]; then printf '  %-8s skipped: no command is set\n' "$step"; continue; fi
  if [ "$step" != prepare ] && [ "$prep_ok" = 0 ]; then printf '  %-8s skipped: prepare failed\n' "$step"; continue; fi
  set +e
  if command -v timeout >/dev/null 2>&1; then (cd "$work/clone" && timeout 900 sh -c "$c") >"$work/$step.log" 2>&1; else (cd "$work/clone" && sh -c "$c") >"$work/$step.log" 2>&1; fi
  rc=$?
  set -e
  if [ "$rc" = 0 ]; then printf '  %-8s ran, passed\n' "$step"
  else
    printf '  %-8s FAILED (exit %s)\n' "$step" "$rc"
    tail -n 5 "$work/$step.log" | sed 's/^/             | /'
    failed=1
    [ "$step" != prepare ] || prep_ok=0
  fi
done
exit "$failed"
