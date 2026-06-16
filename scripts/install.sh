#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PREFIX=${PREFIX:-"$HOME/.local"}
BIN_DIR=${BIN_DIR:-"$PREFIX/bin"}

cd "$ROOT_DIR"
swift build -c release
BIN_PATH=$(swift build -c release --show-bin-path)

mkdir -p "$BIN_DIR"
install -m 755 "$BIN_PATH/mlxchat" "$BIN_DIR/mlxchat"
install -m 755 "$BIN_PATH/mlxchat-app" "$BIN_DIR/mlxchat-app"

echo "Installed mlxchat and mlxchat-app to $BIN_DIR"
echo "Add $BIN_DIR to PATH if it is not already available."
