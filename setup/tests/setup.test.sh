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
if jq -e '(.packages | length) == 5 and (.packages | index("npm:pi-markdown-preview")) != null and (.packages | index("npm:pi-lens@4.5.1")) != null and (.packages | index("npm:pi-context-view@0.8.4")) != null and (.packages | index("npm:@juicesharp/rpiv-todo@2.15.0")) != null and (.packages | index("git:github.com/nphuoctho/pi-usage-bars@e595440")) != null' "$P/pi-primary-settings.json" >/dev/null &&
  jq -e '.defaultTools == ["+codemode"]' "$P/pi-primary-settings.json" >/dev/null &&
  jq -e '.format.enabled == false and .autofix.enabled == false' "$P/pi-lens.json" >/dev/null; then ok "primary-session presets pin the packages, turn codemode on and pi-lens formatting off"; else bad "primary-session presets are wrong"; fi
if jq -e '.shared_quota == true and (.rules | length) == 6 and .default.model == "anthropic/claude-sonnet-5-5" and .default.effort == "medium" and ([.rules[].use.harness] | unique) == ["pi"]' "$P/crew-dispatch.json" >/dev/null; then ok "dispatch preset has six questions and the Sonnet medium default"; else bad "dispatch preset shape is wrong"; fi
if [ "$(cat "$P/supervision-branch-model")" = anthropic/claude-haiku-5-5 ] && [ "$(cat "$P/supervision-branch-effort")" = medium ] &&
  grep -q 'Conventional Commits' "$P/brief-include.md" && grep -q 'Conventional Branch' "$P/brief-include.md" && grep -q 'flank.github.io/flank/pr_titles' "$P/brief-include.md"; then ok "supervision and brief-include presets have the standard content"; else bad "supervision or brief-include preset wrong"; fi

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
  "list ") printf '%b' "\$PI_LIST" ;;
  "install -l") echo "pi \$*" >>"$sb/log"; mkdir -p .pi; [ -s .pi/settings.json ] || echo '{}' >.pi/settings.json
    jq --arg p "\$3" '.packages += [\$p]' .pi/settings.json >.pi/s.tmp && mv .pi/s.tmp .pi/settings.json ;;
  *) echo "pi \$*" >>"$sb/log" ;;
esac
EOF
printf '#!/bin/sh\n' >"$sb/bin/treehouse"
chmod +x "$sb/bin"/*
PI_LIST='User packages:\n  npm:pi-web-access\n    /x\n  npm:pi-lens@4.5.0\n    /y\nProject packages:\n  npm:pi-markdown-preview\n    /z\n'
HERDR_STATUS='pi: not installed (x)\n'
run() { HOME="$sb" FM_HOME="$sb/fm" PATH="$sb/bin:$PATH" HERDR_STATUS="$HERDR_STATUS" PI_LIST="$PI_LIST" "$HERE/setup.sh" ${1:+"$1"} 2>&1; }
snap() { (cd "$sb" && find fm -type f -not -path '*/.git/*' | sort | xargs -r cksum; cksum <fm/.git/info/exclude 2>/dev/null); }

before="$(snap)"
out="$(run --check)"
gaps=0
for want in 'pi package npm:cc-safety-net' 'pi package git:github.com/DietrichGebert/ponytail' 'primary-session pi package npm:pi-context-view@0.8.4' \
  'primary-session pi package git:github.com/nphuoctho/pi-usage-bars@e595440' 'pi codemode' 'herdr integration for pi' 'config/crew-dispatch.json' 'config/brief-include.md' \
  'config/supervision-branch-model' 'config/supervision-branch-effort' 'config/park-on-review' 'config/auto-land' 'config/pr-register-scan' '.pi-lens.json' \
  'git exclude entry .pi/settings.json' 'git exclude entry .pi-lens.json' 'remove user-level npm:pi-lens'; do
  grep -q "MISSING: .*$want" <<<"$out" || { gaps=1; bad "--check did not report: $want" "$out"; }
done
if grep -q 'remove user-level npm:pi-markdown-preview' <<<"$out"; then gaps=1; bad "a project-level package was treated as user-level"; fi
[ "$gaps" = 0 ] && ok "--check reports every gap"
if [ "$before" = "$(snap)" ] && [ ! -e "$sb/fm/.pi" ] && ! grep -Eq 'install|remove' "$sb/log" 2>/dev/null; then ok "--check writes nothing"; else bad "--check changed the sandbox"; fi

# A real run applies everything. A changed file survives with a drift note, and a second run changes nothing.
mkdir -p "$sb/fm/config"; printf 'custom-model\n' >"$sb/fm/config/supervision-branch-model"
out="$(run)"
S="$sb/fm/.pi/settings.json"
if [ "$(jq -c '.packages' "$S")" = "$(jq -c '.packages' "$P/pi-primary-settings.json")" ] && jq -e '.defaultTools == ["+codemode"]' "$S" >/dev/null &&
  grep -qx 'pi install npm:cc-safety-net' "$sb/log" && grep -qx 'pi install git:github.com/DietrichGebert/ponytail' "$sb/log" &&
  ! grep -q 'pi install npm:pi-web-access' "$sb/log" && grep -qx 'pi remove npm:pi-lens@4.5.0' "$sb/log" &&
  ! grep -q 'pi remove npm:pi-markdown-preview' "$sb/log" && grep -qx 'herdr integration install pi' "$sb/log"; then ok "a real run installs each package at the right level"; else bad "real run package handling wrong" "$out"; fi
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

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
