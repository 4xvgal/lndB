#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CONF_FILE="${CONF_FILE:-$PROJECT_ROOT/lndb.conf}"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "[lndB-common] missing config: $CONF_FILE" >&2
  exit 1
fi

# shellcheck source=../lndb.conf
source "$CONF_FILE"

: "${GPG_KEY_SOURCE:=auto}"
: "${AUTO_INSTALL_MISSING_BINS:=false}"
: "${PACKAGE_MANAGER_OVERRIDE:=}"

say() {
  local prefix=${SCRIPT_NAME:-common}
  printf '%s [%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$prefix" "$*" >&2
}

fail() {
  say "ERROR: $*"
  exit 1
}

INSTALL_SUDO=""
DOWNLOAD_TOOL=""

setup_install_privilege() {
  if (( EUID == 0 )); then
    INSTALL_SUDO=""
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    INSTALL_SUDO="sudo"
    return
  fi
  fail "automatic package installation requires root privileges or sudo access"
}

run_with_privilege() {
  if [[ -n "$INSTALL_SUDO" ]]; then
    "$INSTALL_SUDO" "$@"
  else
    "$@"
  fi
}

detect_package_manager() {
  if [[ -n "$PACKAGE_MANAGER_OVERRIDE" ]]; then
    echo "$PACKAGE_MANAGER_OVERRIDE"
    return 0
  fi
  local candidates=(apt-get apt apk dnf yum pacman zypper)
  local mgr
  for mgr in "${candidates[@]}"; do
    if command -v "$mgr" >/dev/null 2>&1; then
      echo "$mgr"
      return 0
    fi
  done
  return 1
}

package_for_bin() {
  local bin=$1 mgr=$2
  case "$mgr" in
    apt-get|apt)
      case "$bin" in
        gpg) echo "gnupg" ;;
        curl) echo "curl" ;;
        wget) echo "wget" ;;
        tar) echo "tar" ;;
        gzip) echo "gzip" ;;
        *) echo "$bin" ;;
      esac
      ;;
    apk)
      case "$bin" in
        gpg) echo "gnupg" ;;
        curl) echo "curl" ;;
        wget) echo "wget" ;;
        tar) echo "tar" ;;
        gzip) echo "gzip" ;;
        *) echo "$bin" ;;
      esac
      ;;
    dnf|yum)
      case "$bin" in
        gpg) echo "gnupg2" ;;
        curl) echo "curl" ;;
        wget) echo "wget" ;;
        tar) echo "tar" ;;
        gzip) echo "gzip" ;;
        *) echo "$bin" ;;
      esac
      ;;
    pacman)
      case "$bin" in
        gpg) echo "gnupg" ;;
        curl) echo "curl" ;;
        wget) echo "wget" ;;
        tar) echo "tar" ;;
        gzip) echo "gzip" ;;
        *) echo "$bin" ;;
      esac
      ;;
    zypper)
      case "$bin" in
        gpg) echo "gnupg2" ;;
        curl) echo "curl" ;;
        wget) echo "wget" ;;
        tar) echo "tar" ;;
        gzip) echo "gzip" ;;
        *) echo "$bin" ;;
      esac
      ;;
    *)
      echo "$bin"
      ;;
  esac
}

run_install_command() {
  local mgr=$1; shift
  local packages=("$@")
  say "installing packages via $mgr: ${packages[*]}"
  case "$mgr" in
    apt-get|apt)
      run_with_privilege apt-get update
      DEBIAN_FRONTEND=noninteractive run_with_privilege apt-get install -y "${packages[@]}"
      ;;
    apk)
      run_with_privilege apk update
      run_with_privilege apk add --no-cache "${packages[@]}"
      ;;
    dnf|yum)
      run_with_privilege "$mgr" install -y "${packages[@]}"
      ;;
    pacman)
      run_with_privilege pacman -Sy --noconfirm "${packages[@]}"
      ;;
    zypper)
      run_with_privilege zypper --non-interactive install --no-recommends "${packages[@]}"
      ;;
    *)
      fail "unsupported package manager: $mgr"
      ;;
  esac
}

