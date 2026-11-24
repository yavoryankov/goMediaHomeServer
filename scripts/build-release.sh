#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR=${1:-"$ROOT_DIR/dist"}
VERSION=${VERSION:-"dev"}

mkdir -p "$OUTPUT_DIR"

build_one() {
  os=$1
  arch=$2
  suffix=$3
  name="gomediahomeserver-${VERSION}-${os}-${arch}"
  staging="$OUTPUT_DIR/$name"
  mkdir -p "$staging"

  echo "Building $os/$arch"
  GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
    go build -buildvcs=false -trimpath -ldflags "-s -w" \
    -o "$staging/gomediahomeserver$suffix" \
    "$ROOT_DIR/cmd/gomediahomeserver"

  cp "$ROOT_DIR/config.example.json" "$staging/"
  cp "$ROOT_DIR/README.md" "$staging/"
  cp "$ROOT_DIR/LICENSE" "$staging/"
  cp "$ROOT_DIR/deploy/com.gomediahomeserver.plist.example" "$staging/" 2>/dev/null || true
  cp "$ROOT_DIR/deploy/gomediahomeserver.service.example" "$staging/" 2>/dev/null || true

  archive="$OUTPUT_DIR/$name"
  if [ "$os" = "windows" ]; then
    (cd "$OUTPUT_DIR" && zip -qr "$archive.zip" "$name")
  else
    tar -czf "$archive.tar.gz" -C "$OUTPUT_DIR" "$name"
  fi
  rm -rf "$staging"
}

build_one darwin amd64 ""
build_one darwin arm64 ""
build_one linux amd64 ""
build_one linux arm64 ""
build_one windows amd64 ".exe"

echo "Release artifacts written to $OUTPUT_DIR"
