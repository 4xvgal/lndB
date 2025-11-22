#!/usr/bin/env bash

set -euo pipefail

GPG_KEY_ID="$1"
SOURCE_PATH="$2"
BACKUP_DIR="$3"

# Path validity check
if [ ! -f "$SOURCE_PATH" ]; then
        echo "Error: File not found: $SOURCE_PATH"
        exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
        echo "Error: Backup directory does not exist : $BACKUP_DIR"
        exit  1
fi

# GPG key existence check (optional, recommended)
if ! gpg --list-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
        echo "error: GPG pubkey not found: $GPG_KEY_ID"
        exit 1
fi

# Prefix

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Extract the base name of the original file
BASENAME="$(basename "$SOURCE_PATH")"

# Construct the names for the compressed and encrypted files
TAR_NAME="${TIMESTAMP}_${BASENAME}.tar.gz"
TAR_PATH="${BACKUP_DIR}/${TAR_NAME}"

ENC_NAME="${TAR_NAME}.gpg"
ENC_PATH="${BACKUP_DIR}/${ENC_NAME}"

echo "1) Compressing to tar.gz ..."
tar -czf "$TAR_PATH" -C "$(dirname "$SOURCE_PATH")" "$BASENAME"

echo "2) Encrypting using gpg pubkey..."
gpg --output "$ENC_PATH" --encrypt --recipient "$GPG_KEY_ID" "$TAR_PATH"

echo "Completed:"
echo "Encrypted file: $ENC_PATH"