install_missing_binaries() {
  local bins=("$@")
  local mgr
  if ! mgr=$(detect_package_manager); then
    fail "cannot detect package manager for automatic installs; install manually: ${bins[*]}"
  fi
  setup_install_privilege
  local packages=()
  declare -A seen=()
  local bin pkg
  for bin in "${bins[@]}"; do
    pkg=$(package_for_bin "$bin" "$mgr")
    [[ -z "$pkg" ]] && continue
    if [[ -z "${seen[$pkg]:-}" ]]; then
      seen[$pkg]=1
      packages+=("$pkg")
    fi
  done
  (( ${#packages[@]} )) || fail "unable to map packages for missing binaries: ${bins[*]}"
  run_install_command "$mgr" "${packages[@]}"
}

require_bins() {
  local bins=("$@")
  local missing=()
  local bin
  for bin in "${bins[@]}"; do
    command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
  done
  if (( ${#missing[@]} )); then
    if [[ "$AUTO_INSTALL_MISSING_BINS" == "true" ]]; then
      install_missing_binaries "${missing[@]}"
      missing=()
      for bin in "${bins[@]}"; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
      done
    fi
  fi
  (( ${#missing[@]} )) && fail "missing required binaries: ${missing[*]}"
}

resolve_path() {
  local raw=$1
  [[ -z "$raw" ]] && return 0
  local expanded
  expanded=$(eval "printf '%s' \"$raw\"")
  printf '%s\n' "$expanded"
}

determine_recipient() {
  if [[ -n "${GPG_RECIPIENT_FINGERPRINT:-}" ]]; then
    echo "$GPG_RECIPIENT_FINGERPRINT"
    return
  fi
  if [[ -n "${GPG_RECIPIENT:-}" ]]; then
    echo "$GPG_RECIPIENT"
    return
  fi
  fail "configure GPG_RECIPIENT or GPG_RECIPIENT_FINGERPRINT"
}

determine_key_fetch_id() {
  if [[ -n "${GPG_KEY_ID:-}" ]]; then
    echo "$GPG_KEY_ID"
    return
  fi
  if [[ -n "${GPG_RECIPIENT_FINGERPRINT:-}" ]]; then
    echo "$GPG_RECIPIENT_FINGERPRINT"
    return
  fi
  if [[ -n "${GPG_RECIPIENT:-}" ]]; then
    echo "$GPG_RECIPIENT"
    return
  fi
  fail "unable to determine key identifier for fetch"
}

ensure_download_tool() {
  [[ -n "$DOWNLOAD_TOOL" ]] && return
  if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_TOOL="curl"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    DOWNLOAD_TOOL="wget"
    return
  fi
  if [[ "$AUTO_INSTALL_MISSING_BINS" == "true" ]]; then
    install_missing_binaries curl
    if command -v curl >/dev/null 2>&1; then
      DOWNLOAD_TOOL="curl"
      return
    fi
    install_missing_binaries wget
    if command -v wget >/dev/null 2>&1; then
      DOWNLOAD_TOOL="wget"
      return
    fi
  fi
  fail "curl or wget is required to download a GPG key"
}

download_key_from_url() {
  local url=$1 dest=$2
  ensure_download_tool
  say "downloading GPG key from URL: $url"
  case "$DOWNLOAD_TOOL" in
    curl) curl -fsSL "$url" -o "$dest" ;;
    wget) wget -qO "$dest" "$url" ;;
    *) fail "unsupported download tool: $DOWNLOAD_TOOL" ;;
  esac
}

import_key_from_file() {
  local file=$1
  [[ -z "$file" ]] && return 1
  [[ -f "$file" ]] || fail "GPG_PUBLIC_KEY_FILE not found: $file"
  say "importing GPG key from file: $file"
  gpg --batch --yes --import "$file"
}

import_key_from_url() {
  local url=$1
  [[ -z "$url" ]] && return 1
  local tmp
  tmp=$(mktemp)
  download_key_from_url "$url" "$tmp"
  gpg --batch --yes --import "$tmp"
  rm -f "$tmp"
}

import_key_from_keyserver() {
  local server=$1
  [[ -z "$server" ]] && return 1
  local key_id
  key_id=$(determine_key_fetch_id)
  say "fetching GPG key $key_id from keyserver $server"
  gpg --keyserver "$server" --recv-keys "$key_id"
}

maybe_import_key() {
  local source="${GPG_KEY_SOURCE:-auto}"
  local normalized
  normalized=$(echo "$source" | tr '[:upper:]' '[:lower:]')
  case "$normalized" in
    existing|"")
      say "GPG_KEY_SOURCE=$normalized: assuming key already exists"
      ;;
    file)
      import_key_from_file "${GPG_PUBLIC_KEY_FILE:-}" || fail "file import failed"
      ;;
    keyserver)
      import_key_from_keyserver "${GPG_KEYSERVER:-}" || fail "keyserver import failed"
      ;;
    url)
      import_key_from_url "${GPG_KEY_URL:-}" || fail "URL import failed"
      ;;
    auto)
      if [[ -n "${GPG_PUBLIC_KEY_FILE:-}" ]]; then
        import_key_from_file "$GPG_PUBLIC_KEY_FILE" || fail "file import failed"
      elif [[ -n "${GPG_KEYSERVER:-}" ]]; then
        import_key_from_keyserver "$GPG_KEYSERVER" || fail "keyserver import failed"
      elif [[ -n "${GPG_KEY_URL:-}" ]]; then
        import_key_from_url "$GPG_KEY_URL" || fail "URL import failed"
      else
        say "GPG_KEY_SOURCE=auto with no import hints; skipping import"
      fi
      ;;
    *)
      fail "unsupported GPG_KEY_SOURCE: $GPG_KEY_SOURCE"
      ;;
  esac
}

