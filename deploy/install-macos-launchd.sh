#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.gomediahomeserver"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BINARY="$ROOT_DIR/gomediahomeserver"

if [[ ! -f "$ROOT_DIR/config.json" ]]; then
  echo "Missing $ROOT_DIR/config.json. Copy config.example.json and configure it first." >&2
  exit 1
fi

if [[ ! -x "$BINARY" ]]; then
  command -v go >/dev/null || { echo "Go is required to build the server." >&2; exit 1; }
  echo "Building goMediaHomeServer..."
  (cd "$ROOT_DIR" && go build -buildvcs=false -o "$BINARY" ./cmd/gomediahomeserver)
fi

mkdir -p "$HOME/Library/LaunchAgents" "$ROOT_DIR/data"
sed "s#YOUR_USERNAME#$(id -un)#g" "$ROOT_DIR/deploy/com.gomediahomeserver.plist.example" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
echo "Status: launchctl print gui/$(id -u)/$LABEL"
echo "Logs:   tail -f $ROOT_DIR/data/server.stdout.log"
