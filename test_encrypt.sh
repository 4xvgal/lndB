#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

KEY_SCRIPT="$SCRIPTS_DIR/key_prepare.sh"
ARCHIVE_SCRIPT="$SCRIPTS_DIR/create_archive.sh"
ENCRYPT_SCRIPT="$SCRIPTS_DIR/encrypt_archive.sh"

ts=$(date +%Y%m%d-%H%M%S)
TEST_ARCHIVE_PATH="${TEST_ARCHIVE_PATH:-$PROJECT_ROOT/tmp/test-$ts.tar.gz}"
TEST_ENCRYPTED_PATH="${TEST_ENCRYPTED_PATH:-$TEST_ARCHIVE_PATH.gpg}"

say() { printf '%s [test-flow] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"; }

ensure_script() {
  local script=$1
  [[ -x "$script" ]] || { echo "missing executable script: $script" >&2; exit 1; }
}

ensure_script "$KEY_SCRIPT"
ensure_script "$ARCHIVE_SCRIPT"
ensure_script "$ENCRYPT_SCRIPT"

say "verifying GPG key before encryption"
"$KEY_SCRIPT"

say "creating test archive at $TEST_ARCHIVE_PATH"
archive_path=$(OUTPUT_ARCHIVE="$TEST_ARCHIVE_PATH" "$ARCHIVE_SCRIPT")
say "archive generated: $archive_path"

say "encrypting test archive -> $TEST_ENCRYPTED_PATH"
encrypted_path=$(INPUT_ARCHIVE="$archive_path" OUTPUT_ENCRYPTED="$TEST_ENCRYPTED_PATH" "$ENCRYPT_SCRIPT")
say "encryption result: $encrypted_path"

du -h "$archive_path" "$encrypted_path" | while read -r size path; do
  say "artifact size: $size $path"
done
