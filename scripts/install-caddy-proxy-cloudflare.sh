#!/usr/bin/env bash
set -Eeuo pipefail

REPO="sholdee/caddy-proxy-cloudflare"
PROJECT="caddy-proxy-cloudflare"
SERVICE="caddy"
BACKUP_DIR="/var/backups/caddy-proxy-cloudflare"
DEFAULT_TARGET="/usr/local/bin/caddy"
CONFIG_PATH="/etc/caddy/Caddyfile"
UNIT_PATH="/etc/systemd/system/caddy.service"

ACTION="install"
VERSION=""
TARGET=""
RESTORE_PATH=""
ASSET=""
WORKDIR=""
COSIGN_STATUS="not checked"
IDLE_INTERVAL="5m"
IDLE_PORTS="80,443"
IDLE_QUIET="2m"
IDLE_TIMEOUT="2h"

DRY_RUN=false
FORCE_SERVICE=false
IF_OUTDATED=false
INSTALL_SERVICE=false
LIST_MODULES=false
NO_RESTART=false
REQUIRE_COSIGN=false
START_SERVICE=false
AUTO_YES=false
WAIT_IDLE=false
WRITE_DEFAULT_CADDYFILE=false

IDLE_INTERVAL_SET=false
IDLE_PORTS_SET=false
IDLE_QUIET_SET=false
IDLE_TIMEOUT_SET=false

SUDO=()

usage() {
  cat <<'EOF'
Install, update, or restore the caddy-proxy-cloudflare host binary.

Usage:
  install-caddy-proxy-cloudflare.sh [options]
  install-caddy-proxy-cloudflare.sh restore [backup-path] [options]
  install-caddy-proxy-cloudflare.sh list-backups

Options:
  --version <tag>              Install a specific release tag instead of latest
  --target <path>              Install or restore to a specific caddy binary path
  --dry-run                    Download and verify only; do not install or restart
  --if-outdated                Exit without changes when the installed binary matches the selected release
  --wait-idle                  Before updating, wait until watched Caddy ports have no recent TCP activity
  --idle-timeout <duration>    Maximum time to wait for idle connections (default: 2h)
  --idle-interval <duration>   Delay between idle checks (default: 5m)
  --idle-quiet <duration>      Treat connections as idle after no send/receive activity (default: 2m)
  --idle-ports <csv>           Local TCP ports to watch for established connections (default: 80,443)
  --require-cosign             Fail if cosign verification cannot be completed
  --install-service            Install a Caddyfile-based systemd caddy.service
  --force-service              Overwrite an existing caddy.service with --install-service
  --write-default-caddyfile    Create a safe placeholder /etc/caddy/Caddyfile if missing
  --start                      Start caddy.service when it exists but is inactive
  --no-restart                 Do not restart or start caddy.service
  -y, --yes                    Accept prompts and run non-interactively
  --list-modules               Print installed Caddy modules after install or restore
  -h, --help                   Show this help

Examples:
  ./install-caddy-proxy-cloudflare.sh
  ./install-caddy-proxy-cloudflare.sh --version v2026.509.50351
  ./install-caddy-proxy-cloudflare.sh --yes --if-outdated --wait-idle
  ./install-caddy-proxy-cloudflare.sh --install-service
  ./install-caddy-proxy-cloudflare.sh restore
  ./install-caddy-proxy-cloudflare.sh restore /var/backups/caddy-proxy-cloudflare/caddy.20260509T120000Z
EOF
}

log() { printf " %s\n" "$*"; }
ok() { printf " %s\n" "$*"; }
warn() { printf "  %s\n" "$*" >&2; }
err() { printf " %s\n" "$*" >&2; }

cleanup() {
  if [[ -n "${WORKDIR}" && -d "${WORKDIR}" ]]; then
    rm -rf "${WORKDIR}"
  fi
}

trap cleanup EXIT

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local answer
  local suffix

  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi

  if ! { : </dev/tty >/dev/tty; } 2>/dev/null; then
    return 1
  fi

  if [[ "${default}" == "yes" ]]; then
    suffix="[Y/n]"
    printf "%s %s " "${prompt}" "${suffix}" >/dev/tty
    IFS= read -r answer </dev/tty || return 1
    [[ -z "${answer}" || "${answer}" =~ ^[Yy]$ ]]
  else
    suffix="[y/N]"
    printf "%s %s " "${prompt}" "${suffix}" >/dev/tty
    IFS= read -r answer </dev/tty || return 1
    [[ "${answer}" =~ ^[Yy]$ ]]
  fi
}