recipient_has_key() {
  local recipient=$1
  gpg --list-keys "$recipient" >/dev/null 2>&1
}

ensure_gpg_key_ready() {
  local recipient
  recipient=$(determine_recipient)
  if recipient_has_key "$recipient"; then
    say "found GPG key for $recipient"
    GPG_ENCRYPT_TARGET="$recipient"
    return
  fi
  say "GPG key for $recipient not found; attempting import (source: $GPG_KEY_SOURCE)"
  maybe_import_key
  if recipient_has_key "$recipient"; then
    say "GPG key ready for $recipient"
    GPG_ENCRYPT_TARGET="$recipient"
    return
  fi
  fail "GPG key still missing after import attempts for $recipient"
}

build_targets() {
  SRC_TARGETS=()
  local resolved_base=""
  if [[ -n "${BASE_CHAIN_DIR:-}" ]]; then
    resolved_base=$(resolve_path "$BASE_CHAIN_DIR")
    resolved_base=${resolved_base%/}
  fi

  local need_base=0
  if [[ ${RELATIVE_FILE_TARGETS[@]+_} ]]; then
    (( ${#RELATIVE_FILE_TARGETS[@]} )) && need_base=1
  fi
  if [[ ${RELATIVE_DIR_TARGETS[@]+_} ]]; then
    (( ${#RELATIVE_DIR_TARGETS[@]} )) && need_base=1
  fi

  if (( need_base )) && [[ -z "$resolved_base" ]]; then
    fail "BASE_CHAIN_DIR must be set when using relative targets"
  fi

  local rel
  if [[ ${RELATIVE_FILE_TARGETS[@]+_} ]]; then
    for rel in "${RELATIVE_FILE_TARGETS[@]}"; do
      [[ -z "$rel" ]] && continue
      SRC_TARGETS+=("$resolved_base/${rel#/}")
    done
  fi
  if [[ ${RELATIVE_DIR_TARGETS[@]+_} ]]; then
    for rel in "${RELATIVE_DIR_TARGETS[@]}"; do
      [[ -z "$rel" ]] && continue
      SRC_TARGETS+=("$resolved_base/${rel#/}")
    done
  fi
  if [[ ${EXTRA_TARGETS[@]+_} ]]; then
    for rel in "${EXTRA_TARGETS[@]}"; do
      [[ -z "$rel" ]] && continue
      SRC_TARGETS+=("$(resolve_path "$rel")")
    done
  fi

  [[ -z "${SRC_TARGETS[*]:-}" ]] && fail "no backup targets defined"
}
