#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="key-prepare"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_bins gpg
ensure_gpg_key_ready
say "GPG key verification complete (recipient: $GPG_ENCRYPT_TARGET)"
