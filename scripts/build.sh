#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-debug}

case "$CONFIGURATION" in
    debug|release)
        ;;
    *)
        echo "CONFIGURATION must be 'debug' or 'release'." >&2
        exit 2
        ;;
esac

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION" "$@"
