#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF_FILE="${CONF_FILE:-$SCRIPT_DIR/lndb.conf}"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "[lndB] missing config: $CONF_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONF_FILE"

: "${GPG_KEY_SOURCE:=auto}"
AUTO_INSTALL_MISSING_BINS=${AUTO_INSTALL_MISSING_BINS:-false}
PACKAGE_MANAGER_OVERRIDE=${PACKAGE_MANAGER_OVERRIDE:-}

log() {
  local level=$1; shift
  local msg="$*"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s [%s] %s\n' "$ts" "$level" "$msg" | tee -a "$LOG_FILE" >&3
}

fail() {
  log "ERROR" "$*"
  exit 1
}

handle_error() {
  local exit_code=$1
  local line=$2
  fail "backup failed at line $line (exit $exit_code)"
}
 
INSTALL_SUDO=""
GPG_ENCRYPT_TARGET=""
DOWNLOAD_TOOL=""
SRC_TARGETS=()

setup_logging() {
  LOG_FILE=${LOG_FILE:-$SCRIPT_DIR/logs/lndb.log}
  if [[ "$LOG_FILE" != "/dev/null" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
  fi
  exec 3>>"$LOG_FILE"
}

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
  local bin=$1
  local mgr=$2
  case "$mgr" in
    apt-get|apt)
      case "$bin" in
        gpg) echo "gnupg" ;;
        scp) echo "openssh-client" ;;
        mountpoint) echo "util-linux" ;;
        find|xargs) echo "findutils" ;;
        *) echo "$bin" ;;
      esac
      ;;
    apk)
      case "$bin" in
        gpg) echo "gnupg" ;;
        scp) echo "openssh-client" ;;
        mountpoint) echo "util-linux" ;;
        find|xargs) echo "findutils" ;;
        *) echo "$bin" ;;
      esac
      ;;
    dnf|yum)
      case "$bin" in
        gpg) echo "gnupg2" ;;
        scp) echo "openssh-clients" ;;
        mountpoint) echo "util-linux" ;;
        find|xargs) echo "findutils" ;;
        *) echo "$bin" ;;
      esac
      ;;
    pacman)
      case "$bin" in
        gpg) echo "gnupg" ;;
        scp) echo "openssh" ;;
        mountpoint) echo "util-linux" ;;
        find|xargs) echo "findutils" ;;
        *) echo "$bin" ;;
      esac
      ;;
    zypper)
      case "$bin" in
        gpg) echo "gnupg2" ;;
        scp) echo "openssh-clients" ;;
        mountpoint) echo "util-linux" ;;
        find|xargs) echo "findutils" ;;
        *) echo "$bin" ;;
      esac
      ;;
    *)
      echo "$bin"
      ;;
  esac
}

run_install_command() {
  local mgr=$1
  shift
  local packages=("$@")
  log "INFO" "installing packages (${packages[*]}) via $mgr"
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

  if (( ${#packages[@]} == 0 )); then
    fail "unable to map packages for missing binaries: ${bins[*]}"
  fi

  run_install_command "$mgr" "${packages[@]}"
}

resolve_path() {
  local raw=$1
  [[ -z "$raw" ]] && return 0
  local expanded
  expanded=$(eval "printf '%s' \"$raw\"")
  printf '%s\n' "$expanded"
}

determine_gpg_recipient() {
  if [[ -n "$GPG_RECIPIENT_FINGERPRINT" ]]; then
    echo "$GPG_RECIPIENT_FINGERPRINT"
    return
  fi
  if [[ -n "$GPG_RECIPIENT" ]]; then
    echo "$GPG_RECIPIENT"
    return
  fi
  fail "configure GPG_RECIPIENT or GPG_RECIPIENT_FINGERPRINT for encryption"
}

determine_key_fetch_id() {
  if [[ -n "$GPG_KEY_ID" ]]; then
    echo "$GPG_KEY_ID"
    return
  fi
  if [[ -n "$GPG_RECIPIENT_FINGERPRINT" ]]; then
    echo "$GPG_RECIPIENT_FINGERPRINT"
    return
  fi
  if [[ -n "$GPG_RECIPIENT" ]]; then
    echo "$GPG_RECIPIENT"
    return
  fi
  fail "unable to determine key identifier for fetch"
}

import_gpg_key_from_file() {
  local file=$1
  [[ -z "$file" ]] && return 0
  [[ -f "$file" ]] || fail "GPG_PUBLIC_KEY_FILE not found: $file"
  log "INFO" "importing GPG key from file $file"
  gpg --batch --yes --import "$file"
}

ensure_download_tool() {
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
  fail "curl or wget is required to download GPG keys via URL"
}

download_key_from_url() {
  local url=$1
  local dest=$2
  ensure_download_tool
  log "INFO" "downloading GPG key from URL $url"
  case "$DOWNLOAD_TOOL" in
    curl)
      curl -fsSL "$url" -o "$dest"
      ;;
    wget)
      wget -qO "$dest" "$url"
      ;;
    *)
      fail "unsupported download tool: $DOWNLOAD_TOOL"
      ;;
  esac
}

import_gpg_key_from_url() {
  local url=$1
  [[ -z "$url" ]] && return 0
  local tmp
  tmp=$(mktemp)
  download_key_from_url "$url" "$tmp"
  gpg --batch --yes --import "$tmp"
  rm -f "$tmp"
}

fetch_gpg_key_from_server() {
  local server=$1
  [[ -z "$server" ]] && return 0
  local key_id
  key_id=$(determine_key_fetch_id)
  log "INFO" "fetching GPG key $key_id from keyserver $server"
  gpg --keyserver "$server" --recv-keys "$key_id"
}

