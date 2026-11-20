#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
MOSS_BUILD_VARIANT=release-universal "$SCRIPT_DIR/package_app.sh"