confirm_or_exit() {
  local prompt="$1"

  if [[ "${AUTO_YES}" == "true" ]]; then
    ok "Continuing because --yes was set."
    return 0
  fi

  if ! { : </dev/tty >/dev/tty; } 2>/dev/null; then
    err "Refusing to modify the system without an interactive terminal or --yes."
    err "For interactive installs, run from a terminal: curl -fsSL https://cpcf.shold.io | bash"
    err "For automation, use: curl -fsSL https://cpcf.shold.io | bash -s -- --yes"
    exit 1
  fi

  if ! prompt_yes_no "${prompt}" yes; then
    err "Aborted."
    exit 1
  fi
}

set_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO=()
  else
    SUDO=(sudo)
  fi
}

require_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    err "This operation requires root privileges, but sudo is not available."
    exit 1
  fi
  sudo -v
}

detect_target_asset() {
  local os raw_arch arch

  case "$(uname -s)" in
    Linux) os="linux" ;;
    *)
      err "Unsupported OS: $(uname -s). This installer only supports Linux."
      exit 1
      ;;
  esac

  raw_arch="$(uname -m)"
  case "${raw_arch}" in
    amd64|x86_64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      err "Unsupported architecture: ${raw_arch}. Supported architectures: amd64, arm64."
      exit 1
      ;;
  esac

  ASSET="${PROJECT}-${os}-${arch}"
  log "Detected target ${os}/${arch}"
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf "apt-get"
  elif command -v dnf >/dev/null 2>&1; then
    printf "dnf"
  elif command -v yum >/dev/null 2>&1; then
    printf "yum"
  elif command -v pacman >/dev/null 2>&1; then
    printf "pacman"
  elif command -v apk >/dev/null 2>&1; then
    printf "apk"
  fi
}

install_required_packages() {
  local manager="$1"

  require_sudo
  case "${manager}" in
    apt-get)
      "${SUDO[@]}" apt-get update
      "${SUDO[@]}" apt-get install -y curl jq coreutils tar
      ;;
    dnf)
      "${SUDO[@]}" dnf install -y curl jq coreutils tar
      ;;
    yum)
      "${SUDO[@]}" yum install -y curl jq coreutils tar
      ;;
    pacman)
      "${SUDO[@]}" pacman -Sy --noconfirm curl jq coreutils tar
      ;;
    apk)
      "${SUDO[@]}" apk add --no-cache curl jq coreutils tar
      ;;
    *)
      return 1
      ;;
  esac
}

missing_required_tools() {
  local missing=()

  for cmd in basename chmod curl date dirname find grep install jq mktemp sort stat tail tar uname; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    missing+=("sha256sum-or-shasum")
  fi

  printf "%s\n" "${missing[@]}"
}

ensure_required_tools() {
  local missing manager

  missing="$(missing_required_tools)"
  if [[ -z "${missing}" ]]; then
    return 0
  fi

  warn "Missing required tools:"
  printf "%s\n" "${missing}" >&2

  manager="$(detect_package_manager)"
  if [[ -n "${manager}" ]] && prompt_yes_no "Install required packages with ${manager}?" yes; then
    install_required_packages "${manager}"
  else
    err "Install the missing tools and run this script again."
    exit 1
  fi

  missing="$(missing_required_tools)"
  if [[ -n "${missing}" ]]; then
    err "Required tools are still missing after package installation:"
    printf "%s\n" "${missing}" >&2
    exit 1
  fi
}

ensure_required_tools_no_install() {
  local missing

  missing="$(missing_required_tools)"
  if [[ -z "${missing}" ]]; then
    return 0
  fi

  err "Missing required tools:"
  printf "%s\n" "${missing}" >&2
  err "Dry-run will not install packages. Install the missing tools and run this script again."
  exit 1
}

install_ss_package() {
  local manager="$1"

  require_sudo
  case "${manager}" in
    apt-get)
      "${SUDO[@]}" apt-get update
      "${SUDO[@]}" apt-get install -y iproute2
      ;;
    dnf)
      "${SUDO[@]}" dnf install -y iproute
      ;;
    yum)
      "${SUDO[@]}" yum install -y iproute
      ;;
    pacman)
      "${SUDO[@]}" pacman -Sy --noconfirm iproute2
      ;;
    apk)
      "${SUDO[@]}" apk add --no-cache iproute2
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_idle_tools() {
  local manager

  if command -v ss >/dev/null 2>&1; then
    return 0
  fi

  warn "--wait-idle requires ss, but ss was not found."

  if [[ "${AUTO_YES}" == "true" || "${DRY_RUN}" == "true" ]]; then
    err "Install ss/iproute2 and run this command again."
    exit 1
  fi

  manager="$(detect_package_manager)"
  if [[ -n "${manager}" ]] && prompt_yes_no "Install ss/iproute2 with ${manager}?" yes; then
    install_ss_package "${manager}"
  else
    err "Install ss/iproute2 and run this command again."
    exit 1
  fi

  if ! command -v ss >/dev/null 2>&1; then
    err "ss is still unavailable after package installation."
    exit 1
  fi
}