perform_gpg_key_import() {
  local source=${GPG_KEY_SOURCE:-auto}
  local normalized
  normalized=$(echo "$source" | tr '[:upper:]' '[:lower:]')
  case "$normalized" in
    existing|"")
      log "INFO" "GPG_KEY_SOURCE=$source, assuming key already imported"
      ;;
    file)
      [[ -n "$GPG_PUBLIC_KEY_FILE" ]] || fail "set GPG_PUBLIC_KEY_FILE when GPG_KEY_SOURCE=file"
      import_gpg_key_from_file "$GPG_PUBLIC_KEY_FILE"
      ;;
    keyserver)
      [[ -n "$GPG_KEYSERVER" ]] || fail "set GPG_KEYSERVER when GPG_KEY_SOURCE=keyserver"
      fetch_gpg_key_from_server "$GPG_KEYSERVER"
      ;;
    url)
      [[ -n "$GPG_KEY_URL" ]] || fail "set GPG_KEY_URL when GPG_KEY_SOURCE=url"
      import_gpg_key_from_url "$GPG_KEY_URL"
      ;;
    auto)
      if [[ -n "$GPG_PUBLIC_KEY_FILE" ]]; then
        import_gpg_key_from_file "$GPG_PUBLIC_KEY_FILE"
      elif [[ -n "$GPG_KEYSERVER" ]]; then
        fetch_gpg_key_from_server "$GPG_KEYSERVER"
      elif [[ -n "$GPG_KEY_URL" ]]; then
        import_gpg_key_from_url "$GPG_KEY_URL"
      else
        log "INFO" "GPG_KEY_SOURCE=auto with no import inputs; assuming key already imported"
      fi
      ;;
    *)
      fail "unsupported GPG_KEY_SOURCE: $GPG_KEY_SOURCE"
      ;;
  esac
}

prepare_gpg_material() {
  perform_gpg_key_import
  GPG_ENCRYPT_TARGET=$(determine_gpg_recipient)
}

build_src_targets() {
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
}

require_binaries() {
  local missing=()
  local bin
  for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing+=("$bin")
    fi
  done
  if (( ${#missing[@]} )); then
    if [[ "$AUTO_INSTALL_MISSING_BINS" == "true" ]]; then
      log "INFO" "missing binaries detected: ${missing[*]} (attempting automatic install)"
      install_missing_binaries "${missing[@]}"
      missing=()
      for bin in "${REQUIRED_BINS[@]}"; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
      done
    fi
  fi

  if (( ${#missing[@]} )); then
    fail "missing required binaries after install attempt: ${missing[*]}"
  fi
}

prepare_workspace() {
  mkdir -p "$WORK_DIR"
  TMP_ARCHIVE="$WORK_DIR/${ARCHIVE_PREFIX}-$(date +%Y%m%d-%H%M%S).tar.gz"
  TMP_ENCRYPTED="$TMP_ARCHIVE.gpg"
}

create_archive() {
  if [[ -z "${SRC_TARGETS[*]:-}" ]]; then
    fail "SRC_TARGETS is empty; configure at least one path to back up"
  fi
  log "INFO" "creating tarball at $TMP_ARCHIVE"
  tar -czf "$TMP_ARCHIVE" --absolute-names "${SRC_TARGETS[@]}"
}

encrypt_archive() {
  log "INFO" "encrypting archive for recipient $GPG_ENCRYPT_TARGET"
  gpg --batch --yes --trust-model always \
      --recipient "$GPG_ENCRYPT_TARGET" \
      --output "$TMP_ENCRYPTED" \
      --encrypt "$TMP_ARCHIVE"
}

store_local() {
  mkdir -p "$LOCAL_TARGET"
  cp "$TMP_ENCRYPTED" "$LOCAL_TARGET/"
  log "INFO" "stored encrypted archive locally"
}

ensure_mount_ready() {
  if [[ -z "$MOUNT_TARGET" ]]; then
    log "INFO" "mount target not configured; skipping"
    return 0
  fi

  if ! mountpoint -q "$MOUNT_TARGET"; then
    fail "mount target $MOUNT_TARGET is not mounted"
  fi
}

store_mount() {
  [[ -z "$MOUNT_TARGET" ]] && return 0
  ensure_mount_ready
  mkdir -p "$MOUNT_TARGET"
  cp "$TMP_ENCRYPTED" "$MOUNT_TARGET/"
  log "INFO" "stored archive on mount"
}

transfer_remote() {
  [[ -z "$REMOTE_HOST" ]] && return 0

  scp "$TMP_ENCRYPTED" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"
  log "INFO" "remote transfer complete via scp"
}

apply_retention() {
  local target=$1
  local days=$2
  [[ -z "$target" || -z "$days" ]] && return 0
  find "$target" -type f -name "${ARCHIVE_PREFIX}*.tar.gz.gpg" -mtime +"$days" -print0 \
    | xargs -0r rm -f
  log "INFO" "applied retention ($days days) on $target"
}

cleanup() {
  rm -f "$TMP_ARCHIVE"
}

main() {
  setup_logging
  trap 'handle_error $? $LINENO' ERR
  require_binaries
  prepare_gpg_material
  build_src_targets
  prepare_workspace
  create_archive
  encrypt_archive
  store_local
  store_mount
  transfer_remote
  apply_retention "$LOCAL_TARGET" "$RETENTION_DAYS_LOCAL"
  [[ -n "$MOUNT_TARGET" ]] && apply_retention "$MOUNT_TARGET" "$RETENTION_DAYS_MOUNT"
  cleanup
  log "INFO" "backup completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
