#!/usr/bin/env bash
# AI Native base bootstrap: Pi Agent + Firstmate + Herdr + no-mistakes.
# Idempotent. Usage: ai-native/setup.sh [--check]   (--check only reports, changes nothing)
# FM_HOME and NM_HOME relocate the Firstmate config and the no-mistakes home (default: this repo, ~/.no-mistakes).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

NPM_CLIS=(gh-axi chrome-devtools-axi lavish-axi quota-axi tasks-axi)
# User-level packages load in every Pi process, workers included, so only the cheap ones live here.
# PRIMARY_ONLY packages cost per-request tokens or memory in every worker (todo ~1.7k tokens, mcp ~1.1k,
# preview_export ~0.8k, pi-lens 0.6-1.2 GB) or break composer reads (pi-open-tui): ai-native/pi-primary.sh
# loads them with -e for the primary session, and setup.sh removes any user-level copy.
PI_PACKAGES=(pi-web-access cc-safety-net)
PRIMARY_ONLY=(pi-open-tui pi-lens @juicesharp/rpiv-todo pi-mcp-adapter pi-markdown-preview)
NM_HOME_DIR="${NM_HOME:-$HOME/.no-mistakes}"
bad=0

say()  { printf '%s\n' "$*"; }
miss() { say "MISSING: $*"; bad=1; }
act()  { if [ "$CHECK" = 1 ]; then miss "$*"; else say "installing: $*"; return 0; fi; return 1; }

for t in git gh node npm jq tmux herdr pi; do
  command -v "$t" >/dev/null 2>&1 || miss "$t (install it with your OS package manager or its vendor installer; herdr: https://herdr.dev, pi: https://pi.dev)"
done

command -v no-mistakes >/dev/null 2>&1 || {
  if act "no-mistakes"; then curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh; fi
}

for c in "${NPM_CLIS[@]}"; do
  command -v "$c" >/dev/null 2>&1 || { if act "$c"; then npm install -g "$c"; fi; }
done

if command -v pi >/dev/null 2>&1; then
  installed="$(pi list 2>/dev/null || true)"
  for p in "${PI_PACKAGES[@]}"; do
    grep -q "npm:$p\$" <<<"$installed" || { if act "pi package $p"; then pi install "npm:$p"; fi; }
  done
  for p in "${PRIMARY_ONLY[@]}"; do
    if grep -q "npm:$p\$" <<<"$installed"; then
      if act "remove user-level $p (primary-only)"; then pi remove "npm:$p"; fi
    fi
  done
fi

# no-mistakes global config: install only when the machine has none, never overwrite a tuned one.
if [ ! -s "$NM_HOME_DIR/config.yaml" ]; then
  if act "no-mistakes global config"; then
    mkdir -p "$NM_HOME_DIR"
    cp "$ROOT/ai-native/no-mistakes/global-config.yaml" "$NM_HOME_DIR/config.yaml"
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
[ -s "$CFG/crew-dispatch.json" ] || { if act "config/crew-dispatch.json (preset)"; then cp "$ROOT/ai-native/presets/crew-dispatch.json" "$CFG/crew-dispatch.json"; fi; }

say "--- versions"
for t in pi herdr no-mistakes tasks-axi gh-axi quota-axi lavish-axi chrome-devtools-axi; do
  command -v "$t" >/dev/null 2>&1 && printf '%s: %s\n' "$t" "$("$t" --version 2>&1 | head -1)"
done
command -v no-mistakes >/dev/null 2>&1 && no-mistakes doctor 2>&1 | grep -E "✓|✗" | head -20
if [ "$bad" = 0 ]; then say "OK"; else say "INCOMPLETE"; exit 1; fi
