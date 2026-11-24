#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE="gomediahomeserver"
UNIT="/etc/systemd/system/$SERVICE.service"
BINARY="$ROOT_DIR/gomediahomeserver"

if [[ ! -f "$ROOT_DIR/config.json" ]]; then
  echo "Missing $ROOT_DIR/config.json. Copy config.example.json and configure it first." >&2
  exit 1
fi
command -v go >/dev/null || { echo "Go is required to build the server." >&2; exit 1; }

if [[ ! -x "$BINARY" ]]; then
  (cd "$ROOT_DIR" && go build -buildvcs=false -o "$BINARY" ./cmd/gomediahomeserver)
fi

sudo mkdir -p "$ROOT_DIR/data"
sudo chown -R "$(id -un):$(id -gn)" "$ROOT_DIR/data" "$ROOT_DIR/config.json" "$BINARY"
sed "s#^User=.*#User=$(id -un)#; s#^WorkingDirectory=.*#WorkingDirectory=$ROOT_DIR#; s#^ExecStart=.*#ExecStart=$BINARY#" "$ROOT_DIR/deploy/gomediahomeserver.service.example" | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE"
sudo systemctl status "$SERVICE" --no-pager
