#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/update-custom-handy.sh" "$ROOT/Update Custom Handy.command"
# Simulate a dirty checkout and verify it stops before any download/build.
git() {
  if [ "${1:-}" = status ]; then
    printf ' M src/App.tsx\n'
  else
    echo 'Unexpected Git operation during preflight' >&2
    return 99
  fi
}
export -f git
if output=$(bash "$ROOT/scripts/update-custom-handy.sh" --check 2>&1); then
  echo 'FAIL: updater accepted uncommitted source changes'; exit 1
fi
[[ "$output" == *'Commit your custom changes first.'* ]] || { printf '%s\n' "$output"; exit 1; }
unset -f git
bash "$ROOT/scripts/update-custom-handy.sh" --check
echo 'PASS: shell syntax, dirty-checkout protection, and real prerequisites.'

# Exercise real Git merges with a local upstream and fake only network/build/UI.
FIXTURE=$(mktemp -d)
trap 'if [ "$?" != 0 ]; then cat "$FIXTURE"/*.log 2>/dev/null; fi; rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/custom/scripts" "$FIXTURE/custom/src-tauri/resources/models"
cp "$ROOT/scripts/update-custom-handy.sh" "$FIXTURE/custom/scripts/"
printf model > "$FIXTURE/custom/src-tauri/resources/models/silero-vad-v6.2-F32.gguf"
printf base > "$FIXTURE/custom/example"
printf ".custom-updates.local/\n" > "$FIXTURE/custom/.gitignore"
git init -q "$FIXTURE/custom"
git -C "$FIXTURE/custom" add .
git -C "$FIXTURE/custom" -c user.name=Test -c user.email=test@example.invalid commit -qm base
git clone -q "$FIXTURE/custom" "$FIXTURE/upstream"
git -C "$FIXTURE/upstream" tag v1.0.0
export FIXTURE
REAL_GIT=$(command -v git)
export REAL_GIT
git() {
  if [ "${1:-}" = remote ] && [ "${2:-}" = add ] && [ "${3:-}" = upstream ]; then
    "$REAL_GIT" remote add upstream "$FIXTURE/upstream"
  else
    "$REAL_GIT" "$@"
  fi
}
curl() { printf '{"tag_name":"v1.0.0"}'; }
bun() {
  if [ "${1:-}" = run ] && [ "${2:-}" = tauri ]; then
    mkdir -p "$CARGO_TARGET_DIR/release/bundle/macos/Handy Update Preview.app"
    echo build >> "$FIXTURE/builds"
  fi
}
cargo() { return 0; }
open() { test -d "$2"; }
export -f git curl bun cargo open
bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/first.log" 2>&1
bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/second.log" 2>&1
[ "$(wc -l < "$FIXTURE/builds" | tr -d ' ')" = 1 ]
rg -q 'Already up to date' "$FIXTURE/second.log"
# Divergent edits must abort without changing the custom checkout.
printf custom > "$FIXTURE/custom/example"
"$REAL_GIT" -C "$FIXTURE/custom" -c user.name=Test -c user.email=test@example.invalid commit -qam custom
printf upstream > "$FIXTURE/upstream/example"
"$REAL_GIT" -C "$FIXTURE/upstream" -c user.name=Test -c user.email=test@example.invalid commit -qam upstream
"$REAL_GIT" -C "$FIXTURE/upstream" tag -f v1.0.0 >/dev/null
if bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/conflict.log" 2>&1; then
  echo 'FAIL: conflicting merge succeeded'; exit 1
fi
rg -q 'Automatic merge failed' "$FIXTURE/conflict.log"
[ "$(cat "$FIXTURE/custom/example")" = custom ]
[ "$(wc -l < "$FIXTURE/builds" | tr -d ' ')" = 1 ]
echo 'PASS: cached repeat skips build; conflicting merge aborts and preserves custom source.'
