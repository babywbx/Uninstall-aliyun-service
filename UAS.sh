#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="Uninstall-aliyun-service"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/uas.XXXXXX")"
readonly WORKDIR
readonly DEFAULT_TIMEOUT=15

AUTO_YES=0
SKIP_QUARTZ=0
INCLUDE_ASSIST=0
INCLUDE_CLOUDMONITOR=0

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: ./UAS.sh [options]

Options:
  -y, --yes                Run without interactive confirmation
      --include-assist     Also uninstall Cloud Assistant (assist_daemon)
      --include-cloudmonitor Also uninstall CloudMonitor (argusagent / CmsGoAgent)
      --skip-quartz        Skip legacy quartz cleanup
  -h, --help               Show this help message
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
      --include-assist)
        INCLUDE_ASSIST=1
        ;;
      --include-cloudmonitor)
        INCLUDE_CLOUDMONITOR=1
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
  if [[ "${INCLUDE_ASSIST}" -eq 1 ]]; then
    printf '%s\n' "Cloud Assistant (assist_daemon) will also be removed."
  fi
  if [[ "${INCLUDE_CLOUDMONITOR}" -eq 1 ]]; then
    printf '%s\n' "CloudMonitor (argusagent / CmsGoAgent) will also be removed."
  fi
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
    wget -q --connect-timeout=5 -T "${DEFAULT_TIMEOUT}" -O "${output}" "${url}"
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

  # Run in subshell to avoid set +e leaking errexit on bash < 4.4
  local rc=0
  ("${script_path}") || rc=$?

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

# Kill agent processes, with pkill fallback for minimal installations
kill_agent_processes() {
  local -a targets=(
    aliyun-service
    AliYunDun
    AliYunDunMonitor
    AliYunDunUpdate
    AliHips
    AliSecGuard
    AliSecCheck
    AliSecureCheck
    AliNet
    AliWebGuard
  )

  local name=""
  for name in "${targets[@]}"; do
    if command_exists pkill; then
      # -x for exact match; fall back to -f for BusyBox pkill
      pkill -x "${name}" 2>/dev/null || pkill -f "/${name}(\\s|$)" 2>/dev/null || true
    elif command_exists killall; then
      killall "${name}" >/dev/null 2>&1 || true
    fi
  done
}

# Stop and disable services across init systems (systemd / SysVinit / chkconfig)
stop_services() {
  local -a service_names=(aliyun aegis agentwatch)
  local svc=""

  for svc in "${service_names[@]}"; do
    if command_exists systemctl; then
      systemctl stop "${svc}.service" >/dev/null 2>&1 || true
      systemctl disable "${svc}.service" >/dev/null 2>&1 || true
    fi

    # SysVinit (CentOS 6, Ubuntu 14.04, Debian 7)
    if [[ -x "/etc/init.d/${svc}" ]]; then
      /etc/init.d/"${svc}" stop >/dev/null 2>&1 || true
    fi
    if command_exists chkconfig; then
      chkconfig --del "${svc}" >/dev/null 2>&1 || true
    elif command_exists update-rc.d; then
      update-rc.d -f "${svc}" remove >/dev/null 2>&1 || true
    fi
  done
}

cleanup_legacy_leftovers() {
  log "Cleaning up legacy service leftovers."

  kill_agent_processes
  stop_services

  # Init scripts
  rm -f /etc/init.d/aegis /etc/init.d/agentwatch

  # Runlevel symlinks (SysVinit autostart on CentOS/Ubuntu/Debian)
  local rc_dir=""
  for rc_dir in /etc/rc{0,1,2,3,4,5,6}.d /etc/rc.d/rc{0,1,2,3,4,5,6}.d; do
    rm -f "${rc_dir}/S80aegis" "${rc_dir}/K20aegis" \
          "${rc_dir}/S80agentwatch" "${rc_dir}/K20agentwatch" \
      >/dev/null 2>&1 || true
  done

  # OpenRC (Gentoo, Alpine)
  rm -f /etc/runlevels/default/aegis >/dev/null 2>&1 || true

  # Systemd unit files (Debian/Ubuntu: /lib, CentOS/RHEL: /usr/lib)
  rm -f \
    /lib/systemd/system/aliyun.service \
    /lib/systemd/system/aegis.service \
    /usr/lib/systemd/system/aliyun.service \
    /usr/lib/systemd/system/aegis.service \
    /etc/systemd/system/aliyun.service \
    /etc/systemd/system/aegis.service \
    /etc/systemd/system/multi-user.target.wants/aliyun.service \
    /etc/systemd/system/multi-user.target.wants/aegis.service

  # Legacy binaries
  rm -f \
    /usr/sbin/aliyun-service \
    /usr/sbin/aliyun-service.backup \
    /usr/sbin/aliyun_installer

  if command_exists systemctl; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed aliyun.service >/dev/null 2>&1 || true
    systemctl reset-failed aegis.service >/dev/null 2>&1 || true
  fi
}

