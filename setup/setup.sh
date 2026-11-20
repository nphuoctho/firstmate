#!/usr/bin/env bash
# Standard setup for a Firstmate home: axi CLIs, Pi packages, Firstmate config presets.
# Idempotent. Usage: setup/setup.sh [--check | -h | --help]
#   --check  only report what is missing and change nothing; exits 1 when something is missing.
# FM_HOME relocates the Firstmate home (default: this repo). Sandbox runs also need HOME and NPM_CONFIG_PREFIX
# set to scratch folders and a limited PATH (see setup/README.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESETS="$ROOT/setup/presets"
HOME_DIR="${FM_HOME:-$ROOT}"
CFG="$HOME_DIR/config"
usage() { printf 'usage: setup/setup.sh [--check]\n  (no argument)  install what is missing\n  --check        report what is missing, change nothing, exit 1 if anything is missing\n'; }
CHECK=0
case "${1:-}" in
  "") ;;
  --check) CHECK=1 ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }

NPM_CLIS=(gh-axi chrome-devtools-axi lavish-axi quota-axi tasks-axi)
# User-level packages load in every Pi process (primary, workers, no-mistakes gate agents), so only the cheap ones live here.
PI_PACKAGES=(npm:pi-web-access npm:cc-safety-net git:github.com/DietrichGebert/ponytail)
# Primary-only packages (presets/pi-primary-settings.json) cost tokens or memory in every session they load in,
# so they are installed for the Firstmate home only. setup.sh removes any user-level copy.
# pi-lens is the exception: it is dropped from the primary preset too, so a user-level or home-level copy is removed.
NOT_USER_LEVEL=(npm:pi-lens npm:@juicesharp/rpiv-todo npm:pi-markdown-preview npm:pi-context-view git:github.com/nphuoctho/pi-usage-bars)
bad=0

say()  { printf '%s\n' "$*"; }
miss() { say "MISSING: $*"; bad=1; }
act()  { if [ "$CHECK" = 1 ]; then miss "$*"; else say "installing: $*"; return 0; fi; return 1; }

hint() {
  case "$1" in
    herdr) printf 'install it from https://herdr.dev' ;;
    pi) printf 'install it from https://pi.dev' ;;
    treehouse) printf 'install it with: curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh' ;;
    *) printf 'install it with your OS package manager' ;;
  esac
}
BACKEND="${FM_BACKEND:-$(head -n1 "$CFG/backend" 2>/dev/null || true)}"
# The preset holds the rules (which Claude model and effort for which job); the worker harness is the home's choice:
# a concrete config/crew-harness first, then claude on t3code (T3 Code runs only claude/codex workers), else the preset's pi.
WORKER="$(head -n1 "$CFG/crew-harness" 2>/dev/null || true)"
[ "$WORKER" != default ] || WORKER=""
[ -n "$WORKER" ] || { [ "$BACKEND" != t3code ] || WORKER=claude; }
WORKER="${WORKER:-pi}"
# Runtime tools follow the home: herdr only for the herdr backend, pi only for pi/pi-signed workers.
# Other missing runtime tools are noted, not failed.
needed() {
  case "$1" in
    herdr) [ "$BACKEND" = herdr ] ;;
    pi) [ "$WORKER" = pi ] || [ "$WORKER" = pi-signed ] ;;
    *) return 0 ;;
  esac
}
for t in git gh node npm jq curl treehouse herdr pi; do
  command -v "$t" >/dev/null 2>&1 && continue
  if needed "$t"; then miss "$t ($(hint "$t"))"
  else say "note: $t is not installed; this home does not need it (backend '${BACKEND:-default}', workers '$WORKER'; $(hint "$t"))"; fi
done

# write_through <tmp> <dest>: write through dest's path so a symlinked settings file keeps its link, then drop tmp.
write_through() { cat "$1" >"$2" && rm -f "$1"; }

# run_or_miss <what> <command...>: a failing command is reported as missing, and the run goes on.
run_or_miss() { local what="$1"; shift; "$@" || miss "$what (command failed: $*)"; }

for c in "${NPM_CLIS[@]}"; do
  command -v "$c" >/dev/null 2>&1 || {
    if act "$c"; then
      if npm install -g "$c"; then
        # Same follow-up step as Firstmate's own install hint (bin/fm-bootstrap.sh).
        case "$c" in
          gh-axi | chrome-devtools-axi | lavish-axi) "$c" setup hooks || miss "$c (setup hooks failed)" ;;
        esac
      else
        miss "$c (npm install -g failed)"
      fi
    fi
  }
