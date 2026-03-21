#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="Uninstall-aliyun-service"
readonly WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/uas.XXXXXX")"
readonly DEFAULT_TIMEOUT=15

AUTO_YES=0
SKIP_QUARTZ=0

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: ./UAS.sh [options]

Options:
  -y, --yes        Run without interactive confirmation
      --skip-quartz
                   Skip legacy quartz cleanup
  -h, --help       Show this help message
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run this script as root."
  fi
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      -y|--yes)
        AUTO_YES=1
        ;;
      --skip-quartz)
        SKIP_QUARTZ=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

confirm() {
  if [[ "${AUTO_YES}" -eq 1 ]]; then
    return
  fi

  printf '%s\n' "======================================================================="
  printf '%s\n' " ${SCRIPT_NAME}"
  printf '%s\n' "======================================================================="
  printf '%s\n' "This script will uninstall the Alibaba Cloud Security Center agent."
  printf '%s\n' "Before continuing, disable Agent Protection and"
  printf '%s\n' "Malicious Host Behavior Prevention in the Security Center console."
  printf '\n'
  printf '%s' "Continue? [y/N] "

  local reply=""
  read -r reply
  if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
    die "Canceled."
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  if command_exists curl; then
    curl -fsSL --connect-timeout 5 --max-time "${DEFAULT_TIMEOUT}" "${url}" -o "${output}"
    return $?
  fi

  if command_exists wget; then
    wget -q -T "${DEFAULT_TIMEOUT}" -O "${output}" "${url}"
    return $?
  fi

  die "curl or wget is required."
}

download_first_available() {
  local output="$1"
  shift

  local url=""
  for url in "$@"; do
    log "Trying ${url}"
    if download_file "${url}" "${output}"; then
      log "Downloaded ${url}"
      return 0
    fi
  done

  return 1
}

detect_ecs() {
  local dmi_path=""
  local dmi_value=""

  for dmi_path in \
    /sys/class/dmi/id/product_name \
    /sys/class/dmi/id/sys_vendor \
    /sys/devices/virtual/dmi/id/product_name \
    /sys/devices/virtual/dmi/id/sys_vendor; do
    if [[ -r "${dmi_path}" ]]; then
      dmi_value="$(<"${dmi_path}")"
      if [[ "${dmi_value}" == *"Alibaba Cloud"* ]]; then
        return 0
      fi
    fi
  done

  if command_exists curl; then
    curl -fsS --connect-timeout 1 --max-time 2 \
      http://100.100.100.200/latest/meta-data/instance-id >/dev/null 2>&1 && return 0
  fi

  if command_exists wget; then
    wget -q -T 2 -O - http://100.100.100.200/latest/meta-data/instance-id >/dev/null 2>&1 && return 0
  fi

  return 1
}

run_script() {
  local script_path="$1"
  local description="$2"

  chmod 700 "${script_path}"
  log "Running ${description}"

  set +e
  "${script_path}"
  local rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    if [[ "${rc}" -eq 6 ]]; then
      warn "${description} failed because self-protection may still be enabled."
      warn "Disable Agent Protection and Malicious Host Behavior Prevention, then retry."
    fi
    return "${rc}"
  fi

  return 0
}

run_official_uninstall() {
  local script_path="${WORKDIR}/uninstall.sh"
  local -a urls=()

  if detect_ecs; then
    log "Detected Alibaba Cloud ECS, preferring the official ECS endpoint."
    urls=(
      "http://update2.aegis.aliyun.com/download/uninstall.sh"
      "https://update2.aegis.aliyun.com/download/uninstall.sh"
      "https://update.aegis.aliyun.com/download/uninstall.sh"
      "http://update.aegis.aliyun.com/download/uninstall.sh"
    )
  else
    log "Using the public uninstall endpoint for a non-ECS server."
    urls=(
      "https://update.aegis.aliyun.com/download/uninstall.sh"
      "http://update.aegis.aliyun.com/download/uninstall.sh"
      "http://update2.aegis.aliyun.com/download/uninstall.sh"
      "https://update2.aegis.aliyun.com/download/uninstall.sh"
    )
  fi

  if ! download_first_available "${script_path}" "${urls[@]}"; then
    warn "Unable to download the official uninstall.sh script."
    return 1
  fi

  run_script "${script_path}" "official uninstall.sh"
}

run_legacy_quartz_cleanup() {
  local script_path="${WORKDIR}/quartz_uninstall.sh"
  local -a urls=(
    "https://update.aegis.aliyun.com/download/quartz_uninstall.sh"
    "http://update.aegis.aliyun.com/download/quartz_uninstall.sh"
  )

  if [[ "${SKIP_QUARTZ}" -eq 1 ]]; then
    log "Skipping legacy quartz cleanup."
    return 0
  fi

  if ! download_first_available "${script_path}" "${urls[@]}"; then
    warn "Legacy quartz_uninstall.sh is unavailable, skipping."
    return 0
  fi

  if ! run_script "${script_path}" "legacy quartz_uninstall.sh"; then
    warn "Legacy quartz cleanup failed, continuing with manual legacy cleanup."
  fi
}

cleanup_legacy_leftovers() {
  log "Cleaning up legacy service leftovers."

  pkill -x aliyun-service >/dev/null 2>&1 || true

  if command_exists systemctl; then
    systemctl stop aliyun.service >/dev/null 2>&1 || true
    systemctl disable aliyun.service >/dev/null 2>&1 || true
  fi

  rm -f \
    /etc/init.d/agentwatch \
    /usr/sbin/aliyun-service \
    /lib/systemd/system/aliyun.service \
    /etc/systemd/system/aliyun.service

  if command_exists systemctl; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed aliyun.service >/dev/null 2>&1 || true
  fi
}

verify_uninstall() {
  local process_output=""

  process_output="$(ps -ef | grep -E 'AliYunDun|YunDunMonitor|YunDunUpdate|AliHips|aliyun-service' | grep -v grep || true)"
  if [[ -n "${process_output}" ]]; then
    warn "Some agent-related processes are still running:"
    printf '%s\n' "${process_output}" >&2
    warn "If these processes are protected, disable self-protection in the console and retry."
    return 1
  fi

  log "No common agent processes are running."
  return 0
}

main() {
  local official_rc=0
  local verify_rc=0

  parse_args "$@"
  require_root
  confirm

  log "Current Alibaba Cloud documentation requires disabling self-protection before command-line uninstall."
  if run_official_uninstall; then
    :
  else
    official_rc=$?
    warn "Official uninstall.sh exited with status ${official_rc}."
  fi

  run_legacy_quartz_cleanup
  cleanup_legacy_leftovers
  if verify_uninstall; then
    :
  else
    verify_rc=$?
  fi

  printf '\n'
  printf '%s\n' "======================================================================="
  printf '%s\n' " ${SCRIPT_NAME}"
  if [[ "${official_rc}" -eq 0 && "${verify_rc}" -eq 0 ]]; then
    printf '%s\n' " Done"
    printf '%s\n' "======================================================================="
    return 0
  fi

  printf '%s\n' " Completed with warnings"
  printf '%s\n' "======================================================================="

  if [[ "${official_rc}" -ne 0 ]]; then
    return "${official_rc}"
  fi

  return "${verify_rc}"
}

main "$@"
