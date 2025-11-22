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

#load conf File
#(GPG_KEY_ID, SOURCE_PATH, BACKUP_DIR)
#shellcheck source=/dev/null
. "$CONFIG_FILE"

#Checking variables set (unset = error)
: "${GPG_KEY_ID:?GPG_KEY_ID is not set in $CONFIG_FILE}"
: "${SOURCE_PATH:?SOURCE_PATH is not set in $CONFIG_FILE}"
: "${BACKUP_DIR:?BACKUP_DIR is not set in $CONFIG_FILE}"


# SOURCE_FILES array check 
if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
    echo "Error: SOURCE_FILES is empty"
    exit 1
fi
#check each file exist

for file in "${SOURCE_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Error: file not found: $file"
        exit 1
    fi
done

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

# 압축 파일 이름
TAR_NAME="${TIMESTAMP}_backup.tar.gz"
TAR_PATH="${BACKUP_DIR}/${TAR_NAME}"

# 암호화 파일 이름
ENC_PATH="${TAR_PATH}.gpg"

echo "1) tar.gz 압축 중..."

# tar 에 여러 파일을 전달
tar -czf "$TAR_PATH" "${SOURCE_FILES[@]}"

echo "2) GPG 암호화 중..."
gpg --batch --yes \
    --output "$ENC_PATH" \
    --encrypt --recipient "$GPG_KEY_ID" \
    "$TAR_PATH"

# 평문 tar 삭제 (원하면 비활성화 가능)
rm -f "$TAR_PATH"

echo "완료:"
echo "암호화 파일: $ENC_PATH"