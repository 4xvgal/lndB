#!/usr/bin/env bash

set -euo pipefail

#config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/lndB.conf"

#checking conf exist
if [ ! -f "$CONFIG_FILE" ]; then
	echo "Error: config file not found: $CONFIG_FILE"
	exit 1
fi

#loding conf File
#(GPG_KEY_ID, SOURCE_PATH, BACKUP_DIR)
#shellcheck source=/dev/null
. "$CONFIG_FILE"

#Checking variables set (unset = error)
: "${GPG_KEY_ID:?GPG_KEY_ID is not set in $CONFIG_FILE}"
: "${SOURCE_PATH:?SOURCE_PATH is not set in $CONFIG_FILE}"
: "${BACKUP_DIR:?BACKUP_DIR is not set in $CONFIG_FILE}"


#경로 유효성 체크
if [ ! -f "$SOURCE_PATH" ]; then
	echo "오류: 파일을 찾을 수 없습니다: $SOURCE_PATH"
	exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
	echo "오류: 백업 디렉토리가 존재하지 않습니다 : $BACKUP_DIR"
	exit  1
fi

#GPG 키 존재 여부 체크 (선택, 권장)
if ! gpg --list-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
	echo "error: GPG pubkey not found: $GPG_KEY_ID"
	exit 1
fi

# prefix

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

#원본 파일 이름만 추출
BASENAME="$(basename "$SOURCE_PATH")"

#압축 파일 및 암호화 파일 이름 구성
TAR_NAME="${TIMESTAMP}_${BASENAME}.tar.gz"
TAR_PATH="${BACKUP_DIR}/${TAR_NAME}"

ENC_NAME="${TAR_NAME}.gpg"
ENC_PATH="${BACKUP_DIR}/${ENC_NAME}"

echo "1) tar.gz 압축 중 ..."
tar -czf "$TAR_PATH" -C "$(dirname "$SOURCE_PATH")" "$BASENAME"

echo "2) encrytping using gpg pubkey..."
gpg --output "$ENC_PATH" --encrypt --recipient "$GPG_KEY_ID" "$TAR_PATH"

echo "완료:"
echo "암호화 파일: $ENC_PATH"