#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="create-archive"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_bins tar gzip
build_targets

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_WORK_DIR=${WORK_DIR:-$PROJECT_ROOT/tmp}
OUTPUT_ARCHIVE=${OUTPUT_ARCHIVE:-$DEFAULT_WORK_DIR/${ARCHIVE_PREFIX:-lndb}-manual-$TIMESTAMP.tar.gz}

mkdir -p "$(dirname "$OUTPUT_ARCHIVE")"
say "creating archive at $OUTPUT_ARCHIVE"
tar -czf "$OUTPUT_ARCHIVE" --absolute-names "${SRC_TARGETS[@]}"
say "archive ready: $OUTPUT_ARCHIVE"

printf '%s\n' "$OUTPUT_ARCHIVE"