done

# user_entry <source>: prints the user-level `pi list` line for a package, with or without a pinned @version.
# Only the "User packages:" section counts, so a project-level package of the same name never matches.
user_entry() {
  awk -v s="$1" '/^User packages:/ { u = 1; next } /^[^ ]/ { u = 0 } u && /^  [^ ]/ { sub(/^ +/, ""); sub(/ \(filtered\)$/, ""); t = $0; sub(/@[^\/@]+$/, "", t); if (t == s) { print $0; exit } }' <<<"$installed"
}

# -a trusts this home's project files for the one command, so it also works without a terminal.
install_local() { (cd "$HOME_DIR" && pi install -l -a "$1"); }

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
if command -v pi >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  # FORCE_COLOR=0 keeps Pi from colouring the headers this parse depends on.
  installed="$(FORCE_COLOR=0 pi list 2>/dev/null || true)"
  for p in "${PI_PACKAGES[@]}"; do
    [ -n "$(user_entry "$p")" ] || { if act "pi package $p"; then run_or_miss "pi package $p" pi install "$p"; fi; }
  done
  for p in "${NOT_USER_LEVEL[@]}"; do
    e="$(user_entry "$p")"
    if [ -n "$e" ]; then
      if act "remove user-level $p (primary session only)"; then run_or_miss "remove user-level $p" pi remove "$e"; fi
    fi
  done

  # Codemode is on for every session (primary and workers), so it lives in the user-level settings.
  # Never mixed into a list that names plain tools or is empty, since pi rejects that mix and [] means no tools.
  us="$PI_AGENT_DIR/settings.json"
  if jq -e '(.defaultTools // []) | (index("+codemode") or index("codemode"))' "$us" >/dev/null 2>&1; then :
  elif [ ! -s "$us" ] || jq -e 'has("defaultTools") | not' "$us" >/dev/null 2>&1 ||
    jq -e '.defaultTools | length > 0 and all(.[]; startswith("+") or startswith("-"))' "$us" >/dev/null 2>&1; then
    if act "pi codemode (defaultTools +codemode in $us)"; then
      mkdir -p "$PI_AGENT_DIR"
      [ -s "$us" ] || printf '{}\n' >"$us"
      if jq '.defaultTools = ((.defaultTools // []) + ["+codemode"])' "$us" >"$us.tmp"; then
        write_through "$us.tmp" "$us" || miss "pi codemode (could not update $us)"
      else
        rm -f "$us.tmp"; miss "pi codemode (could not update $us)"
      fi
    fi
  else
    say "note: $us defaultTools is empty or names plain tools, so +codemode is not added. Add it by hand."
  fi

  # Primary-session packages go into the Firstmate home's own .pi/settings.json, which workers never read.
  # A plain entry counts as present when settings.json lists that exact pinned source.
  # An object entry (a package with filters) counts as present when settings.json has an object for that source.
  settings="$HOME_DIR/.pi/settings.json"
  have="$(jq -r '(.packages // [])[] | if type == "object" then .source else . end' "$settings" 2>/dev/null || true)"
  while IFS= read -r entry; do
    if [ "$(jq -r 'type' <<<"$entry")" = string ]; then
      p="$(jq -r '.' <<<"$entry")"
      grep -qxF "$p" <<<"$have" || { if act "primary-session pi package $p (in $settings)"; then run_or_miss "primary-session pi package $p" install_local "$p"; fi; }
    else
      p="$(jq -r '.source' <<<"$entry")"
      jq -e --arg p "$p" '(.packages // []) | any(.[]; type == "object" and .source == $p)' "$settings" >/dev/null 2>&1 || {
        if act "primary-session pi package $p with filters (in $settings)"; then
          mkdir -p "$HOME_DIR/.pi"
          [ -s "$settings" ] || printf '{}\n' >"$settings"
          if jq --argjson e "$entry" --arg p "$p" '.packages = [(.packages // [])[] | select((if type == "object" then .source else . end) != $p)] + [$e]' "$settings" >"$settings.tmp"; then
            write_through "$settings.tmp" "$settings" || miss "primary-session pi package $p (could not update $settings)"
          else
            rm -f "$settings.tmp"; miss "primary-session pi package $p (could not update $settings)"
          fi
        fi
      }
    fi
  done < <(jq -c '.packages[]' "$PRESETS/pi-primary-settings.json")
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if act "remove home-level $p (pi-lens is no longer used, in $settings)"; then
      # shellcheck disable=SC2016 # the inner bash, not this shell, expands $1 and $2.
      run_or_miss "remove home-level $p" bash -c 'cd "$1" && pi remove -l -a "$2"' _ "$HOME_DIR" "$p"
    fi
  done < <(grep -E '^npm:pi-lens(@.*)?$' <<<"$have" || true)
