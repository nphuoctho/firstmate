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
NOT_USER_LEVEL=(npm:pi-lens npm:@juicesharp/rpiv-todo npm:pi-markdown-preview npm:pi-context-view git:github.com/nphuoctho/pi-usage-bars)
bad=0

say()  { printf '%s\n' "$*"; }
miss() { say "MISSING: $*"; bad=1; }
act()  { if [ "$CHECK" = 1 ]; then miss "$*"; else say "installing: $*"; return 0; fi; return 1; }

hint() {
  case "$1" in
    herdr) printf 'install it from https://herdr.dev' ;;
    pi) printf 'install it from https://pi.dev' ;;
    treehouse) printf 'install it with its vendor installer; Firstmate needs it for the herdr backend' ;;
    *) printf 'install it with your OS package manager' ;;
  esac
}
for t in git gh node npm jq curl treehouse herdr pi; do
  command -v "$t" >/dev/null 2>&1 || miss "$t ($(hint "$t"))"
done

for c in "${NPM_CLIS[@]}"; do
  command -v "$c" >/dev/null 2>&1 || {
    if act "$c"; then
      npm install -g "$c"
      # Same follow-up step as Firstmate's own install hint (bin/fm-bootstrap.sh).
      case "$c" in
        gh-axi | chrome-devtools-axi | lavish-axi) "$c" setup hooks || say "warning: $c setup hooks failed" ;;
      esac
    fi
  }
done

# user_entry <source>: prints the user-level `pi list` line for a package, with or without a pinned @version.
# Only the "User packages:" section counts, so a project-level package of the same name never matches.
user_entry() {
  awk -v s="$1" '/^User packages:/ { u = 1; next } /^[^ ]/ { u = 0 } u && /^  [^ ]/ { sub(/^ +/, ""); sub(/ \(filtered\)$/, ""); t = $0; sub(/@[^\/@]+$/, "", t); if (t == s || $0 == s) { print $0; exit } }' <<<"$installed"
}

if command -v pi >/dev/null 2>&1; then
  installed="$(pi list 2>/dev/null || true)"
  for p in "${PI_PACKAGES[@]}"; do
    [ -n "$(user_entry "$p")" ] || { if act "pi package $p"; then pi install "$p"; fi; }
  done
  for p in "${NOT_USER_LEVEL[@]}"; do
    e="$(user_entry "$p")"
    if [ -n "$e" ]; then
      if act "remove user-level $p (primary session only)"; then pi remove "$e"; fi
    fi
  done

  # Primary-session packages go into the Firstmate home's own .pi/settings.json, which workers never read.
  # A package counts as present when settings.json lists that exact pinned source.
  settings="$HOME_DIR/.pi/settings.json"
  have="$(jq -r '(.packages // [])[] | if type == "object" then .source else . end' "$settings" 2>/dev/null || true)"
  while IFS= read -r p; do
    grep -qxF "$p" <<<"$have" || { if act "primary-session pi package $p (in $settings)"; then (cd "$HOME_DIR" && pi install -l "$p"); fi; }
  done < <(jq -r '.packages[]' "$PRESETS/pi-primary-settings.json")
  # defaultTools: turn codemode on. Never mixed into a list that names plain tools, since pi rejects that mix.
  if jq -e '(.defaultTools // []) | index("+codemode")' "$settings" >/dev/null 2>&1; then :
  elif [ ! -s "$settings" ] || jq -e '(.defaultTools // []) | all(.[]; startswith("+") or startswith("-"))' "$settings" >/dev/null 2>&1; then
    if act "pi codemode (defaultTools +codemode in $settings)"; then
      mkdir -p "$HOME_DIR/.pi"
      [ -s "$settings" ] || printf '{}\n' >"$settings"
      jq '.defaultTools = ((.defaultTools // []) + ["+codemode"])' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
    fi
  else
    say "note: $settings defaultTools names plain tools, so +codemode is not added. Add it by hand."
  fi
else
  say "skipped: Pi package check (pi is not installed, so the packages cannot be listed)"
fi

# Herdr learns the agent's working, blocked and done state from its integration.
# The install needs the agent's extension folder, which only exists after pi first ran.
if command -v herdr >/dev/null 2>&1 && command -v pi >/dev/null 2>&1; then
  if hstatus="$(herdr integration status 2>/dev/null)" && [ -n "$hstatus" ]; then
    if ! grep -q "^pi: current" <<<"$hstatus"; then
      if act "herdr integration for pi"; then
        mkdir -p "$HOME/.pi/agent/extensions"
        herdr integration install pi || say "warning: herdr integration install pi failed"
      fi
    fi
  else
    say "skipped: Herdr integration check (herdr integration status failed; is the Herdr server running?)"
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
seed "$PRESETS/crew-dispatch.json" "$CFG/crew-dispatch.json" config/crew-dispatch.json
seed "$PRESETS/brief-include.md" "$CFG/brief-include.md" config/brief-include.md
seed "$PRESETS/supervision-branch-model" "$CFG/supervision-branch-model" config/supervision-branch-model
seed "$PRESETS/supervision-branch-effort" "$CFG/supervision-branch-effort" config/supervision-branch-effort
seed "$PRESETS/pi-lens.json" "$HOME_DIR/.pi-lens.json" .pi-lens.json
# Firstmate options that are switched on by the file existing.
for f in park-on-review auto-land pr-register-scan; do
  [ -e "$CFG/$f" ] || { if act "config/$f"; then mkdir -p "$CFG"; touch "$CFG/$f"; fi; }
done

# Keep the primary-only Pi files out of git. Needs the home to be the top of its own git repo.
if excl="$(git -C "$HOME_DIR" rev-parse --git-path info/exclude 2>/dev/null)" &&
  [ "$(git -C "$HOME_DIR" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$HOME_DIR" && pwd -P)" ]; then
  case "$excl" in /*) ;; *) excl="$HOME_DIR/$excl" ;; esac
  for pat in .pi/settings.json .pi/npm/ .pi/git/ .pi-lens.json; do
    grep -qxF "$pat" "$excl" 2>/dev/null || {
      if act "git exclude entry $pat"; then mkdir -p "$(dirname "$excl")"; printf '%s\n' "$pat" >>"$excl"; fi
    }
  done
fi

say "--- versions"
for t in pi herdr tasks-axi gh-axi quota-axi lavish-axi chrome-devtools-axi; do
  command -v "$t" >/dev/null 2>&1 && printf '%s: %s\n' "$t" "$("$t" --version 2>&1 | head -1)"
done
if [ "$bad" = 0 ]; then say "OK"; else say "INCOMPLETE"; exit 1; fi