# Remove /usr/local/aegis when official uninstall.sh was not available
cleanup_aegis_directory() {
  local aegis_dir="/usr/local/aegis"

  if [[ ! -d "${aegis_dir}" ]]; then
    return 0
  fi

  log "Removing leftover ${aegis_dir} directory."
  if ! rm -rf "${aegis_dir}" 2>/dev/null; then
    warn "Failed to fully remove ${aegis_dir}."
    warn "Some files may be immutable or held by running processes."
    warn "Try: chattr -R -i ${aegis_dir} && rm -rf ${aegis_dir}"
    return 1
  fi
}

# Uninstall Cloud Assistant (assist_daemon + aliyun_assist)
# Official order: stop daemon first (watchdog), then service, package, files.
uninstall_cloud_assist() {
  if [[ "${INCLUDE_ASSIST}" -eq 0 ]]; then
    return 0
  fi

  log "Uninstalling Cloud Assistant."

  # Step 1: Stop and delete the watchdog daemon (check both standard and CoreOS paths)
  local daemon_bin=""
  for daemon_bin in \
    /usr/local/share/assist-daemon/assist_daemon \
    /opt/local/share/assist-daemon/assist_daemon; do
    if [[ -x "${daemon_bin}" ]]; then
      log "Stopping assist_daemon watchdog via ${daemon_bin}."
      "${daemon_bin}" --stop >/dev/null 2>&1 || true
      "${daemon_bin}" --delete >/dev/null 2>&1 || true
    fi
  done

  # Kill assist_daemon and the auto-updater in case --stop/--delete didn't work
  if command_exists pkill; then
    pkill -x "assist_daemon" 2>/dev/null || pkill -f "/assist_daemon" 2>/dev/null || true
    pkill -f "aliyun_assist_update" 2>/dev/null || true
    pkill -f "aliyun-service" 2>/dev/null || true
    pkill -f "aliyun_assist_service" 2>/dev/null || true
  elif command_exists killall; then
    killall "assist_daemon" >/dev/null 2>&1 || true
    killall "aliyun-service" >/dev/null 2>&1 || true
  fi

  # Step 2: Stop the Cloud Assistant service
  if command_exists systemctl; then
    systemctl stop aliyun.service >/dev/null 2>&1 || true
    systemctl disable aliyun.service >/dev/null 2>&1 || true
    systemctl stop AssistDaemon.service >/dev/null 2>&1 || true
    systemctl disable AssistDaemon.service >/dev/null 2>&1 || true
  fi

  # Upstart (Ubuntu 14.04, CentOS 6)
  if command_exists initctl; then
    initctl stop aliyun-service >/dev/null 2>&1 || true
  fi

  # SysVinit
  if [[ -x /etc/init.d/aliyun-service ]]; then
    /etc/init.d/aliyun-service stop >/dev/null 2>&1 || true
  fi

  # Step 3: Uninstall the package
  if command_exists rpm; then
    local rpm_pkg=""
    rpm_pkg="$(rpm -qa 2>/dev/null | grep aliyun_assist || true)"
    if [[ -n "${rpm_pkg}" ]]; then
      log "Removing RPM package: ${rpm_pkg}"
      rpm -e "${rpm_pkg}" >/dev/null 2>&1 || true
    fi
  fi
  if command_exists dpkg; then
    if dpkg -l aliyun-assist >/dev/null 2>&1; then
      log "Removing DEB package: aliyun-assist"
      dpkg --purge aliyun-assist >/dev/null 2>&1 || true
    fi
  fi

  # Step 4: Remove leftover directories and files (standard + CoreOS paths)
  rm -rf /usr/local/share/aliyun-assist
  rm -rf /usr/local/share/assist-daemon
  rm -rf /opt/local/share/aliyun-assist
  rm -rf /opt/local/share/assist-daemon
  rm -f /etc/init.d/aliyun-service
  rm -f \
    /etc/systemd/system/AssistDaemon.service \
    /etc/systemd/system/multi-user.target.wants/AssistDaemon.service \
    /lib/systemd/system/AssistDaemon.service \
    /usr/lib/systemd/system/AssistDaemon.service

  if command_exists systemctl; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed AssistDaemon.service >/dev/null 2>&1 || true
  fi

  log "Cloud Assistant uninstall completed."
}

