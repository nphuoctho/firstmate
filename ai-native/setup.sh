#!/usr/bin/env bash
# AI Native base bootstrap: Pi Agent + Firstmate + Herdr + no-mistakes.
# Idempotent. Usage: ai-native/setup.sh [--check | -h | --help]
#   --check  only report what is missing and change nothing; exits 1 when something is missing.
# FM_HOME and NM_HOME relocate the Firstmate config and the no-mistakes home (default: this repo, ~/.no-mistakes).
# A real sandbox run also needs HOME, NPM_CONFIG_PREFIX and a limited PATH (see ai-native/README.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { printf 'usage: ai-native/setup.sh [--check]\n  (no argument)  install what is missing\n  --check        report what is missing, change nothing, exit 1 if anything is missing\n'; }
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
# NOT_USER_LEVEL packages cost per-request tokens or memory in every one of those processes (todo ~1.7k tokens,
# mcp ~1.1k, preview_export ~0.8k, pi-lens 0.6-1.2 GB) or break composer reads (pi-open-tui).
# setup.sh removes any user-level copy.
PI_PACKAGES=(pi-web-access cc-safety-net)
NOT_USER_LEVEL=(pi-open-tui pi-lens @juicesharp/rpiv-todo pi-mcp-adapter pi-markdown-preview)
NM_HOME_DIR="${NM_HOME:-$HOME/.no-mistakes}"
# First line of the kit's global config. A config carrying it is the kit's and is never touched.
KIT_MARKER='# ai-native-kit-config'
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

# no-mistakes global config. Installed when absent. Replaced (after a timestamped .bak copy) only when the
# installer wrote it in this run. Any other existing config, with or without the kit marker, is never touched.
nm_cfg_sum() { { cksum <"$NM_HOME_DIR/config.yaml"; } 2>/dev/null || true; }
install_nm_config() {
  local f="$NM_HOME_DIR/config.yaml" fresh="${1:-}"
  if [ ! -s "$f" ]; then
    if act "no-mistakes global config"; then
      mkdir -p "$NM_HOME_DIR"
      cp "$ROOT/ai-native/no-mistakes/global-config.yaml" "$f"
    fi
  elif [ -n "$fresh" ]; then
    cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
    cp "$ROOT/ai-native/no-mistakes/global-config.yaml" "$f"
    say "replaced the installer's default config; old copy saved as config.yaml.bak.<time>."
    say "note: restart the no-mistakes daemon to apply it (no-mistakes daemon restart) when no runs are active."
  elif ! grep -qxF "$KIT_MARKER" "$f"; then
    say "note: $f is not the kit config and is left alone. To adopt the kit config: cp '$f' '$f.bak' && cp '$ROOT/ai-native/no-mistakes/global-config.yaml' '$f'"
  fi
}

# Before the installer, so its first daemon start already reads the kit config.
install_nm_config

if ! command -v no-mistakes >/dev/null 2>&1; then
  before="$(nm_cfg_sum)"
  if ! command -v curl >/dev/null 2>&1; then
    say "skipped: no-mistakes install (curl is not installed)"
  elif act "no-mistakes"; then
    curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
  fi
  # The installer may have written its own default config.
  if [ "$CHECK" != 1 ] && [ "$(nm_cfg_sum)" != "$before" ]; then install_nm_config fresh; fi
fi

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

if command -v pi >/dev/null 2>&1; then
  installed="$(pi list 2>/dev/null || true)"
  for p in "${PI_PACKAGES[@]}"; do
    grep -q "npm:$p\$" <<<"$installed" || { if act "pi package $p"; then pi install "npm:$p"; fi; }
  done
  for p in "${NOT_USER_LEVEL[@]}"; do
    if grep -q "npm:$p\$" <<<"$installed"; then
      if act "remove user-level $p (not for every session)"; then pi remove "npm:$p"; fi
    fi
  done
else
  say "skipped: Pi package check (pi is not installed, so the packages cannot be listed)"
fi

# Herdr learns each agent's working, blocked and done state from its integration for that agent.
# The install needs the agent's extension folder, which only exists after the agent first ran.
if command -v herdr >/dev/null 2>&1; then
  if hstatus="$(herdr integration status 2>/dev/null)" && [ -n "$hstatus" ]; then
  for a in pi omp; do
    command -v "$a" >/dev/null 2>&1 || continue
    grep -q "^$a: current" <<<"$hstatus" && continue
    if act "herdr integration for $a"; then
      mkdir -p "$HOME/.$a/agent/extensions"
      herdr integration install "$a" || say "warning: herdr integration install $a failed"
    fi
  done
  else
    say "skipped: Herdr integration check (herdr integration status failed; is the Herdr server running?)"
  fi
fi

# Firstmate local (gitignored) config: Pi workers on the Herdr backend, plus the dispatch preset.
# Each file is written only when absent or empty, never overwritten.
CFG="${FM_HOME:-$ROOT}/config"
[ "$CHECK" = 1 ] || mkdir -p "$CFG"
for kv in "backend:herdr" "crew-harness:pi"; do
  f="$CFG/${kv%%:*}"
  [ -s "$f" ] || { if act "config/${kv%%:*}=${kv##*:}"; then printf '%s\n' "${kv##*:}" >"$f"; fi; }
done
PRESET="$ROOT/ai-native/presets/crew-dispatch.json"
if [ ! -s "$CFG/crew-dispatch.json" ]; then
  if act "config/crew-dispatch.json (preset)"; then cp "$PRESET" "$CFG/crew-dispatch.json"; fi
elif ! cmp -s "$CFG/crew-dispatch.json" "$PRESET"; then
  say "note: config/crew-dispatch.json differs from the preset and is left alone. Compare: diff '$CFG/crew-dispatch.json' '$PRESET'"
fi

say "--- versions"
for t in pi herdr no-mistakes tasks-axi gh-axi quota-axi lavish-axi chrome-devtools-axi; do
  command -v "$t" >/dev/null 2>&1 && printf '%s: %s\n' "$t" "$("$t" --version 2>&1 | head -1)"
done
command -v no-mistakes >/dev/null 2>&1 && no-mistakes doctor 2>&1 | grep -E "✓|✗" | head -20 || true
if [ "$bad" = 0 ]; then say "OK"; else say "INCOMPLETE"; exit 1; fi
