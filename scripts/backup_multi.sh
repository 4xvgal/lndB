#!/usr/bin/env bash

set -euo pipefail

########################################
# 1. 설정 파일 로드
########################################

# 스크립트 위치 기준으로 conf 찾기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/lndB.conf"   # 파일 이름 확인해서 맞게 수정할 것

# conf 존재 확인
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config file not found: $CONFIG_FILE"
    exit 1
fi

# conf 로드
# (필요 변수: GPG_KEY_ID, SOURCE_PATH, BACKUP_DIR, SOURCE_FILES)
# shellcheck source=/dev/null
. "$CONFIG_FILE"

########################################
# 2. 설정 값 검증
########################################

: "${GPG_KEY_ID:?GPG_KEY_ID is not set in $CONFIG_FILE}"
: "${SOURCE_PATH:?SOURCE_PATH is not set in $CONFIG_FILE}"
: "${BACKUP_DIR:?BACKUP_DIR is not set in $CONFIG_FILE}"

# SOURCE_FILES 배열 비어 있는지 확인
if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
    echo "Error: SOURCE_FILES is empty in $CONFIG_FILE"
    exit 1
fi

# SOURCE_PATH 디렉터리 확인
if [ ! -d "$SOURCE_PATH" ]; then
    echo "Error: SOURCE_PATH directory not found: $SOURCE_PATH"
    exit 1
fi

# BACKUP_DIR 디렉터리 없으면 생성
if [ ! -d "$BACKUP_DIR" ]; then
    echo "백업 디렉토리가 없어 생성합니다: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

# GPG 키 존재 여부 확인
if ! gpg --list-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
    echo "Error: GPG public key not found: $GPG_KEY_ID"
    exit 1
fi

########################################
# 3. 백업 대상 파일 확인
########################################

# SOURCE_PATH 끝 슬래시 제거
SRC_DIR="${SOURCE_PATH%/}"

# tar에 넣을 상대 경로(=SOURCE_FILES 그대로) 목록을 쓸 예정이라,
# 여기서는 존재 여부만 절대 경로로 체크.
for file in "${SOURCE_FILES[@]}"; do
    src_file="${SRC_DIR}/${file}"
    if [ ! -f "$src_file" ]; then
        echo "Error: file not found: $src_file"
        exit 1
    fi
done

########################################
# 4. tar + gpg 암호화 백업
########################################

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="${TIMESTAMP}_lnd_backup.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR%/}/${ARCHIVE_NAME}"
ENCRYPTED_PATH="${ARCHIVE_PATH}.gpg"

echo "백업 생성 중..."
echo "  SOURCE_PATH : $SRC_DIR"
echo "  FILES       : ${SOURCE_FILES[*]}"
echo "  ARCHIVE     : $ARCHIVE_PATH"
echo "  ENCRYPTED   : $ENCRYPTED_PATH"

# tar 생성 (SOURCE_PATH를 기준 디렉토리로 해서 상대 경로만 포함)
tar -czf "$ARCHIVE_PATH" -C "$SRC_DIR" "${SOURCE_FILES[@]}"

# gpg 암호화
gpg --yes --output "$ENCRYPTED_PATH" --encrypt --recipient "$GPG_KEY_ID" "$ARCHIVE_PATH"

# 원본 tar 제거 (암호화 파일만 남기고 싶을 때)
rm -f "$ARCHIVE_PATH"

echo "완료: 암호화 백업 생성됨 -> $ENCRYPTED_PATH"