# Uninstall CloudMonitor agent (C++ argusagent, Go CmsGoAgent, Java wrapper)
uninstall_cloudmonitor() {
  if [[ "${INCLUDE_CLOUDMONITOR}" -eq 0 ]]; then
    return 0
  fi

  local arch=""
  case "$(uname -m)" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)       arch="386" ;;
  esac

  # Standard path is /usr/local/cloudmonitor; CoreOS/Flatcar uses /opt
  local cms_home="" go_agent="" found_any=0
  for cms_home in /usr/local/cloudmonitor /opt/cloudmonitor; do
    if [[ ! -d "${cms_home}" ]]; then
      continue
    fi
    found_any=1
    log "Uninstalling CloudMonitor from ${cms_home}."

    # C++ version (3.x): cloudmonitorCtl.sh
    if [[ -x "${cms_home}/cloudmonitorCtl.sh" ]]; then
      log "Stopping C++ version (argusagent)."
      "${cms_home}/cloudmonitorCtl.sh" stop >/dev/null 2>&1 || true
      "${cms_home}/cloudmonitorCtl.sh" uninstall >/dev/null 2>&1 || true
    fi

    # Go version (2.x): CmsGoAgent.linux-{amd64,arm64,386}
    go_agent="${cms_home}/CmsGoAgent.linux-${arch}"
    if [[ -x "${go_agent}" ]]; then
      log "Stopping Go version (CmsGoAgent)."
      "${go_agent}" stop >/dev/null 2>&1 || true
      "${go_agent}" uninstall >/dev/null 2>&1 || true
    fi

    # Java version (1.x): wrapper
    if [[ -x "${cms_home}/wrapper/bin/cloudmonitor.sh" ]]; then
      log "Removing Java version (wrapper)."
      "${cms_home}/wrapper/bin/cloudmonitor.sh" remove >/dev/null 2>&1 || true
    fi
  done

  if [[ "${found_any}" -eq 0 ]]; then
    log "CloudMonitor directory not found, skipping."
    return 0
  fi

  # Kill lingering processes before removing directories
  if command_exists pkill; then
    pkill -x "argusagent" 2>/dev/null || true
    pkill -f "CmsGoAgent" 2>/dev/null || true
  elif command_exists killall; then
    killall "argusagent" >/dev/null 2>&1 || true
    killall "CmsGoAgent.linux-${arch}" >/dev/null 2>&1 || true
  fi

  for cms_home in /usr/local/cloudmonitor /opt/cloudmonitor; do
    rm -rf "${cms_home}"
  done

  log "CloudMonitor uninstall completed."
}

verify_uninstall() {
  local -a targets=(
    AliYunDun AliYunDunMonitor AliYunDunUpdate
    AliHips AliSecGuard AliSecCheck AliSecureCheck
    AliNet AliWebGuard aliyun-service
  )
  if [[ "${INCLUDE_ASSIST}" -eq 1 ]]; then
    targets+=(assist_daemon)
  fi
  if [[ "${INCLUDE_CLOUDMONITOR}" -eq 1 ]]; then
    targets+=(argusagent)
  fi
  local found=0
  local name=""

  for name in "${targets[@]}"; do
    if command_exists pgrep; then
      # -x matches exact process name; works on procps and BusyBox
      if pgrep -x "${name}" >/dev/null 2>&1; then
        warn "Process still running: ${name}"
        found=1
      fi
    else
      # shellcheck disable=SC2009
      if ps -eo comm= 2>/dev/null | grep -qx "${name}"; then
        warn "Process still running: ${name}"
        found=1
      fi
    fi
  done

  # CmsGoAgent binary includes arch suffix (e.g. CmsGoAgent.linux-amd64),
  # so pgrep -x cannot match; use -f for command-line pattern match instead.
  if [[ "${INCLUDE_CLOUDMONITOR}" -eq 1 ]]; then
    if command_exists pgrep; then
      if pgrep -f "CmsGoAgent" >/dev/null 2>&1; then
        warn "Process still running: CmsGoAgent"
        found=1
      fi
    else
      # shellcheck disable=SC2009
      if ps -eo args= 2>/dev/null | grep -q "CmsGoAgent"; then
        warn "Process still running: CmsGoAgent"
        found=1
      fi
    fi
  fi

  if [[ "${found}" -ne 0 ]]; then
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

  if cleanup_aegis_directory; then
    :
  else
    warn "Aegis directory cleanup failed; you may need to manually remove /usr/local/aegis."
  fi

  uninstall_cloud_assist
  uninstall_cloudmonitor

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