else
  say "skipped: Pi package check (needs both pi and jq installed, so the packages cannot be listed)"
fi

# Herdr learns the agent's working, blocked and done state from its integration.
# The install needs the agent's extension folder, which only exists after pi first ran.
if command -v herdr >/dev/null 2>&1 && command -v pi >/dev/null 2>&1; then
  if hstatus="$(herdr integration status 2>/dev/null)" && [ -n "$hstatus" ]; then
    if ! grep -q "^pi: current" <<<"$hstatus"; then
      if act "herdr integration for pi"; then
        mkdir -p "$PI_AGENT_DIR/extensions"
        herdr integration install pi || miss "herdr integration for pi (install failed)"
      fi
    fi
  else
    say "skipped: Herdr integration check (herdr integration status failed)"
  fi
fi

# seed <preset> <dest> <label>: copy when dest is absent or empty; otherwise only note a difference, never overwrite.
seed() {
  if [ ! -s "$2" ]; then
    if act "$3 (preset)"; then mkdir -p "$(dirname "$2")"; cp "$1" "$2"; fi
  elif ! cmp -s "$2" "$1"; then
    say "note: $3 differs from the preset and is left alone. Compare: diff '$2' '$1'"
  fi
}
dispatch="$PRESETS/crew-dispatch.json"
case "$WORKER" in
  pi) ;;
  pi-signed | omp | claude) # pi-signed and omp take the preset's provider/id names; claude takes bare names
    dispatch="$(mktemp)"; trap 'rm -f "$dispatch"' EXIT
    # Without jq, or if it fails, seed nothing rather than the pi preset or an empty file.
    command -v jq >/dev/null 2>&1 &&
      jq --arg h "$WORKER" '(.. | objects | select(has("harness"))) |= (.harness = $h | if $h == "claude" then .model |= sub("^anthropic/"; "") else . end)' \
        "$PRESETS/crew-dispatch.json" >"$dispatch" || dispatch="" ;;
  *) dispatch="" ;; # the preset's Claude models do not fit this harness
esac
if [ -n "$dispatch" ]; then
  seed "$dispatch" "$CFG/crew-dispatch.json" config/crew-dispatch.json
elif [ ! -s "$CFG/crew-dispatch.json" ]; then
  case "$WORKER" in
    pi-signed | omp | claude) miss "config/crew-dispatch.json (needs jq to adapt the preset to the '$WORKER' harness)" ;;
    *) say "note: config/crew-dispatch.json not seeded: its rules use Claude models and the worker harness is '$WORKER'. Write it by hand (docs/configuration.md \"Crew dispatch profiles\")." ;;
  esac
fi
seed "$PRESETS/brief-include.md" "$CFG/brief-include.md" config/brief-include.md
seed "$PRESETS/supervision-branch-model" "$CFG/supervision-branch-model" config/supervision-branch-model
seed "$PRESETS/supervision-branch-effort" "$CFG/supervision-branch-effort" config/supervision-branch-effort
# Firstmate options that are switched on by the file existing.
for f in park-on-review auto-land pr-register-scan; do
  [ -e "$CFG/$f" ] || { if act "config/$f"; then mkdir -p "$CFG"; touch "$CFG/$f"; fi; }
done

# Keep the primary-only Pi files out of git. Needs the home to be the top of its own git repo.
if excl="$(git -C "$HOME_DIR" rev-parse --git-path info/exclude 2>/dev/null)" &&
  [ "$(git -C "$HOME_DIR" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$HOME_DIR" && pwd -P)" ]; then
  case "$excl" in /*) ;; *) excl="$HOME_DIR/$excl" ;; esac
  for pat in .pi/settings.json .pi/npm/ .pi/git/; do
    grep -qxF "$pat" "$excl" 2>/dev/null || {
      if act "git exclude entry $pat"; then mkdir -p "$(dirname "$excl")"; [ ! -s "$excl" ] || [ -z "$(tail -c1 "$excl")" ] || echo >>"$excl"; printf '%s\n' "$pat" >>"$excl"; fi
    }
  done
fi

if [ "$bad" = 0 ]; then say "OK"; else say "INCOMPLETE"; exit 1; fi
