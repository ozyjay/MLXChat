#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TARGET=mlxchat

if [ "$#" -gt 0 ]; then
    case "$1" in
        cli|mlxchat)
            TARGET=mlxchat
            shift
            ;;
        app|mlxchat-app)
            TARGET=mlxchat-app
            shift
            ;;
    esac
fi

cd "$ROOT_DIR"
swift run "$TARGET" "$@"
