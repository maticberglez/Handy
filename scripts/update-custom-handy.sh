#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
for tool in git bun cargo python3 curl; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool"; exit 1; }
done
# Uncommitted files cannot be preserved by a Git merge.
changes=$(git status --porcelain --untracked-files=all -- . ':!Update Custom Handy.command' ':!scripts/update-custom-handy.sh' ':!scripts/test-update-custom-handy.sh' ':!CUSTOM_UPDATES.md')
if [ -n "$changes" ]; then
  echo "Commit your custom changes first. No update was started:"
  printf '%s\n' "$changes"
  exit 1
fi
if [ "${1:-}" = "--check" ]; then
  echo "Ready: required tools are installed and custom source changes are committed."
  exit 0
fi
BASE="$ROOT/.custom-updates.local"
mkdir -p "$BASE"
if ! mkdir "$BASE/running.lock" 2>/dev/null; then
  echo "An update is already running. If it was interrupted, remove $BASE/running.lock and retry."
  exit 1
fi
trap 'rmdir "$BASE/running.lock"' EXIT
WORK="$(mktemp -d "$BASE/update-XXXXXX")"
exec > >(tee "$WORK/update.log") 2>&1
trap 'echo "Update stopped. Your everyday app is unchanged. Files and log: $WORK"' ERR
printf 'Checking the latest official Handy release...\n'
RELEASE=$(curl --connect-timeout 20 --max-time 120 --fail --silent --show-error --location --retry 3 \
  https://api.github.com/repos/cjpais/Handy/releases/latest | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
# Only accept ordinary version tags, never arbitrary revision expressions.
if [[ ! "$RELEASE" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "Unexpected release tag: $RELEASE"; exit 1
fi
export CARGO_TARGET_DIR="$BASE/target"
# Reuse the previous successful build's dependencies on the first cached run.
if [ ! -d "$CARGO_TARGET_DIR" ]; then
  for previous in "$BASE"/update-*/source/src-tauri/target; do
    if [ -d "$previous/release" ]; then
      ln -s "$previous" "$CARGO_TARGET_DIR"
      break
    fi
  done
fi
APP="$CARGO_TARGET_DIR/release/bundle/macos/Handy Update Preview.app"
FINGERPRINT="$(git rev-parse HEAD) $RELEASE $(git hash-object scripts/update-custom-handy.sh)"
if [ -d "$APP" ] && [ -f "$BASE/built-version" ] && [ "$(cat "$BASE/built-version")" = "$FINGERPRINT" ]; then
  echo "Already up to date. Your tested preview is ready: $APP"
  open -R "$APP"
  exit 0
fi
echo "Preparing your custom source with official release $RELEASE in $WORK/source"
git clone --no-hardlinks --single-branch "$ROOT" "$WORK/source"
cd "$WORK/source"
git remote add upstream https://github.com/cjpais/Handy.git
git fetch --no-tags upstream "refs/tags/$RELEASE:refs/tags/$RELEASE"
if ! git -c user.name='Handy Local Updater' -c user.email='handy-updater@example.invalid' \
  -c commit.gpgsign=false merge --no-edit "refs/tags/$RELEASE"; then
  git diff --name-only --diff-filter=U
  git merge --abort
  echo "Automatic merge failed. No app was installed. Resolve this in $WORK/source with help."
  exit 1
fi
# A separate identifier keeps preview settings and single-instance behavior isolated.
cat > src-tauri/update-preview.local.json <<'CONFIG'
{
  "productName": "Handy Update Preview",
  "identifier": "com.maticberglez.handy.preview",
  "bundle": { "createUpdaterArtifacts": false }
}
CONFIG
mkdir -p src-tauri/resources/models
MODEL=silero-vad-v6.2-F32.gguf
if [ -f "$ROOT/src-tauri/resources/models/$MODEL" ]; then
  cp "$ROOT/src-tauri/resources/models/$MODEL" "src-tauri/resources/models/$MODEL"
else
  curl --fail --location --retry 3 -o "src-tauri/resources/models/$MODEL" \
    "https://huggingface.co/handy-computer/silero-vad-v6.2-gguf/resolve/main/$MODEL"
fi
bun install --frozen-lockfile
bun run lint
bun run check:translations
(cd src-tauri && cargo fmt -- --check)
HANDY_SOURCE_ROOT="$ROOT" CMAKE_POLICY_VERSION_MINIMUM=3.5 bun run tauri build --bundles app --config src-tauri/update-preview.local.json
[ -d "$APP" ] || { echo 'Build finished but the preview app could not be found.'; exit 1; }
printf '%s\n' "$FINGERPRINT" > "$BASE/built-version"
printf '\nUpdated preview ready: %s\n' "$APP"
printf 'Quit everyday Handy before opening the preview to avoid shortcut conflicts.\n'
printf 'The preview has separate settings. Test it before adopting this update.\n'
printf 'Keep this folder: it contains your merged source for the eventual everyday build.\n'
open -R "$APP"
