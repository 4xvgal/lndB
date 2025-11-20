#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="encrypt-archive"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_bins gpg
ensure_gpg_key_ready

INPUT_ARCHIVE=${1:-${INPUT_ARCHIVE:-}}
[[ -n "$INPUT_ARCHIVE" ]] || fail "provide archive path via argument or INPUT_ARCHIVE env"
[[ -f "$INPUT_ARCHIVE" ]] || fail "archive not found: $INPUT_ARCHIVE"

OUTPUT_ENCRYPTED=${OUTPUT_ENCRYPTED:-$INPUT_ARCHIVE.gpg}

say "encrypting $INPUT_ARCHIVE for $GPG_ENCRYPT_TARGET"
gpg --batch --yes --trust-model always \
    --recipient "$GPG_ENCRYPT_TARGET" \
    --output "$OUTPUT_ENCRYPTED" \
    --encrypt "$INPUT_ARCHIVE"

say "encryption complete: $OUTPUT_ENCRYPTED"
printf '%s\n' "$OUTPUT_ENCRYPTED"
