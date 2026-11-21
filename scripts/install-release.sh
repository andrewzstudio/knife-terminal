#!/bin/bash
# Install a release of Andrew's fork over the running Knife, then relaunch it.
# Usage: scripts/install-release.sh v1.4.34-andrew
# Quitting Knife ends any Claude session running inside it, so this detaches itself first:
# the swap happens ~8 s later, after Knife has quit. Log: ~/.knife/backup/install.log
set -euo pipefail
TAG="${1:?usage: $0 <release tag, e.g. v1.4.34-andrew>}"
REPO=andrewzstudio/knife-terminal
GH="${GH:-$HOME/.local/bin/gh}"
WORK="$HOME/.knife/backup/releases/$TAG"
APP="/Applications/Knife Terminal.app"
LOG="$HOME/.knife/backup/install.log"

if [ "${KNIFE_INSTALL_DETACHED:-}" != 1 ]; then
  rm -rf "$WORK" && mkdir -p "$WORK"
  "$GH" release download "$TAG" -R "$REPO" -p '*.zip' -D "$WORK"
  ditto -x -k "$WORK"/*.zip "$WORK/unzipped"
  NEW="$WORK/unzipped/Knife Terminal.app"
  codesign --verify --deep --strict "$NEW"
  echo "verified $(defaults read "$NEW/Contents/Info" CFBundleShortVersionString)"
  OLD_V=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo none)
  ditto -c -k --keepParent "$APP" "$HOME/.knife/backup/Knife-Terminal-$OLD_V-before-$TAG.zip"
  echo "backed up current $OLD_V to ~/.knife/backup/Knife-Terminal-$OLD_V-before-$TAG.zip"
  KNIFE_INSTALL_DETACHED=1 nohup python3 -c 'import os,sys; os.setsid(); os.execv("/bin/bash", ["/bin/bash"] + sys.argv[1:])' \
    "$0" "$TAG" >/dev/null 2>&1 &
  echo "Knife will quit in ~8 s, be replaced, and reopen."
  exit 0
fi

exec >>"$LOG" 2>&1
echo "== $(date) installing $TAG"
NEW="$WORK/unzipped/Knife Terminal.app"
sleep 8
osascript -e 'tell application "Knife Terminal" to quit' || true
for _ in $(seq 1 60); do pgrep -x "Knife Terminal" >/dev/null || break; sleep 1; done
if pgrep -x "Knife Terminal" >/dev/null; then echo "Knife did not quit; nothing changed"; exit 1; fi
rm -rf "$APP" && ditto "$NEW" "$APP" && xattr -dr com.apple.quarantine "$APP"
echo "installed $(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
open "$APP"
