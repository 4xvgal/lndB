#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF_FILE="${CONF_FILE:-$SCRIPT_DIR/lndb.conf}"
TEST_WORK_DIR="${TEST_WORK_DIR:-$SCRIPT_DIR/tmp/test-encrypt}"
TEST_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_LOG_FILE="${TEST_LOG_FILE:-/dev/null}"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "[lndB-test] missing config: $CONF_FILE" >&2
  exit 1
fi

source "$SCRIPT_DIR/backup.sh"

error_handler() {
  local exit_code=$1
  local line=$2
  log "ERROR" "test_encrypt failed at line $line (exit $exit_code)"
  exit $exit_code
}

LOG_FILE="$TEST_LOG_FILE"
setup_logging
trap 'error_handler $? $LINENO' ERR

TEST_ARCHIVE="$TEST_WORK_DIR/test-$TEST_TIMESTAMP.tar.gz"
TEST_ENCRYPTED="$TEST_ARCHIVE.gpg"

require_binaries
prepare_gpg_material
build_src_targets
mkdir -p "$(dirname "$TEST_ARCHIVE")"

log "INFO" "creating test tarball at $TEST_ARCHIVE"
tar -czf "$TEST_ARCHIVE" --absolute-names "${SRC_TARGETS[@]}"

log "INFO" "encrypting test tarball for $GPG_ENCRYPT_TARGET"
gpg --batch --yes --trust-model always \
    --recipient "$GPG_ENCRYPT_TARGET" \
    --output "$TEST_ENCRYPTED" \
    --encrypt "$TEST_ARCHIVE"

log "INFO" "test encryption complete: $TEST_ENCRYPTED"
du -h "$TEST_ARCHIVE" "$TEST_ENCRYPTED" | while read -r size path; do
  log "INFO" "artifact size: $size $path"
done

echo "Test artifacts saved under $TEST_WORK_DIR" 1>&2