hash_file() {
  local path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    if [[ -r "${path}" ]]; then
      sha256sum "${path}" | awk '{print $1}'
    else
      require_sudo
      "${SUDO[@]}" sha256sum "${path}" | awk '{print $1}'
    fi
  elif command -v shasum >/dev/null 2>&1; then
    if [[ -r "${path}" ]]; then
      shasum -a 256 "${path}" | awk '{print $1}'
    else
      require_sudo
      "${SUDO[@]}" shasum -a 256 "${path}" | awk '{print $1}'
    fi
  else
    err "sha256sum or shasum is required."
    exit 1
  fi
}

duration_seconds() {
  local raw="$1"
  local number unit

  if [[ "${raw}" =~ ^([0-9]+)([smh]?)$ ]]; then
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
  else
    err "Invalid duration: ${raw}. Use seconds, or suffix with s, m, or h."
    exit 1
  fi

  case "${unit}" in
    ""|s) printf "%s" "$((10#${number}))" ;;
    m) printf "%s" "$((10#${number} * 60))" ;;
    h) printf "%s" "$((10#${number} * 3600))" ;;
    *)
      err "Invalid duration unit: ${unit}"
      exit 1
      ;;
  esac
}

validate_idle_ports() {
  local raw="$1"
  local port
  local -a ports

  if [[ ! "${raw}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    err "Invalid --idle-ports value: ${raw}. Use a comma-separated list such as 80,443."
    exit 1
  fi

  IFS=',' read -r -a ports <<<"${raw}"
  for port in "${ports[@]}"; do
    if ((port < 1 || port > 65535)); then
      err "Invalid port in --idle-ports: ${port}"
      exit 1
    fi
  done
}

cosign_asset_arch() {
  case "$(uname -m)" in
    amd64|x86_64) printf "amd64" ;;
    arm64|aarch64) printf "arm64" ;;
    *)
      return 1
      ;;
  esac
}

install_cosign_optional() {
  local arch tmp url

  if command -v cosign >/dev/null 2>&1; then
    return 0
  fi

  if ! prompt_yes_no "Install latest cosign to /usr/local/bin/cosign?" yes; then
    return 1
  fi

  arch="$(cosign_asset_arch)" || {
    warn "Unsupported architecture for cosign installer."
    return 1
  }

  tmp="$(mktemp)"
  url="$(curl -fsSL https://api.github.com/repos/sigstore/cosign/releases/latest \
    | jq -r ".assets[] | select(.name == \"cosign-linux-${arch}\") | .browser_download_url")"

  if [[ -z "${url}" || "${url}" == "null" ]]; then
    rm -f "${tmp}"
    warn "Could not resolve cosign download URL."
    return 1
  fi

  curl -fsSL "${url}" -o "${tmp}"
  chmod 0755 "${tmp}"
  require_sudo
  "${SUDO[@]}" install -o root -g root -m 0755 "${tmp}" /usr/local/bin/cosign
  rm -f "${tmp}"
  ok "Installed cosign: $(command -v cosign)"
}

resolve_release() {
  local release_api release_json

  if [[ -n "${VERSION}" ]]; then
    release_api="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
  else
    release_api="https://api.github.com/repos/${REPO}/releases/latest"
  fi

  release_json="$(curl -fsSL "${release_api}")"
  TAG="$(jq -r '.tag_name' <<<"${release_json}")"

  if [[ -z "${TAG}" || "${TAG}" == "null" ]]; then
    err "Could not resolve release tag."
    exit 1
  fi

  ASSET_URL="$(jq -r --arg name "${ASSET}" '.assets[] | select(.name == $name) | .browser_download_url' <<<"${release_json}")"
  SUMS_URL="$(jq -r '.assets[] | select(.name == "checksums-sha256.txt") | .browser_download_url' <<<"${release_json}")"
  BUNDLE_URL="$(jq -r '.assets[] | select(.name == "checksums-sha256.txt.sigstore.json") | .browser_download_url' <<<"${release_json}")"

  for value in ASSET_URL SUMS_URL; do
    if [[ -z "${!value}" || "${!value}" == "null" ]]; then
      err "Missing release asset URL: ${value}"
      exit 1
    fi
  done

  if [[ "${REQUIRE_COSIGN}" == "true" && ( -z "${BUNDLE_URL}" || "${BUNDLE_URL}" == "null" ) ]]; then
    err "Missing release asset URL: BUNDLE_URL"
    exit 1
  fi
}

