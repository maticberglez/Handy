#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/update-custom-handy.sh" "$ROOT/Update Custom Handy.command"
# Uncommitted changes must stop even the prerequisite check.
git() { printf ' M src/App.tsx\n'; }
export -f git
if output=$(bash "$ROOT/scripts/update-custom-handy.sh" --check 2>&1); then
  echo 'FAIL: updater accepted uncommitted source changes'; exit 1
fi
[[ "$output" == *'Commit your custom changes first.'* ]]
unset -f git

# Real local Git merges; downloads, compilation and main-app replacement are mocked.
FIXTURE=$(mktemp -d)
trap 'if [ "$?" != 0 ]; then cat "$FIXTURE"/*.log 2>/dev/null; fi; rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/custom/scripts" "$FIXTURE/custom/src-tauri/resources/models"
cp "$ROOT/scripts/update-custom-handy.sh" "$ROOT/scripts/install-custom-handy.py" "$FIXTURE/custom/scripts/"
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
REAL_PYTHON=$(command -v python3)
export REAL_GIT REAL_PYTHON
export TEST_RELEASE=v1.0.0
git() {
  if [ "${1:-}" = remote ] && [ "${2:-}" = add ] && [ "${3:-}" = upstream ]; then
    "$REAL_GIT" remote add upstream "$FIXTURE/upstream"
  else
    "$REAL_GIT" "$@"
  fi
}
curl() { printf '{"tag_name":"%s"}' "$TEST_RELEASE"; }
bun() {
  if [ "${FAIL_CHECKS:-}" = 1 ] && [ "${2:-}" = lint ]; then
    echo 'simulated lint failure'; return 1
  fi
  if [ "${1:-}" = run ] && [ "${2:-}" = tauri ]; then
    mkdir -p "$CARGO_TARGET_DIR/release/bundle/macos/Handy.app"
    echo build >> "$FIXTURE/builds"
  fi
}
cargo() { return 0; }
python3() {
  if [[ "${1:-}" == */install-custom-handy.py ]]; then
    if [ "${2:-}" = --is-current ]; then
      [ -f "$FIXTURE/installed" ] && [ "$(cat "$FIXTURE/installed")" = "$("$REAL_GIT" -C "$3" rev-parse HEAD) $4" ]
    else
      [ -d "$4" ] && [[ "$4" == */Handy.app ]]
      "$REAL_GIT" -C "$2" fetch "$3" HEAD
      "$REAL_GIT" -C "$2" merge --ff-only FETCH_HEAD
      echo "$("$REAL_GIT" -C "$2" rev-parse HEAD) $5" > "$FIXTURE/installed"
      echo install >> "$FIXTURE/installs"
    fi
  else
    "$REAL_PYTHON" "$@"
  fi
}
export -f git curl bun cargo python3
bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/first.log" 2>&1
bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/second.log" 2>&1
[ "$(wc -l < "$FIXTURE/builds" | tr -d ' ')" = 1 ]
[ "$(wc -l < "$FIXTURE/installs" | tr -d ' ')" = 1 ]
rg -q 'Already up to date' "$FIXTURE/second.log"
[ "$(cat "$FIXTURE/custom/.custom-updates.local/result")" = 0 ]
! find "$FIXTURE" -name '*Preview.app' -print | rg .
# Failed checks must not install or advance the original checkout.
printf new > "$FIXTURE/upstream/new-file"
"$REAL_GIT" -C "$FIXTURE/upstream" add .
"$REAL_GIT" -C "$FIXTURE/upstream" -c user.name=Test -c user.email=test@example.invalid commit -qm update
"$REAL_GIT" -C "$FIXTURE/upstream" tag v1.0.1
export TEST_RELEASE=v1.0.1 FAIL_CHECKS=1
before=$("$REAL_GIT" -C "$FIXTURE/custom" rev-parse HEAD)
if bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/check-failed.log" 2>&1; then
  echo 'FAIL: ignored failed checks'; exit 1
fi
[ "$("$REAL_GIT" -C "$FIXTURE/custom" rev-parse HEAD)" = "$before" ]
[ "$(wc -l < "$FIXTURE/installs" | tr -d ' ')" = 1 ]
[ "$(cat "$FIXTURE/custom/.custom-updates.local/result")" != 0 ]
rg -q 'simulated lint failure' "$FIXTURE/custom/.custom-updates.local/ui-update.log"
unset FAIL_CHECKS
bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/new-release.log" 2>&1
[ -f "$FIXTURE/custom/new-file" ]
[ "$(wc -l < "$FIXTURE/installs" | tr -d ' ')" = 2 ]
# Conflicting custom and upstream edits must abort without touching main source.
printf custom > "$FIXTURE/custom/example"
"$REAL_GIT" -C "$FIXTURE/custom" -c user.name=Test -c user.email=test@example.invalid commit -qam custom
printf upstream > "$FIXTURE/upstream/example"
"$REAL_GIT" -C "$FIXTURE/upstream" -c user.name=Test -c user.email=test@example.invalid commit -qam upstream
"$REAL_GIT" -C "$FIXTURE/upstream" tag v1.0.2
export TEST_RELEASE=v1.0.2
if bash "$FIXTURE/custom/scripts/update-custom-handy.sh" > "$FIXTURE/conflict.log" 2>&1; then
  echo 'FAIL: conflicting merge succeeded'; exit 1
fi
rg -q 'Automatic merge failed' "$FIXTURE/conflict.log"
[ "$(cat "$FIXTURE/custom/example")" = custom ]
[ "$(wc -l < "$FIXTURE/installs" | tr -d ' ')" = 2 ]
[ ! -d "$FIXTURE/custom/.custom-updates.local/running.lock" ]
echo 'PASS: direct main-app updates, unchanged release skip, failed checks, persisted errors, and conflict abort.'
