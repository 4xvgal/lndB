#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="list-targets"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

build_targets
printf '%s\n' "${SRC_TARGETS[@]}"