ensure_workdir() {
  if [[ -z "${WORKDIR}" ]]; then
    WORKDIR="$(mktemp -d)"
  fi
}

download_checksums() {
  ensure_workdir
  if [[ -f "${WORKDIR}/checksums-sha256.txt" ]]; then
    return 0
  fi

  log "Downloading checksum manifest for ${REPO} ${TAG}"
  curl -fsSL "${SUMS_URL}" -o "${WORKDIR}/checksums-sha256.txt"
}

download_assets() {
  ensure_workdir

  log "Downloading ${REPO} ${TAG}"
  curl -fsSL "${ASSET_URL}" -o "${WORKDIR}/${ASSET}"
  download_checksums
  if [[ -n "${BUNDLE_URL}" && "${BUNDLE_URL}" != "null" ]]; then
    curl -fsSL "${BUNDLE_URL}" -o "${WORKDIR}/checksums-sha256.txt.sigstore.json"
  fi
  chmod 0755 "${WORKDIR}/${ASSET}"
  ok "Downloaded release assets"
}

expected_asset_checksum() {
  local checksum

  checksum="$(awk -v asset="${ASSET}" '$2 == asset {print $1}' "${WORKDIR}/checksums-sha256.txt")"
  if [[ -z "${checksum}" ]]; then
    err "No checksum entry found for ${ASSET}."
    exit 1
  fi

  printf "%s" "${checksum}"
}

target_matches_release() {
  local expected actual

  if [[ ! -e "${TARGET_PATH}" ]]; then
    return 1
  fi

  expected="$(expected_asset_checksum)"
  actual="$(hash_file "${TARGET_PATH}")"
  [[ "${actual}" == "${expected}" ]]
}

maybe_exit_if_current() {
  if [[ "${IF_OUTDATED}" != "true" ]]; then
    return 0
  fi

  download_checksums
  if target_matches_release; then
    ok "${TARGET_PATH} already matches ${TAG}; no update needed."
    exit 0
  fi

  if [[ -e "${TARGET_PATH}" ]]; then
    log "${TARGET_PATH} does not match ${TAG}; update needed."
  else
    log "${TARGET_PATH} is missing; install needed."
  fi
}

idle_filter_expression() {
  local expr="("
  local port
  local separator=""
  local -a ports

  IFS=',' read -r -a ports <<<"${IDLE_PORTS}"
  for port in "${ports[@]}"; do
    expr+="${separator} sport = :${port}"
    separator=" or"
  done
  expr+=" )"

  printf "%s" "${expr}"
}

recently_active_connection_count() {
  local filter
  local quiet_ms

  filter="$(idle_filter_expression)"
  quiet_ms="$(( $(duration_seconds "${IDLE_QUIET}") * 1000 ))"
  ss -Htanio state established "${filter}" 2>/dev/null | awk -v quiet_ms="${quiet_ms}" '
    /^[^[:space:]]/ {
      if (pending) {
        count++
      }
      pending = 1
      next
    }
    /^[[:space:]]/ {
      if (!pending) {
        next
      }

      has_activity_time = 0
      is_active = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^lastsnd:[0-9]+$/) {
          split($i, value, ":")
          has_activity_time = 1
          if (value[2] < quiet_ms) {
            is_active = 1
          }
        }
        if ($i ~ /^lastrcv:[0-9]+$/) {
          split($i, value, ":")
          has_activity_time = 1
          if (value[2] < quiet_ms) {
            is_active = 1
          }
        }
      }

      if (!has_activity_time || is_active) {
        count++
      }
      pending = 0
    }
    END {
      if (pending) {
        count++
      }
      print count + 0
    }'
}

wait_for_idle_connections() {
  local timeout interval start now elapsed count

  if [[ "${WAIT_IDLE}" != "true" ]]; then
    return 0
  fi

  ensure_idle_tools
  timeout="$(duration_seconds "${IDLE_TIMEOUT}")"
  interval="$(duration_seconds "${IDLE_INTERVAL}")"
  start="$(date +%s)"

  if ((interval < 1)); then
    err "--idle-interval must be at least 1 second."
    exit 1
  fi

  log "Waiting for quiet Caddy connections on ports ${IDLE_PORTS}; quiet window ${IDLE_QUIET}"
  while true; do
    count="$(recently_active_connection_count)"
    if [[ "${count}" == "0" ]]; then
      ok "No recently active Caddy connections found."
      return 0
    fi

    now="$(date +%s)"
    elapsed="$((now - start))"
    if ((elapsed >= timeout)); then
      warn "Deferred update: ${count} recently active Caddy connection(s) remained after ${IDLE_TIMEOUT}."
      exit 0
    fi

    log "Found ${count} recently active Caddy connection(s); retrying in ${IDLE_INTERVAL}"
    sleep "${interval}"
  done
}

