#!/usr/bin/env bash
# Checks for setup/setup.sh and its presets. No network and no toolchain installs: every tool is a stub
# in a sandbox HOME/FM_HOME. Needs jq and git. Usage: setup/tests/setup.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$HERE/presets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
pass=0 fail=0

ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/        | /'; }

for t in jq git; do command -v "$t" >/dev/null 2>&1 || { echo "missing $t"; exit 1; }; done

# Presets.
for f in "$P"/*.json; do if jq -e . "$f" >/dev/null 2>&1; then ok "preset $(basename "$f") is valid JSON"; else bad "preset $(basename "$f") is not valid JSON"; fi; done
if jq -e '(.packages | length) == 6 and (.packages | index("npm:pi-markdown-preview")) != null and (.packages | index("npm:pi-lens@4.5.1")) != null and (.packages | index("npm:pi-context-view@0.8.4")) != null and (.packages | index("npm:@juicesharp/rpiv-todo@2.15.0")) != null and (.packages | index("git:github.com/nphuoctho/pi-usage-bars@e595440")) != null' "$P/pi-primary-settings.json" >/dev/null &&
  jq -e '(has("defaultTools") | not) and (.packages[5] == {source: "git:github.com/DietrichGebert/ponytail", autoload: false, extensions: ["!**"], skills: ["!**"]})' "$P/pi-primary-settings.json" >/dev/null &&
  jq -e '.format.enabled == false and .autofix.enabled == false' "$P/pi-lens.json" >/dev/null; then ok "primary-session presets pin the packages, turn Ponytail off and pi-lens formatting off"; else bad "primary-session presets are wrong"; fi
if jq -e '.shared_quota == true and (.rules | length) == 6 and .default.model == "anthropic/claude-sonnet-5-5" and .default.effort == "medium" and ([.rules[].use.harness] | unique) == ["pi"]' "$P/crew-dispatch.json" >/dev/null; then ok "dispatch preset has six questions and the Sonnet medium default"; else bad "dispatch preset shape is wrong"; fi
if [ "$(cat "$P/supervision-branch-model")" = anthropic/claude-haiku-5-5 ] && [ "$(cat "$P/supervision-branch-effort")" = medium ]; then ok "supervision presets have the standard content"; else bad "supervision preset wrong"; fi

# The presets must not hard-code a tech stack.
if ! grep -qiE '\b(node|npm|npx|tsc|typescript|javascript|golang|go vet|python|ruff|pytest|rust|cargo|clippy|pnpm|yarn)\b' "$P/brief-include.md"; then ok "brief-include preset names no tech stack"; else bad "brief-include preset names a tech stack" "$(grep -niE 'node|npm|tsc|go vet|ruff|cargo|clippy' "$P/brief-include.md")"; fi

# The brief-include preset must reach workers: Firstmate's own brief builder has to emit it.
bh="$TMP/bhome"; mkdir -p "$bh/config"; cp "$P/brief-include.md" "$bh/config/"
if FM_HOME="$bh" "$HERE/../bin/fm-brief.sh" inc some-proj --scout >/dev/null 2>&1 &&
  b="$bh/data/inc/brief.md" && grep -q '^# Home brief additions$' "$b" &&
  sed -n '/^# Home brief additions$/,$p' "$b" | grep -q 'flank.github.io/flank/pr_titles'; then ok "the brief builder emits the brief-include preset"; else bad "brief builder did not emit the brief-include preset"; fi

# The dispatch preset must pass Firstmate's own crew-dispatch validation (bootstrap prints CREW_DISPATCH: for a bad file).
vh="$TMP/vhome"; mkdir -p "$vh/config"
cp "$P/crew-dispatch.json" "$vh/config/"
out="$(cd "$HERE/.." && FM_HOME="$vh" FM_BOOTSTRAP_DETECT_ONLY=1 timeout 120 bin/fm-bootstrap.sh 2>&1)"
if ! grep -q 'CREW_DISPATCH:' <<<"$out"; then ok "dispatch preset passes Firstmate's crew-dispatch validation"; else bad "dispatch preset rejected" "$(grep CREW_DISPATCH <<<"$out")"; fi
jq '.rules[0].use.harness = "not-a-harness"' "$P/crew-dispatch.json" >"$vh/config/crew-dispatch.json"
out="$(cd "$HERE/.." && FM_HOME="$vh" FM_BOOTSTRAP_DETECT_ONLY=1 timeout 120 bin/fm-bootstrap.sh 2>&1)"
if grep -q 'CREW_DISPATCH:' <<<"$out"; then ok "the validation can fail (negative control)"; else bad "validation did not reject a bad harness"; fi

# setup.sh rejects an unknown argument before doing anything.
out="$("$HERE/setup.sh" --chek 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q usage <<<"$out" && ! grep -q 'versions' <<<"$out"; then ok "setup.sh rejects an unknown argument"; else bad "setup.sh --chek: exit $rc" "$out"; fi

# Sandbox: the home is its own git repo; every tool is a stub. PI_LIST sets what `pi list` reports,
# HERDR_STATUS what `herdr integration status` reports; other calls are logged to $sb/log.
sb="$TMP/sb"; mkdir -p "$sb/fm" "$sb/bin"
git -C "$sb/fm" init -q
for t in gh-axi chrome-devtools-axi lavish-axi quota-axi tasks-axi; do printf '#!/bin/sh\necho "%s $*" >>"%s/log"\n' "$t" "$sb" >"$sb/bin/$t"; done
cat >"$sb/bin/herdr" <<EOF
#!/bin/sh
case "\$1 \$2" in "integration status") [ -z "\$HERDR_FAIL" ] || exit 1; printf '%b' "\$HERDR_STATUS" ;; *) echo "herdr \$*" >>"$sb/log" ;; esac
EOF
cat >"$sb/bin/pi" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "list ") if [ -n "\$FORCE_COLOR" ] && [ "\$FORCE_COLOR" != 0 ]; then printf '\033[1mUser packages:\033[22m\n'; printf '%b' "\$PI_LIST" | tail -n +2; else printf '%b' "\$PI_LIST"; fi ;;
  "install -l") [ "\$3" = -a ] || { echo "Project is not trusted. Use --approve to modify local package config." >&2; exit 1; }
    echo "pi \$*" >>"$sb/log"; mkdir -p .pi; [ -s .pi/settings.json ] || echo '{}' >.pi/settings.json
    jq --arg p "\$4" '.packages += [\$p]' .pi/settings.json >.pi/s.tmp && mv .pi/s.tmp .pi/settings.json ;;
  *) echo "pi \$*" >>"$sb/log" ;;
esac
EOF
printf '#!/bin/sh\n' >"$sb/bin/treehouse"
chmod +x "$sb/bin"/*
PI_LIST='User packages:\n  npm:pi-web-access (filtered)\n    /x\n  npm:pi-lens@4.5.0 (filtered)\n    /y\nProject packages:\n  npm:pi-markdown-preview\n    /z\n'
HERDR_STATUS='pi: not installed (x)\n'
run() { HOME="$sb" FM_HOME="$sb/fm" PATH="$sb/bin:$PATH" HERDR_STATUS="$HERDR_STATUS" PI_LIST="$PI_LIST" "$HERE/setup.sh" ${1:+"$1"} 2>&1; }
snap() { (cd "$sb" && find fm -type f -not -path '*/.git/*' | sort | xargs -r cksum; cksum <fm/.git/info/exclude 2>/dev/null); }

before="$(snap)"
out="$(run --check)"
gaps=0
for want in 'pi package npm:cc-safety-net' 'pi package git:github.com/DietrichGebert/ponytail' 'primary-session pi package npm:pi-context-view@0.8.4' \
  'primary-session pi package git:github.com/DietrichGebert/ponytail with filters' \
  'primary-session pi package git:github.com/nphuoctho/pi-usage-bars@e595440' 'pi codemode' 'herdr integration for pi' 'config/crew-dispatch.json' 'config/brief-include.md' \
  'config/supervision-branch-model' 'config/supervision-branch-effort' 'config/park-on-review' 'config/auto-land' 'config/pr-register-scan' '.pi-lens.json' \
  'git exclude entry .pi/settings.json' 'git exclude entry .pi-lens.json' 'remove user-level npm:pi-lens'; do
  grep -q "MISSING: .*$want" <<<"$out" || { gaps=1; bad "--check did not report: $want" "$out"; }
done
if grep -q 'remove user-level npm:pi-markdown-preview' <<<"$out"; then gaps=1; bad "a project-level package was treated as user-level"; fi
[ "$gaps" = 0 ] && ok "--check reports every gap"
if [ "$before" = "$(snap)" ] && [ ! -e "$sb/fm/.pi" ] && [ ! -e "$sb/.pi/agent/settings.json" ] && ! grep -Eq 'install|remove' "$sb/log" 2>/dev/null; then ok "--check writes nothing"; else bad "--check changed the sandbox"; fi

# A real run applies everything. A changed file survives with a drift note, and a second run changes nothing.
mkdir -p "$sb/fm/config" "$sb/.pi/agent"; printf 'custom-model\n' >"$sb/fm/config/supervision-branch-model"
printf '{"theme":"dark","defaultTools":["-write"]}\n' >"$sb/.pi/agent/settings.json"
out="$(run)"
S="$sb/fm/.pi/settings.json"
if [ "$(jq -c '.packages' "$S")" = "$(jq -c '.packages' "$P/pi-primary-settings.json")" ] && ! jq -e 'has("defaultTools")' "$S" >/dev/null &&
  jq -e '.theme == "dark" and .defaultTools == ["-write", "+codemode"]' "$sb/.pi/agent/settings.json" >/dev/null &&
  grep -qx 'pi install npm:cc-safety-net' "$sb/log" && grep -qx 'pi install -l -a npm:pi-lens@4.5.1' "$sb/log" && grep -qx 'pi install git:github.com/DietrichGebert/ponytail' "$sb/log" &&
  ! grep -q 'pi install npm:pi-web-access' "$sb/log" && grep -qx 'pi remove npm:pi-lens@4.5.0' "$sb/log" &&
  ! grep -q 'pi remove npm:pi-markdown-preview' "$sb/log" && grep -qx 'herdr integration install pi' "$sb/log"; then ok "a real run installs each package at the right level, codemode at user level, Ponytail off in the primary"; else bad "real run package handling wrong" "$out"; fi
if cmp -s "$P/brief-include.md" "$sb/fm/config/brief-include.md" && cmp -s "$P/crew-dispatch.json" "$sb/fm/config/crew-dispatch.json" &&
  cmp -s "$P/supervision-branch-effort" "$sb/fm/config/supervision-branch-effort" && cmp -s "$P/pi-lens.json" "$sb/fm/.pi-lens.json" &&
  [ -e "$sb/fm/config/park-on-review" ] && [ -e "$sb/fm/config/auto-land" ] && [ -e "$sb/fm/config/pr-register-scan" ]; then ok "a real run seeds the config files and option flags"; else bad "config not seeded" "$out"; fi
if [ "$(cat "$sb/fm/config/supervision-branch-model")" = custom-model ] && grep -q 'config/supervision-branch-model differs from the preset' <<<"$out"; then ok "a changed config file is kept and noted"; else bad "changed config file mishandled" "$out"; fi
if git -C "$sb/fm" status --porcelain -- .pi .pi-lens.json | grep -q .; then bad "primary-only files are not excluded from git" "$(git -C "$sb/fm" status --porcelain)"; else ok "primary-only files are excluded from git"; fi
: >"$sb/log"; before="$(snap)"
# The stubs keep no state, so describe the machine after the first run.
PI_LIST='User packages:\n  npm:pi-web-access\n    /x\n  npm:cc-safety-net\n    /x\n  git:github.com/DietrichGebert/ponytail\n    /x\n'
HERDR_STATUS='pi: current (v1) (x)\n'
out="$(run)"
if [ "$(snap)" = "$before" ] && ! grep -Eq 'install' "$sb/log"; then ok "a second run changes nothing"; else bad "second run was not idempotent" "$out"; fi

# Herdr status failing skips the integration check rather than reporting it missing.
out="$(HERDR_FAIL=1 run --check)"
if grep -q 'skipped: Herdr integration check' <<<"$out" && ! grep -q 'MISSING: herdr integration' <<<"$out"; then ok "a failing herdr status skips the integration check"; else bad "failed herdr status mishandled" "$out"; fi

# Colour in `pi list` (FORCE_COLOR set outside) must not hide the user-level packages.
out="$(FORCE_COLOR=1 run --check)"
if ! grep -q 'MISSING: pi package npm:pi-web-access' <<<"$out"; then ok "a coloured pi list is still read"; else bad "FORCE_COLOR broke the pi list parse" "$out"; fi

# defaultTools: [] means "no built-in tools" and is left alone with a note.
printf '{"defaultTools":[]}\n' >"$sb/.pi/agent/settings.json"
out="$(run --check)"
if grep -q 'defaultTools is empty or names plain tools' <<<"$out" && ! grep -q 'MISSING: pi codemode' <<<"$out"; then ok "an empty defaultTools is only noted"; else bad "empty defaultTools mishandled" "$out"; fi

# A missing tool must not stop the run: curated PATH holding only the stubs and the basic tools.
mk_min() {
  rm -rf "$sb/min"; mkdir -p "$sb/min"
  for t in "$@"; do ln -s "$(command -v "$t")" "$sb/min/$t"; done
  cp "$sb/bin"/* "$sb/min/"
}
BASIC=(bash git awk grep cmp cp mkdir touch dirname mv head cat sed env date basename tail tr)
run_min() { HOME="$sb" FM_HOME="$sb/fm2" PATH="$sb/min" HERDR_STATUS="$HERDR_STATUS" PI_LIST="$PI_LIST" bash "$HERE/setup.sh" 2>&1; }
rm -rf "$sb/fm2"; mkdir -p "$sb/fm2"; git -C "$sb/fm2" init -q
mk_min "${BASIC[@]}" jq node gh curl
rm -f "$sb/min/tasks-axi"
out="$(run_min)"; rc=$?
if [ "$rc" = 1 ] && grep -q 'MISSING: npm' <<<"$out" && grep -q 'MISSING: tasks-axi (npm install -g failed)' <<<"$out" && [ -e "$sb/fm2/config/crew-dispatch.json" ] && [ -e "$sb/fm2/config/auto-land" ] && grep -qx '.pi-lens.json' "$sb/fm2/.git/info/exclude"; then ok "a missing npm is reported and the rest of the setup still runs"; else bad "missing npm aborted the run (exit $rc)" "$out"; fi
rm -rf "$sb/fm2"; mkdir -p "$sb/fm2"; git -C "$sb/fm2" init -q
mk_min "${BASIC[@]}" node npm gh curl
out="$(run_min)"; rc=$?
if [ "$rc" = 1 ] && grep -q 'MISSING: jq' <<<"$out" && grep -q 'needs both pi and jq' <<<"$out" && [ ! -e "$sb/fm2/.pi" ] && ! grep -q 'command not found' <<<"$out"; then ok "a missing jq is reported and nothing half-written is left"; else bad "missing jq mishandled (exit $rc)" "$out"; fi

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
