#!/usr/bin/env bash
# Compose the AI Native per-repo no-mistakes policy for one stack into <repo-dir>/.no-mistakes.yaml.
# Usage: ai-native/new-project.sh <stack> <repo-dir>
# Stacks: the file names under ai-native/no-mistakes/stacks/ (node python go rust cpp shopify).
# Never overwrites an existing .no-mistakes.yaml.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS="$HERE/no-mistakes/stacks"
BASE="$HERE/no-mistakes/project.no-mistakes.yaml"
MARK='# @@STACK@@'

list() { for f in "$STACKS"/*.yaml; do basename "$f" .yaml; done | tr '\n' ' '; }
die() { printf 'new-project.sh: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 2 ] || die "usage: new-project.sh <stack> <repo-dir>   (stacks: $(list))"
stack="$1"
repo="$2"
case "$stack" in *[!a-z0-9_-]* | "") die "invalid stack name '$stack' (stacks: $(list))" ;; esac
snippet="$STACKS/$stack.yaml"
[ -f "$snippet" ] || die "unknown stack '$stack' (stacks: $(list))"
[ -d "$repo" ] || die "not a directory: $repo"
out="$repo/.no-mistakes.yaml"
[ ! -e "$out" ] || die "$out already exists; not overwriting"
grep -qxF "$MARK" "$BASE" || die "marker line missing in $BASE"

tmp="$(mktemp "$repo/.no-mistakes.yaml.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$line" = "$MARK" ]; then cat "$snippet"; else printf '%s\n' "$line"; fi
done <"$BASE" >"$tmp"
# ln fails if the target appeared meanwhile, so a racing file is never replaced.
ln "$tmp" "$out" 2>/dev/null || die "$out appeared meanwhile; not overwriting"
printf 'wrote %s (%s). Commit it on the default branch, then run: no-mistakes init\n' "$out" "$stack"