verify_checksum() {
  local check_file

  check_file="${WORKDIR}/selected-checksum.txt"
  if ! grep "  ${ASSET}$" "${WORKDIR}/checksums-sha256.txt" > "${check_file}"; then
    err "No checksum entry found for ${ASSET}."
    exit 1
  fi

  (
    cd "${WORKDIR}"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum --check "$(basename "${check_file}")"
    else
      shasum -a 256 --check "$(basename "${check_file}")"
    fi
  )
}

verify_assets() {
  log "Verifying checksum"
  verify_checksum
  ok "Checksum verified"

  if [[ ! -f "${WORKDIR}/checksums-sha256.txt.sigstore.json" ]]; then
    if [[ "${REQUIRE_COSIGN}" == "true" ]]; then
      err "cosign verification is required but the release has no checksum Sigstore bundle."
      exit 1
    fi
    warn "release has no checksum Sigstore bundle; skipped cosign verification"
    COSIGN_STATUS="skipped; bundle unavailable"
  elif command -v cosign >/dev/null 2>&1 || { [[ "${DRY_RUN}" != "true" ]] && install_cosign_optional; }; then
    log "Verifying checksum Sigstore bundle"
    cosign verify-blob \
      --bundle "${WORKDIR}/checksums-sha256.txt.sigstore.json" \
      --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
      --certificate-identity "https://github.com/${REPO}/.github/workflows/main.yml@refs/heads/main" \
      "${WORKDIR}/checksums-sha256.txt" >/dev/null
    ok "Cosign bundle verified"
    COSIGN_STATUS="verified"
  elif [[ "${REQUIRE_COSIGN}" == "true" ]]; then
    err "cosign verification is required but cosign is unavailable."
    exit 1
  else
    warn "cosign unavailable; skipped checksum bundle verification"
    COSIGN_STATUS="skipped; cosign unavailable"
  fi

  log "Checking downloaded binary"
  "${WORKDIR}/${ASSET}" version
  ok "Downloaded binary runs"
}

resolve_target_path() {
  local dir

  if [[ -n "${TARGET}" ]]; then
    TARGET_PATH="${TARGET}"
  elif command -v caddy >/dev/null 2>&1; then
    TARGET_PATH="$(command -v caddy)"
  else
    TARGET_PATH="${DEFAULT_TARGET}"
  fi

  if [[ "${TARGET_PATH}" != /* ]]; then
    err "Target path must be absolute: ${TARGET_PATH}"
    exit 1
  fi

  dir="$(dirname "${TARGET_PATH}")"
  case ":${PATH}:" in
    *":${dir}:"*) ;;
    *) warn "Target directory is not in PATH: ${dir}" ;;
  esac
}

capture_target_metadata() {
  if [[ -e "${TARGET_PATH}" ]]; then
    TARGET_OWNER="$(stat -c '%u' "${TARGET_PATH}")"
    TARGET_GROUP="$(stat -c '%g' "${TARGET_PATH}")"
    TARGET_MODE="$(stat -c '%a' "${TARGET_PATH}")"
  else
    TARGET_OWNER="0"
    TARGET_GROUP="0"
    TARGET_MODE="0755"
  fi
}

plan_backup_path() {
  if [[ -e "${TARGET_PATH}" ]]; then
    BACKUP_PATH="${BACKUP_DIR}/caddy.$(date -u +'%Y%m%dT%H%M%SZ')"
  else
    BACKUP_PATH=""
  fi
}

backup_existing() {
  if [[ ! -e "${TARGET_PATH}" ]]; then
    warn "No existing binary at ${TARGET_PATH}; no backup created."
    BACKUP_PATH=""
    return 0
  fi

  if [[ -z "${BACKUP_PATH:-}" ]]; then
    plan_backup_path
  fi

  log "Backing up ${TARGET_PATH} to ${BACKUP_PATH}"
  require_sudo
  "${SUDO[@]}" mkdir -p "${BACKUP_DIR}"
  "${SUDO[@]}" cp -a "${TARGET_PATH}" "${BACKUP_PATH}"
  ok "Backup created"
}

install_binary() {
  log "Installing binary to ${TARGET_PATH}"
  require_sudo
  "${SUDO[@]}" mkdir -p "$(dirname "${TARGET_PATH}")"
  "${SUDO[@]}" install -o "${TARGET_OWNER}" -g "${TARGET_GROUP}" -m "${TARGET_MODE}" "${WORKDIR}/${ASSET}" "${TARGET_PATH}"
  ok "Installed ${TARGET_PATH}"

  log "Checking installed binary"
  "${TARGET_PATH}" version

  if [[ "${LIST_MODULES}" == "true" ]]; then
    log "Installed Caddy modules"
    "${TARGET_PATH}" list-modules
  fi
}

systemd_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1
}

require_systemd() {
  local version

  if ! systemd_available; then
    err "systemd/systemctl is not available on this host."
    exit 1
  fi

  version="$(systemctl --version | awk 'NR == 1 {print $2}')"
  if [[ -n "${version}" && "${version}" =~ ^[0-9]+$ && "${version}" -lt 232 ]]; then
    err "systemctl ${version} is too old; Caddy recommends systemctl 232 or newer."
    exit 1
  fi
}

service_exists() {
  systemd_available && systemctl cat "${SERVICE}.service" >/dev/null 2>&1
}

service_is_active() {
  systemd_available && systemctl is-active --quiet "${SERVICE}.service" >/dev/null 2>&1
}

preflight_service_plan() {
  if [[ "${INSTALL_SERVICE}" != "true" ]]; then
    return 0
  fi

  require_systemd
  if service_exists && [[ "${FORCE_SERVICE}" != "true" ]]; then
    err "${SERVICE}.service already exists. Use --force-service with --install-service to overwrite it."
    exit 1
  fi
}

service_unit_plan() {
  if [[ "${INSTALL_SERVICE}" != "true" ]]; then
    printf "unchanged"
  elif service_exists; then
    printf "overwrite %s" "${UNIT_PATH}"
  else
    printf "install %s" "${UNIT_PATH}"
  fi
}

service_runtime_plan() {
  if [[ "${NO_RESTART}" == "true" ]]; then
    printf "skip (--no-restart)"
  elif service_is_active; then
    printf "restart active %s.service" "${SERVICE}"
  elif service_exists || [[ "${INSTALL_SERVICE}" == "true" ]]; then
    if [[ "${START_SERVICE}" == "true" ]]; then
      printf "enable and start %s.service after config validation" "${SERVICE}"
    else
      printf "leave %s.service inactive unless it is already active" "${SERVICE}"
    fi
  else
    printf "none"
  fi
}

print_install_plan() {
  local backup_display

  if [[ -n "${BACKUP_PATH:-}" ]]; then
    backup_display="${BACKUP_PATH}"
  else
    backup_display="none; target does not exist"
  fi

  printf "\n"
  printf " Ready to install/update caddy-proxy-cloudflare %s\n" "${TAG}"
  printf "\n"
  printf " Target:        %s\n" "${TARGET_PATH}"
  printf " Backup:        %s\n" "${backup_display}"
  printf " Binary asset:  %s\n" "${ASSET}"
  printf " Checksum:      verified\n"
  printf " Cosign:        %s\n" "${COSIGN_STATUS:-not checked}"
  printf " Systemd unit:  %s\n" "$(service_unit_plan)"
  printf " Service:       %s\n" "$(service_runtime_plan)"
  printf "\n"
}

print_restore_plan() {
  printf "\n"
  printf " Ready to restore caddy-proxy-cloudflare backup\n"
  printf "\n"
  printf " Source:        %s\n" "${1}"
  printf " Target:        %s\n" "${TARGET_PATH}"
  printf " Service:       %s\n" "$(service_runtime_plan)"
  printf "\n"
}

ensure_service_user() {
  if ! command -v getent >/dev/null 2>&1 || ! command -v groupadd >/dev/null 2>&1 || ! command -v useradd >/dev/null 2>&1; then
    err "Installing a systemd service requires getent, groupadd, and useradd."
    exit 1
  fi

  require_sudo
  if ! getent group caddy >/dev/null 2>&1; then
    "${SUDO[@]}" groupadd --system caddy
  fi

  if ! getent passwd caddy >/dev/null 2>&1; then
    "${SUDO[@]}" useradd --system \
      --gid caddy \
      --create-home \
      --home-dir /var/lib/caddy \
      --shell /usr/sbin/nologin \
      --comment "Caddy web server" \
      caddy
  fi

  "${SUDO[@]}" mkdir -p /etc/caddy /var/lib/caddy
  "${SUDO[@]}" chown caddy:caddy /var/lib/caddy
}

write_default_caddyfile() {
  local tmp

  if [[ -e "${CONFIG_PATH}" ]]; then
    return 0
  fi

  if [[ "${WRITE_DEFAULT_CADDYFILE}" != "true" ]]; then
    return 0
  fi

  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
:2015 {
	respond "Caddy is running"
}
EOF
  require_sudo
  "${SUDO[@]}" install -o root -g caddy -m 0640 "${tmp}" "${CONFIG_PATH}"
  rm -f "${tmp}"
  ok "Wrote default ${CONFIG_PATH}"
}

install_systemd_service() {
  local tmp_unit

  require_systemd
  if service_exists && [[ "${FORCE_SERVICE}" != "true" ]]; then
    err "${SERVICE}.service already exists. Use --force-service with --install-service to overwrite it."
    exit 1
  fi

  ensure_service_user
  write_default_caddyfile

  tmp_unit="$(mktemp)"
  cat > "${tmp_unit}" <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=${TARGET_PATH} run --environ --config ${CONFIG_PATH}
ExecReload=${TARGET_PATH} reload --config ${CONFIG_PATH} --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  log "Installing ${UNIT_PATH}"
  require_sudo
  "${SUDO[@]}" install -o root -g root -m 0644 "${tmp_unit}" "${UNIT_PATH}"
  rm -f "${tmp_unit}"
  "${SUDO[@]}" systemctl daemon-reload
  ok "Installed ${SERVICE}.service"
}

config_is_valid() {
  [[ -e "${CONFIG_PATH}" ]] && "${SUDO[@]}" "${TARGET_PATH}" validate --config "${CONFIG_PATH}" >/dev/null
}

start_or_restart_service() {
  if [[ "${NO_RESTART}" == "true" ]]; then
    warn "Skipping service restart because --no-restart was set."
    return 0
  fi

  if ! service_exists; then
    warn "${SERVICE}.service does not exist; installed binary only."
    return 0
  fi

  if service_is_active; then
    log "Restarting ${SERVICE}.service"
    require_sudo
    "${SUDO[@]}" systemctl restart "${SERVICE}.service"
  elif [[ "${START_SERVICE}" == "true" ]]; then
    if ! config_is_valid; then
      err "${CONFIG_PATH} is missing or failed validation; not starting ${SERVICE}.service."
      exit 1
    fi
    log "Starting ${SERVICE}.service"
    require_sudo
    "${SUDO[@]}" systemctl enable --now "${SERVICE}.service"
  else
    warn "${SERVICE}.service exists but is inactive; not starting without --start."
    return 0
  fi

  if "${SUDO[@]}" systemctl is-active --quiet "${SERVICE}.service"; then
    ok "${SERVICE}.service is running"
  else
    err "${SERVICE}.service is not active."
    "${SUDO[@]}" systemctl status --no-pager "${SERVICE}.service" || true
    exit 1
  fi
}

list_backups() {
  if [[ ! -d "${BACKUP_DIR}" ]]; then
    warn "No backup directory found: ${BACKUP_DIR}"
    return 0
  fi

  find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'caddy.*' -print | sort
}

latest_backup() {
  list_backups | tail -n 1
}

restore_backup() {
  local backup

  resolve_target_path
  capture_target_metadata

  if [[ -n "${RESTORE_PATH}" ]]; then
    backup="${RESTORE_PATH}"
  else
    backup="$(latest_backup)"
  fi

  if [[ -z "${backup}" ]]; then
    err "No backups found in ${BACKUP_DIR}."
    exit 1
  fi

  if [[ ! -f "${backup}" ]]; then
    err "Backup does not exist: ${backup}"
    exit 1
  fi

  print_restore_plan "${backup}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    ok "Dry run complete. No files changed."
    return 0
  fi

  confirm_or_exit "Continue with restore?"

  log "Restoring ${backup} to ${TARGET_PATH}"
  require_sudo
  "${SUDO[@]}" mkdir -p "$(dirname "${TARGET_PATH}")"
  "${SUDO[@]}" install -o "${TARGET_OWNER}" -g "${TARGET_GROUP}" -m "${TARGET_MODE}" "${backup}" "${TARGET_PATH}"
  ok "Restored ${TARGET_PATH}"

  log "Checking restored binary"
  "${TARGET_PATH}" version

  if [[ "${LIST_MODULES}" == "true" ]]; then
    log "Installed Caddy modules"
    "${TARGET_PATH}" list-modules
  fi

  start_or_restart_service
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      restore)
        ACTION="restore"
        shift
        if [[ $# -gt 0 && "$1" != --* ]]; then
          RESTORE_PATH="$1"
          shift
        fi
        ;;
      list-backups)
        ACTION="list-backups"
        shift
        ;;
      --version)
        VERSION="${2:-}"
        [[ -n "${VERSION}" ]] || { err "--version requires a tag"; exit 1; }
        shift 2
        ;;
      --target)
        TARGET="${2:-}"
        [[ -n "${TARGET}" ]] || { err "--target requires a path"; exit 1; }
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --if-outdated)
        IF_OUTDATED=true
        shift
        ;;
      --idle-interval)
        IDLE_INTERVAL="${2:-}"
        [[ -n "${IDLE_INTERVAL}" ]] || { err "--idle-interval requires a duration"; exit 1; }
        IDLE_INTERVAL_SET=true
        shift 2
        ;;
      --idle-ports)
        IDLE_PORTS="${2:-}"
        [[ -n "${IDLE_PORTS}" ]] || { err "--idle-ports requires a comma-separated port list"; exit 1; }
        IDLE_PORTS_SET=true
        shift 2
        ;;
      --idle-quiet)
        IDLE_QUIET="${2:-}"
        [[ -n "${IDLE_QUIET}" ]] || { err "--idle-quiet requires a duration"; exit 1; }
        IDLE_QUIET_SET=true
        shift 2
        ;;
      --idle-timeout)
        IDLE_TIMEOUT="${2:-}"
        [[ -n "${IDLE_TIMEOUT}" ]] || { err "--idle-timeout requires a duration"; exit 1; }
        IDLE_TIMEOUT_SET=true
        shift 2
        ;;
      --force-service)
        FORCE_SERVICE=true
        shift
        ;;
      --install-service)
        INSTALL_SERVICE=true
        shift
        ;;
      --list-modules)
        LIST_MODULES=true
        shift
        ;;
      --no-restart)
        NO_RESTART=true
        shift
        ;;
      --require-cosign)
        REQUIRE_COSIGN=true
        shift
        ;;
      --start)
        START_SERVICE=true
        shift
        ;;
      --wait-idle)
        WAIT_IDLE=true
        shift
        ;;
      -y|--yes)
        AUTO_YES=true
        shift
        ;;
      --write-default-caddyfile)
        WRITE_DEFAULT_CADDYFILE=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

validate_args() {
  if [[ "${ACTION}" != "install" ]]; then
    if [[ "${IF_OUTDATED}" == "true" || "${WAIT_IDLE}" == "true" || "${IDLE_INTERVAL_SET}" == "true" || "${IDLE_PORTS_SET}" == "true" || "${IDLE_QUIET_SET}" == "true" || "${IDLE_TIMEOUT_SET}" == "true" ]]; then
      err "--if-outdated and --wait-idle options only apply to install/update mode."
      exit 1
    fi
  fi

  if [[ "${WAIT_IDLE}" != "true" ]]; then
    if [[ "${IDLE_INTERVAL_SET}" == "true" || "${IDLE_PORTS_SET}" == "true" || "${IDLE_QUIET_SET}" == "true" || "${IDLE_TIMEOUT_SET}" == "true" ]]; then
      err "--idle-timeout, --idle-interval, --idle-quiet, and --idle-ports require --wait-idle."
      exit 1
    fi
  else
    duration_seconds "${IDLE_TIMEOUT}" >/dev/null
    duration_seconds "${IDLE_INTERVAL}" >/dev/null
    duration_seconds "${IDLE_QUIET}" >/dev/null
    validate_idle_ports "${IDLE_PORTS}"
  fi
}

install_or_update() {
  detect_target_asset
  if [[ "${DRY_RUN}" == "true" ]]; then
    ensure_required_tools_no_install
  else
    ensure_required_tools
  fi
  resolve_target_path
  resolve_release
  maybe_exit_if_current

  if [[ "${DRY_RUN}" != "true" ]]; then
    preflight_service_plan
    wait_for_idle_connections
  elif [[ "${WAIT_IDLE}" == "true" ]]; then
    warn "Skipping idle wait because --dry-run was set."
  fi

  download_assets
  verify_assets

  if [[ "${DRY_RUN}" == "true" ]]; then
    ok "Dry run complete. No files changed."
    return 0
  fi

  capture_target_metadata
  plan_backup_path
  print_install_plan
  confirm_or_exit "Continue with install/update?"

  backup_existing
  install_binary

  if [[ "${INSTALL_SERVICE}" == "true" ]]; then
    install_systemd_service
  fi

  start_or_restart_service

  ok "Completed successfully: ${TARGET_PATH} is now ${TAG}"
  if [[ -n "${BACKUP_PATH:-}" ]]; then
    printf " Backup retained at: %s\n" "${BACKUP_PATH}"
  fi
}

main() {
  parse_args "$@"
  validate_args
  set_sudo

  printf " Caddy Proxy Cloudflare Installer\n"
  printf "==================================\n\n"

  case "${ACTION}" in
    install)
      install_or_update
      ;;
    restore)
      restore_backup
      ;;
    list-backups)
      list_backups
      ;;
    *)
      err "Unknown action: ${ACTION}"
      exit 1
      ;;
  esac
}

main "$@"
