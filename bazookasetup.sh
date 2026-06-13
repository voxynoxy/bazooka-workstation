#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIG
# ============================================================================

readonly BAZOOKA_NAME="Bazooka"
readonly BAZOOKA_TAGLINE="Ubuntu Security Workstation Manager"
readonly BAZOOKA_VERSION="1.0.0"
readonly BAZOOKA_MAINTAINER="voxynoxy"
readonly BAZOOKA_REPOSITORY="voxynoxy/bazooka-workstation"
readonly BAZOOKA_REPOSITORY_URL="https://github.com/voxynoxy/bazooka-workstation"

# CHECK: Stage 5 update engine will use these variables. They are intentionally
# empty until a release source is configured.
readonly BAZOOKA_UPDATE_URL=""
readonly BAZOOKA_RELEASE_API_URL=""

DRY_RUN=false
NO_COLOR=false
VERBOSE=false
QUIET=false
ASSUME_YES=false
INTERACTIVE_MODE=false
APT_UPDATED=false
COMMAND=""
COMMAND_ARG=""
START_TIME="$(date +%s)"
SCRIPT_PATH="${BASH_SOURCE[0]}"

# ============================================================================
# CONSTANTS
# ============================================================================

readonly STATE_DIR="/var/lib/bazooka"
readonly LOG_FILE="/var/log/bazooka.log"
readonly SYSTEM_INSTALL_PATH="/usr/local/bin/bazookasetup"
readonly BAZOOKA_USER="${SUDO_USER:-${USER:-$(id -un)}}"
readonly BAZOOKA_HOME="$(getent passwd "$BAZOOKA_USER" | awk -F: '{print $6}')"
readonly WORKSPACE_DIR="${BAZOOKA_HOME}/bazooka/workspaces"
readonly REPORT_DIR="${BAZOOKA_HOME}/bazooka/reports"
readonly WORDLIST_DIR="${BAZOOKA_HOME}/bazooka/wordlists"
readonly BACKUP_DIR="${BAZOOKA_HOME}/.bazooka/backups"
readonly SUPPORTED_UBUNTU_MIN_MAJOR=22

# Exit code contract:
#   0   success, including all successful dry-run operations
#   1   general runtime error
#   2   usage error, invalid argument, or unsupported operating system
#   3   privilege error
#   4   healthcheck completed with Overall Status = UNHEALTHY
#   5   requested resource not found, such as restore with no backups
#   130 interrupted by user
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_USAGE=2
readonly EXIT_PRIVILEGE=3
readonly EXIT_HEALTH_UNHEALTHY=4
readonly EXIT_NOT_FOUND=5
readonly EXIT_INTERRUPTED=130

# CHECK: Package names for later stages must be checked at runtime with
# apt-cache policy before installation when availability differs across Ubuntu
# releases.

# ============================================================================
# COLORS
# ============================================================================

if [[ -t 1 ]]; then
  COLOR_CYAN=$'\033[36m'
  COLOR_WHITE=$'\033[37m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_RED=$'\033[31m'
  COLOR_GRAY=$'\033[90m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_CYAN=""
  COLOR_WHITE=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_GRAY=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

disable_colors() {
  COLOR_CYAN=""
  COLOR_WHITE=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_GRAY=""
  COLOR_BOLD=""
  COLOR_RESET=""
}

# ============================================================================
# BANNER
# ============================================================================

print_banner() {
  print_color "$COLOR_CYAN" '▗▄▄▖   ▄  ▗▄▄▄▖ ▗▄▖  ▗▄▖ ▗▖ ▄▖  ▄  '
  print_color "$COLOR_CYAN" '▐▛▀▜▌ ▐█▌ ▝▀▀█▌ █▀█  █▀█ ▐▌▐▛  ▐█▌ '
  print_color "$COLOR_CYAN" '▐▌ ▐▌ ▐█▌   ▐▛ ▐▌ ▐▌▐▌ ▐▌▐▙█   ▐█▌ '
  print_color "$COLOR_CYAN" '▐███  █ █  ▗█▘ ▐▌ ▐▌▐▌ ▐▌▐██   █ █ '
  print_color "$COLOR_CYAN" '▐▌ ▐▌ ███  ▟▌  ▐▌ ▐▌▐▌ ▐▌▐▌▐▙  ███ '
  print_color "$COLOR_CYAN" '▐▙▄▟▌▗█ █▖▐█▄▄▖ █▄█  █▄█ ▐▌ █▖▗█ █▖'
  print_color "$COLOR_CYAN" '▝▀▀▀ ▝▘ ▝▘▝▀▀▀▘ ▝▀▘  ▝▀▘ ▝▘ ▝▘▝▘ ▝▘'
  printf '\n%s\n\n' "$BAZOOKA_TAGLINE"
  print_warn "AUTHORIZED USE ONLY"
}

print_status_box() {
  local host user mode status
  host="$(hostname 2>/dev/null || printf 'unknown')"
  user="$BAZOOKA_USER"
  mode="$1"
  status="$2"

  print_color "$COLOR_CYAN" "┌────────────────────────────────────────────────────────────┐"
  print_color "$COLOR_CYAN" "│                          BAZOOKA                           │"
  print_color "$COLOR_CYAN" "│              Ubuntu Security Workstation Manager            │"
  print_color "$COLOR_CYAN" "├────────────────────────────────────────────────────────────┤"
  printf '│ %-12s %-45s│\n' "Version" "$BAZOOKA_VERSION"
  printf '│ %-12s %-45s│\n' "Host" "$host"
  printf '│ %-12s %-45s│\n' "User" "$user"
  printf '│ %-12s %-45s│\n' "Mode" "$mode"
  printf '│ %-12s %-45s│\n' "Status" "$status"
  print_color "$COLOR_CYAN" "└────────────────────────────────────────────────────────────┘"
}

# ============================================================================
# LOGGER
# ============================================================================

log_line() {
  local level message timestamp
  level="$1"
  message="$2"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ -w "$LOG_FILE" ]]; then
    printf '%s %s %s\n' "$timestamp" "$level" "$message" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

log_info() {
  log_line "INFO" "$1"
}

log_warn() {
  log_line "WARN" "$1"
}

log_error() {
  log_line "ERROR" "$1"
}

log_debug() {
  if [[ "$VERBOSE" == true ]]; then
    log_line "DEBUG" "$1"
  fi
}

# ============================================================================
# UTILITIES
# ============================================================================

print_color() {
  local color text
  color="$1"
  text="$2"
  if [[ "$NO_COLOR" == true ]]; then
    printf '%s\n' "$text"
  else
    printf '%s%s%s\n' "$color" "$text" "$COLOR_RESET"
  fi
}

print_info() {
  [[ "$QUIET" == true ]] && return 0
  print_color "$COLOR_WHITE" "$1"
}

print_ok() {
  [[ "$QUIET" == true ]] && return 0
  print_color "$COLOR_GREEN" "$1"
}

print_warn() {
  [[ "$QUIET" == true ]] && return 0
  print_color "$COLOR_YELLOW" "WARN: $1"
}

print_error() {
  print_color "$COLOR_RED" "ERROR: $1" >&2
}

print_debug() {
  [[ "$VERBOSE" == true ]] || return 0
  [[ "$QUIET" == true ]] && return 0
  print_color "$COLOR_GRAY" "DEBUG: $1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

format_duration() {
  local elapsed hours minutes seconds
  elapsed="$1"
  hours=$((elapsed / 3600))
  minutes=$(((elapsed % 3600) / 60))
  seconds=$((elapsed % 60))
  printf '%02d:%02d:%02d' "$hours" "$minutes" "$seconds"
}

confirm() {
  local prompt reply
  prompt="$1"

  if [[ "$ASSUME_YES" == true ]]; then
    return 0
  fi

  printf '%s [y/N] ' "$prompt"
  read -r reply
  [[ "$reply" == "y" || "$reply" == "Y" || "$reply" == "yes" || "$reply" == "YES" ]]
}

ensure_directory() {
  local dir
  dir="$1"

  if [[ "$DRY_RUN" == true ]]; then
    print_debug "dry-run: mkdir -p $dir"
    return 0
  fi

  mkdir -p "$dir"
}

safe_basename() {
  basename -- "$1"
}

cleanup() {
  local exit_code
  exit_code="$?"
  log_debug "cleanup completed with exit code ${exit_code}"
}

on_error() {
  local exit_code line command_text
  exit_code="$1"
  line="$2"
  command_text="$3"
  log_error "Command failed at line ${line}: ${command_text} (exit ${exit_code})"
  print_error "Command failed at line ${line}. Run with --verbose for details."
  exit "$exit_code"
}

on_interrupt() {
  printf '\n'
  print_warn "Interrupted by user."
  log_warn "Interrupted by user"
  exit "$EXIT_INTERRUPTED"
}

print_kv() {
  local key value
  key="$1"
  value="$2"
  printf '%-28s %s\n' "$key" "$value"
}

print_rule() {
  printf '────────────────────────────────────────────────────────────\n'
}

join_by() {
  local delimiter first item
  delimiter="$1"
  shift
  first=true

  for item in "$@"; do
    if [[ "$first" == true ]]; then
      printf '%s' "$item"
      first=false
    else
      printf '%s%s' "$delimiter" "$item"
    fi
  done
}

# ============================================================================
# OS DETECTION
# ============================================================================

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    print_error "Cannot detect operating system. /etc/os-release is missing."
    return 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    print_error "Unsupported operating system: ${PRETTY_NAME:-unknown}. Ubuntu is required."
    return 1
  fi

  if ! is_supported_ubuntu_version "${VERSION_ID:-0}"; then
    print_error "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported: 22.04 LTS, 24.04 LTS, and newer compatible releases."
    return 1
  fi

  log_debug "Detected supported OS: ${PRETTY_NAME:-Ubuntu}"
}

is_supported_ubuntu_version() {
  local version major
  version="$1"
  major="${version%%.*}"

  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  ((major >= SUPPORTED_UBUNTU_MIN_MAJOR))
}

# ============================================================================
# PRIVILEGE CHECKS
# ============================================================================

is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

has_sudo() {
  command_exists sudo
}

require_root() {
  local action
  action="$1"

  if is_root; then
    return 0
  fi

  print_error "${action} requires root privileges. Re-run with sudo."
  return "$EXIT_PRIVILEGE"
}

require_command() {
  local cmd
  cmd="$1"
  if ! command_exists "$cmd"; then
    print_error "Required command not found: $cmd"
    return 1
  fi
}

ensure_state_paths() {
  if [[ "$DRY_RUN" == true ]]; then
    print_info "Dry run: would create ${STATE_DIR} and ${LOG_FILE}"
    return 0
  fi

  require_root "Creating Bazooka state paths" || return "$?"

  mkdir -p "$STATE_DIR"
  touch "$LOG_FILE"
  chmod 0755 "$STATE_DIR"
  chmod 0644 "$LOG_FILE"
}

# ============================================================================
# PACKAGE MANAGEMENT
# ============================================================================

package_installed() {
  local package_name
  package_name="$1"
  dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q 'install ok installed'
}

package_available() {
  local package_name candidate
  package_name="$1"

  if ! command_exists apt-cache; then
    return 1
  fi

  candidate="$(apt-cache policy "$package_name" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

check_package_state() {
  local audit_output

  if ! command_exists dpkg || ! command_exists apt-get; then
    print_error "dpkg and apt-get are required for package management."
    return 1
  fi

  audit_output="$(dpkg --audit 2>/dev/null || true)"
  if [[ -n "$audit_output" ]]; then
    print_error "dpkg reports an incomplete package state. Run --repair before installing profiles."
    log_error "dpkg audit reported package issues"
    return 1
  fi

  if ! apt-get check >/dev/null 2>&1; then
    print_error "APT reports broken dependencies. Run --repair before installing profiles."
    log_error "apt-get check failed"
    return 1
  fi
}

apt_retry() {
  local attempt max_attempts delay
  max_attempts=3
  delay=8

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if "$@"; then
      return 0
    fi

    if ((attempt < max_attempts)); then
      print_warn "APT command failed, retrying in ${delay}s (${attempt}/${max_attempts})"
      log_warn "APT command failed, retrying attempt ${attempt}/${max_attempts}: $*"
      sleep "$delay"
    fi
  done

  return 1
}

apt_update_once() {
  if [[ "$APT_UPDATED" == true ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    print_debug "dry-run: apt-get update"
    APT_UPDATED=true
    return 0
  fi

  require_root "APT update" || return "$?"
  log_info "Running apt-get update"
  if ! apt_retry env DEBIAN_FRONTEND=noninteractive apt-get \
    -o Dpkg::Lock::Timeout=60 update; then
    print_error "apt-get update failed."
    log_error "apt-get update failed"
    return 1
  fi

  APT_UPDATED=true
}

print_profile_header() {
  local profile_name
  profile_name="$1"
  [[ "$QUIET" == true ]] && return 0
  printf 'Provisioning Profile: %s\n' "$profile_name"
  print_rule
  printf '\n'
}

print_package_status() {
  local package_name status
  package_name="$1"
  status="$2"

  [[ "$QUIET" == true ]] && return 0

  case "$status" in
    OK)
      printf '%-28s ' "$package_name"
      print_color "$COLOR_GREEN" "OK"
      ;;
    DRY-RUN)
      printf '%-28s ' "$package_name"
      print_color "$COLOR_GRAY" "DRY-RUN"
      ;;
    WARN*)
      printf '%-28s ' "$package_name"
      print_color "$COLOR_YELLOW" "$status"
      ;;
    FAILED)
      printf '%-28s ' "$package_name"
      print_color "$COLOR_RED" "FAILED"
      ;;
    *)
      printf '%-28s %s\n' "$package_name" "$status"
      ;;
  esac
}

print_completion() {
  local start_ts end_ts elapsed
  start_ts="$1"
  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))

  [[ "$QUIET" == true ]] && return 0

  printf '\n'
  printf 'Completed\n'
  printf 'Duration: %s\n' "$(format_duration "$elapsed")"
  printf 'Log: %s\n' "$LOG_FILE"
}

print_task_header() {
  local title
  title="$1"
  [[ "$QUIET" == true ]] && return 0
  printf '%s\n' "$title"
  print_rule
  printf '\n'
}

print_task_status() {
  local label status
  label="$1"
  status="$2"

  [[ "$QUIET" == true ]] && return 0

  case "$status" in
    OK | RUNNING | READY)
      printf '%-28s ' "$label"
      print_color "$COLOR_GREEN" "$status"
      ;;
    DRY-RUN)
      printf '%-28s ' "$label"
      print_color "$COLOR_GRAY" "$status"
      ;;
    WARN*)
      printf '%-28s ' "$label"
      print_color "$COLOR_YELLOW" "$status"
      ;;
    FAILED)
      printf '%-28s ' "$label"
      print_color "$COLOR_RED" "$status"
      ;;
    *)
      printf '%-28s %s\n' "$label" "$status"
      ;;
  esac
}

record_profile_state() {
  local profile_name timestamp state_file tmp_file
  profile_name="$1"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  state_file="${STATE_DIR}/profiles.list"
  tmp_file="${state_file}.tmp"

  if [[ "$DRY_RUN" == true ]]; then
    print_debug "dry-run: record profile ${profile_name} in ${state_file}"
    return 0
  fi

  ensure_state_paths
  if [[ -f "$state_file" ]]; then
    grep -v "^${profile_name}|" "$state_file" >"$tmp_file" 2>/dev/null || true
    mv "$tmp_file" "$state_file"
  fi

  printf '%s|%s\n' "$profile_name" "$timestamp" >>"$state_file"
  log_info "Recorded profile state: ${profile_name}"
}

install_one_package() {
  local package_name
  package_name="$1"

  if package_installed "$package_name"; then
    print_package_status "$package_name" "OK"
    log_info "Package already installed: ${package_name}"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    print_package_status "$package_name" "DRY-RUN"
    log_info "Dry run: would install package ${package_name}"
    return 0
  fi

  log_info "Installing package: ${package_name}"
  if apt_retry env DEBIAN_FRONTEND=noninteractive apt-get \
    -o Dpkg::Lock::Timeout=60 install -y "$package_name" >/dev/null; then
    print_package_status "$package_name" "OK"
    return 0
  fi

  print_package_status "$package_name" "FAILED"
  log_error "Failed to install package: ${package_name}"
  return 1
}

install_packages() {
  local profile_name start_ts package_name failed
  profile_name="$1"
  shift
  start_ts="$(date +%s)"
  failed=0

  print_profile_header "$profile_name"

  if [[ "$DRY_RUN" != true ]]; then
    require_root "Installing profile ${profile_name}" || return "$?"
    check_package_state
  else
    print_debug "dry-run: package state checks will not modify the system"
  fi

  apt_update_once

  for package_name in "$@"; do
    if ! install_one_package "$package_name"; then
      failed=1
    fi
  done

  if [[ "$failed" -eq 0 ]]; then
    record_profile_state "$profile_name"
  fi

  print_completion "$start_ts"
  return "$failed"
}

install_available_packages() {
  local profile_name start_ts package_name failed status
  profile_name="$1"
  shift
  start_ts="$(date +%s)"
  failed=0

  print_profile_header "$profile_name"

  if [[ "$DRY_RUN" != true ]]; then
    require_root "Installing profile ${profile_name}" || return "$?"
    check_package_state
  else
    print_debug "dry-run: package state checks will not modify the system"
  fi

  apt_update_once

  for package_name in "$@"; do
    # CHECK: These packages can vary between Ubuntu releases or enabled apt
    # repositories, so availability is checked at runtime.
    if ! package_available "$package_name"; then
      status="WARN not available via apt, skipped"
      print_package_status "$package_name" "$status"
      log_warn "${package_name}: not available via apt, skipped"
      continue
    fi

    if ! install_one_package "$package_name"; then
      failed=1
    fi
  done

  if [[ "$failed" -eq 0 ]]; then
    record_profile_state "$profile_name"
  fi

  print_completion "$start_ts"
  return "$failed"
}

clone_testssl_optional() {
  local target_dir start_ts
  target_dir="/opt/bazooka-tools/testssl"
  start_ts="$(date +%s)"

  print_warn "testssl.sh is for authorized testing only. Do not use against systems without explicit permission."

  if [[ "$DRY_RUN" == true ]]; then
    print_package_status "testssl.sh" "DRY-RUN"
    log_info "Dry run: would offer optional clone of testssl.sh to ${target_dir}"
    print_completion "$start_ts"
    return 0
  fi

  if ! confirm "Clone official testssl.sh repository to ${target_dir}?"; then
    print_package_status "testssl.sh" "WARN skipped by user"
    log_warn "testssl.sh clone skipped by user"
    return 0
  fi

  require_root "Installing optional testssl.sh" || return "$?"
  require_command git
  mkdir -p "$(dirname "$target_dir")"

  if [[ -d "$target_dir/.git" ]]; then
    git -C "$target_dir" pull --ff-only
  else
    git clone --depth 1 https://github.com/testssl/testssl.sh.git "$target_dir"
  fi

  print_package_status "testssl.sh" "OK"
  log_info "Installed optional testssl.sh at ${target_dir}"
  print_completion "$start_ts"
}

# ============================================================================
# PROFILE ENGINE
# ============================================================================

profile_minimal() {
  local packages
  packages=(
    curl
    wget
    git
    ca-certificates
    gnupg
    lsb-release
    software-properties-common
    build-essential
    unzip
    jq
    tree
    tmux
    vim
    nano
    python3
    python3-pip
    python3-venv
  )

  install_packages "minimal" "${packages[@]}"
}

profile_recon() {
  local stable_packages optional_packages
  stable_packages=(
    whois
    dnsutils
    traceroute
    netcat-openbsd
    nmap
    httpie
    sslscan
  )
  optional_packages=(
    massdns
    whatweb
    testssl.sh
  )

  install_packages "recon" "${stable_packages[@]}"
  install_available_packages "recon-optional" "${optional_packages[@]}"

  if ! package_available "testssl.sh" && ! package_installed "testssl.sh"; then
    clone_testssl_optional
  fi
}

profile_web() {
  local packages
  packages=(
    nikto
    sqlmap
    wfuzz
    ffuf
    gobuster
    feroxbuster
    zaproxy
  )

  print_warn "sqlmap: Authorized testing only. Do not use against systems without explicit permission."
  install_available_packages "web" "${packages[@]}"
}

profile_all() {
  profile_minimal
  profile_recon
  profile_web
  install_docker_engine
  deploy_labs
  manage_wordlists
}

# ============================================================================
# DOCKER ENGINE
# ============================================================================

docker_compose_available() {
  command_exists docker && docker compose version >/dev/null 2>&1
}

docker_engine_available() {
  command_exists docker
}

docker_service_active() {
  command_exists systemctl && systemctl is-active --quiet docker
}

docker_repo_codename() {
  local codename
  codename=""

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi

  if [[ -z "$codename" ]] && command_exists lsb_release; then
    codename="$(lsb_release -cs)"
  fi

  printf '%s' "$codename"
}

add_docker_repository() {
  local arch codename source_line
  arch="$(dpkg --print-architecture)"
  codename="$(docker_repo_codename)"

  if [[ -z "$codename" ]]; then
    print_task_status "Docker repository" "FAILED"
    print_error "Unable to detect Ubuntu codename for Docker repository."
    return 1
  fi

  source_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable"

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "Docker GPG key" "DRY-RUN"
    print_task_status "Docker apt source" "DRY-RUN"
    log_info "Dry run: would configure Docker repository for ${codename}"
    return 0
  fi

  require_root "Configuring Docker repository" || return "$?"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  printf '%s\n' "$source_line" >/etc/apt/sources.list.d/docker.list
  print_task_status "Docker GPG key" "OK"
  print_task_status "Docker apt source" "OK"
  log_info "Configured Docker official apt repository for ${codename}"
  APT_UPDATED=false
}

enable_docker_service() {
  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "Docker service" "DRY-RUN"
    log_info "Dry run: would enable and start docker service"
    return 0
  fi

  require_root "Managing Docker service" || return "$?"
  systemctl enable --now docker >/dev/null
  print_task_status "Docker service" "OK"
  log_info "Docker service enabled and started"
}

configure_docker_group() {
  if id -nG "$BAZOOKA_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    print_task_status "User docker group" "OK"
    log_info "User ${BAZOOKA_USER} already belongs to docker group"
    return 0
  fi

  print_warn "Adding a user to the docker group grants root-equivalent control over the Docker daemon."
  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "User docker group" "DRY-RUN"
    log_info "Dry run: would ask before adding ${BAZOOKA_USER} to docker group"
    return 0
  fi

  if ! confirm "Add ${BAZOOKA_USER} to the docker group?"; then
    print_task_status "User docker group" "WARN skipped"
    log_warn "Docker group membership skipped for ${BAZOOKA_USER}"
    return 0
  fi

  require_root "Configuring docker group membership" || return "$?"
  groupadd -f docker
  usermod -aG docker "$BAZOOKA_USER"
  print_task_status "User docker group" "OK"
  log_info "Added ${BAZOOKA_USER} to docker group"
}

install_docker_engine() {
  local start_ts docker_packages
  start_ts="$(date +%s)"
  docker_packages=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-compose-plugin
  )

  print_task_header "Docker Engine"

  if docker_engine_available && docker_compose_available; then
    print_task_status "Docker packages" "OK"
    log_info "Docker Engine and Compose plugin already available"
  else
    # CHECK: Docker package names are provided by Docker's official apt
    # repository and must be installed only after that repository is configured.
    if [[ "$DRY_RUN" != true ]]; then
      require_root "Installing Docker Engine" || return "$?"
      check_package_state
    fi

    install_packages "docker-prerequisites" ca-certificates curl gnupg lsb-release
    add_docker_repository
    apt_update_once
    install_packages "docker" "${docker_packages[@]}"
  fi

  enable_docker_service
  configure_docker_group
  record_profile_state "docker"
  print_completion "$start_ts"
}

# ============================================================================
# LAB ENGINE
# ============================================================================

labs_dir() {
  printf '%s/labs' "$STATE_DIR"
}

labs_compose_file() {
  printf '%s/docker-compose.yml' "$(labs_dir)"
}

write_labs_compose() {
  local dir compose_file
  dir="$(labs_dir)"
  compose_file="$(labs_compose_file)"

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "Compose file" "DRY-RUN"
    log_info "Dry run: would write local-only lab compose file to ${compose_file}"
    return 0
  fi

  require_root "Writing lab compose file" || return "$?"
  mkdir -p "$dir"
  cat >"$compose_file" <<'EOF'
services:
  juice-shop:
    image: bkimminich/juice-shop:latest
    container_name: bazooka-juice-shop
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"

  dvwa:
    image: vulnerables/web-dvwa:latest
    container_name: bazooka-dvwa
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"

  webgoat:
    image: webgoat/webgoat:latest
    container_name: bazooka-webgoat
    restart: unless-stopped
    ports:
      - "127.0.0.1:8081:8080"
EOF
  print_task_status "Compose file" "OK"
  log_info "Wrote lab compose file to ${compose_file}"
}

record_labs_state() {
  local state_file
  state_file="${STATE_DIR}/labs.list"

  if [[ "$DRY_RUN" == true ]]; then
    print_debug "dry-run: record lab state in ${state_file}"
    return 0
  fi

  ensure_state_paths
  cat >"$state_file" <<EOF
juice-shop|running|127.0.0.1|3000
dvwa|running|127.0.0.1|8080
webgoat|running|127.0.0.1|8081
EOF
  log_info "Recorded local lab state"
}

start_labs_compose() {
  local compose_file
  compose_file="$(labs_compose_file)"

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "Docker compose up" "DRY-RUN"
    log_info "Dry run: would run docker compose -f ${compose_file} up -d"
    return 0
  fi

  docker compose -f "$compose_file" up -d
  print_task_status "Docker compose up" "OK"
  log_info "Started local labs with Docker Compose"
}

deploy_labs() {
  local start_ts
  start_ts="$(date +%s)"

  print_task_header "Local Labs"
  print_warn "Local labs are for local learning only. They must not be exposed to public networks."

  if [[ "$DRY_RUN" != true ]]; then
    if ! docker_engine_available || ! docker_compose_available; then
      print_error "Docker Engine with Compose plugin is required. Run: bazookasetup.sh --docker"
      log_error "Labs requested without Docker Engine and Compose plugin"
      return 1
    fi
    require_root "Deploying local labs" || return "$?"
  fi

  write_labs_compose
  start_labs_compose
  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "Juice Shop 127.0.0.1:3000" "DRY-RUN"
    print_task_status "DVWA 127.0.0.1:8080" "DRY-RUN"
    print_task_status "WebGoat 127.0.0.1:8081" "DRY-RUN"
  else
    print_task_status "Juice Shop" "RUNNING 127.0.0.1:3000"
    print_task_status "DVWA" "RUNNING 127.0.0.1:8080"
    print_task_status "WebGoat" "RUNNING 127.0.0.1:8081"
  fi
  record_labs_state
  print_info "Stop labs with: docker compose -f $(labs_compose_file) down"
  print_completion "$start_ts"
}

# ============================================================================
# WORDLIST ENGINE
# ============================================================================

write_wordlist_readme() {
  local readme_path
  readme_path="${WORDLIST_DIR}/README.md"

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "README.md" "DRY-RUN"
    return 0
  fi

  cat >"$readme_path" <<'EOF'
# Bazooka Wordlists

Place authorized, legally obtained wordlists in the category directories.
Bazooka does not download leaked data or credential dumps.
Use official Ubuntu packages or files already present on this workstation.
EOF
  print_task_status "README.md" "OK"
}

restore_user_ownership() {
  local path
  path="$1"

  if [[ "$DRY_RUN" == true || ! -e "$path" ]]; then
    return 0
  fi

  if is_root && [[ -n "$BAZOOKA_USER" ]]; then
    chown -R "${BAZOOKA_USER}:" "$path"
  fi
}

symlink_if_present() {
  local source_path target_dir link_name target_path
  source_path="$1"
  target_dir="$2"
  link_name="$3"
  target_path="${target_dir}/${link_name}"

  if [[ ! -e "$source_path" ]]; then
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "$link_name" "DRY-RUN"
    log_info "Dry run: would symlink ${source_path} to ${target_path}"
    return 0
  fi

  ln -sfn "$source_path" "$target_path"
  print_task_status "$link_name" "OK"
  log_info "Linked wordlist ${source_path} to ${target_path}"
}

record_wordlists_state() {
  local state_file timestamp
  state_file="${STATE_DIR}/wordlists.list"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ "$DRY_RUN" == true ]]; then
    print_debug "dry-run: record wordlists state in ${state_file}"
    return 0
  fi

  ensure_state_paths
  cat >"$state_file" <<EOF
wordlists|ready|${WORDLIST_DIR}|${timestamp}
EOF
  log_info "Recorded wordlists state"
}

report_wordlist_package_hint() {
  local package_name
  package_name="$1"

  if package_installed "$package_name"; then
    print_task_status "$package_name" "OK"
  elif package_available "$package_name"; then
    print_task_status "$package_name" "WARN available via apt, not installed"
    log_warn "${package_name} available via apt but not installed"
  else
    print_task_status "$package_name" "WARN not available via apt"
    log_warn "${package_name} not available via apt"
  fi
}

manage_wordlists() {
  local start_ts directories linked_any dir
  start_ts="$(date +%s)"
  linked_any=false
  directories=(
    common
    web
    dns
    content-discovery
    custom
  )

  print_task_header "Wordlists"

  if [[ "$DRY_RUN" != true ]]; then
    require_root "Managing wordlists state" || return "$?"
  fi

  for dir in "${directories[@]}"; do
    if [[ "$DRY_RUN" == true ]]; then
      print_task_status "${WORDLIST_DIR}/${dir}" "DRY-RUN"
    else
      mkdir -p "${WORDLIST_DIR}/${dir}"
      print_task_status "${dir}/" "OK"
    fi
  done

  report_wordlist_package_hint "seclists"
  report_wordlist_package_hint "dirb"
  report_wordlist_package_hint "wfuzz"

  if symlink_if_present "/usr/share/wordlists/rockyou.txt" "${WORDLIST_DIR}/common" "rockyou.txt"; then
    linked_any=true
  fi
  if symlink_if_present "/usr/share/wordlists/dirb/common.txt" "${WORDLIST_DIR}/content-discovery" "dirb-common.txt"; then
    linked_any=true
  fi
  if symlink_if_present "/usr/share/wordlists/wfuzz/general/common.txt" "${WORDLIST_DIR}/web" "wfuzz-common.txt"; then
    linked_any=true
  fi
  if [[ -d "/usr/share/seclists" ]]; then
    if symlink_if_present "/usr/share/seclists" "${WORDLIST_DIR}" "seclists"; then
      linked_any=true
    fi
  fi

  if [[ "$linked_any" != true ]]; then
    print_task_status "Existing wordlists" "WARN none found, structure created"
    log_warn "No existing system wordlists found to link"
  fi

  write_wordlist_readme
  restore_user_ownership "${BAZOOKA_HOME}/bazooka"
  record_wordlists_state
  print_completion "$start_ts"
}

# ============================================================================
# HEALTH ENGINE
# ============================================================================

HEALTH_FAIL_COUNT=0
HEALTH_WARN_COUNT=0

health_status_line() {
  local label status
  label="$1"
  status="$2"

  [[ "$QUIET" == true ]] || {
    printf '%-28s ' "$label"
    case "$status" in
      PASS)
        print_color "$COLOR_GREEN" "$status"
        ;;
      WARN*)
        print_color "$COLOR_YELLOW" "$status"
        ;;
      FAIL*)
        print_color "$COLOR_RED" "$status"
        ;;
      *)
        printf '%s\n' "$status"
        ;;
    esac
  }

  case "$status" in
    WARN*)
      HEALTH_WARN_COUNT=$((HEALTH_WARN_COUNT + 1))
      log_warn "Health ${label}: ${status}"
      ;;
    FAIL*)
      HEALTH_FAIL_COUNT=$((HEALTH_FAIL_COUNT + 1))
      log_error "Health ${label}: ${status}"
      ;;
    *)
      log_info "Health ${label}: ${status}"
      ;;
  esac
}

check_internet_connectivity() {
  if command_exists curl && curl -fsSL --max-time 5 https://www.google.com/generate_204 >/dev/null 2>&1; then
    health_status_line "Internet Connectivity" "PASS" true
  elif command_exists ping && ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    health_status_line "Internet Connectivity" "PASS" true
  else
    health_status_line "Internet Connectivity" "FAIL" true
  fi
}

check_dns_resolution() {
  if command_exists getent && getent hosts ubuntu.com >/dev/null 2>&1; then
    health_status_line "DNS Resolution" "PASS"
  else
    health_status_line "DNS Resolution" "FAIL"
  fi
}

check_ubuntu_health_version() {
  local version
  version="0"

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    version="${VERSION_ID:-0}"
  fi

  if is_supported_ubuntu_version "$version"; then
    health_status_line "Ubuntu Version" "PASS"
  else
    health_status_line "Ubuntu Version" "FAIL"
  fi
}

check_disk_space() {
  local available_kb
  available_kb="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"

  if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
    health_status_line "Disk Space" "FAIL" true
  elif ((available_kb < 512000)); then
    health_status_line "Disk Space" "FAIL" true
  elif ((available_kb < 2097152)); then
    health_status_line "Disk Space" "WARN low"
  else
    health_status_line "Disk Space" "PASS"
  fi
}

check_memory_available() {
  local available_kb
  available_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || true)"

  if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
    health_status_line "Memory" "WARN unknown"
  elif ((available_kb < 262144)); then
    health_status_line "Memory" "WARN low"
  else
    health_status_line "Memory" "PASS"
  fi
}

check_apt_lock_state() {
  local locks lock_path
  locks=(
    /var/lib/dpkg/lock
    /var/lib/dpkg/lock-frontend
    /var/lib/apt/lists/lock
    /var/cache/apt/archives/lock
  )

  if ! command_exists fuser; then
    # CHECK: apt lock detection is best-effort without fuser from psmisc.
    health_status_line "APT State" "WARN fuser unavailable"
    return 0
  fi

  for lock_path in "${locks[@]}"; do
    if [[ -e "$lock_path" ]] && fuser "$lock_path" >/dev/null 2>&1; then
      health_status_line "APT State" "FAIL lock held" true
      return 0
    fi
  done

  if command_exists apt-get && apt-get check >/dev/null 2>&1; then
    health_status_line "APT State" "PASS"
  else
    health_status_line "APT State" "FAIL" true
  fi
}

check_dpkg_state() {
  local audit_output
  audit_output="$(dpkg --audit 2>/dev/null || true)"

  if [[ -z "$audit_output" ]]; then
    health_status_line "DPKG State" "PASS"
  else
    health_status_line "DPKG State" "FAIL" true
  fi
}

check_required_commands() {
  local commands missing cmd
  commands=(curl git dpkg apt-get)
  missing=()

  for cmd in "${commands[@]}"; do
    if ! command_exists "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if ((${#missing[@]} == 0)); then
    health_status_line "Required Commands" "PASS"
  else
    health_status_line "Required Commands" "WARN missing: $(join_by ', ' "${missing[@]}")"
  fi
}

check_docker_health() {
  if ! docker_engine_available; then
    health_status_line "Docker Engine" "WARN not installed"
    return 0
  fi

  if docker_service_active; then
    health_status_line "Docker Engine" "PASS"
  else
    health_status_line "Docker Engine" "WARN installed, not active"
  fi
}

check_docker_user_access() {
  if id -nG "$BAZOOKA_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    health_status_line "Docker User Access" "PASS"
  elif docker_engine_available; then
    health_status_line "Docker User Access" "WARN user not in docker group"
  else
    health_status_line "Docker User Access" "WARN docker not installed"
  fi
}

check_state_and_log_paths() {
  if [[ -d "$STATE_DIR" && -w "$STATE_DIR" ]]; then
    health_status_line "State Directory" "PASS"
  elif [[ -d "$STATE_DIR" ]]; then
    health_status_line "State Directory" "WARN not writable"
  else
    health_status_line "State Directory" "WARN missing"
  fi

  if [[ -f "$LOG_FILE" && -w "$LOG_FILE" ]]; then
    health_status_line "Log File" "PASS"
  elif [[ -f "$LOG_FILE" ]]; then
    health_status_line "Log File" "WARN not writable"
  else
    health_status_line "Log File" "WARN missing"
  fi
}

run_healthcheck() {
  local overall
  HEALTH_FAIL_COUNT=0
  HEALTH_WARN_COUNT=0

  [[ "$QUIET" == true ]] || {
    printf 'Health Report\n'
    print_rule
    printf '\n'
  }

  check_internet_connectivity
  check_dns_resolution
  check_ubuntu_health_version
  check_apt_lock_state
  check_disk_space
  check_memory_available
  check_dpkg_state
  check_required_commands
  check_docker_health
  check_docker_user_access
  check_state_and_log_paths

  if ((HEALTH_FAIL_COUNT > 0)); then
    overall="UNHEALTHY"
  elif ((HEALTH_WARN_COUNT > 0)); then
    overall="DEGRADED"
  else
    overall="HEALTHY"
  fi

  [[ "$QUIET" == true ]] || {
    printf '\n'
    printf '%-28s ' "Overall Status"
    case "$overall" in
      HEALTHY)
        print_color "$COLOR_GREEN" "$overall"
        ;;
      DEGRADED)
        print_color "$COLOR_YELLOW" "$overall"
        ;;
      *)
        print_color "$COLOR_RED" "$overall"
        ;;
    esac
  }

  log_info "Healthcheck completed with status ${overall}"

  if ((HEALTH_FAIL_COUNT > 0)); then
    return 1
  fi
  return 0
}

# ============================================================================
# STATUS ENGINE
# ============================================================================

ubuntu_version_short() {
  local version
  version="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    version="${VERSION_ID:-unknown}"
  fi
  printf '%s' "$version"
}

installed_profiles_summary() {
  local state_file profiles
  state_file="${STATE_DIR}/profiles.list"

  if [[ ! -r "$state_file" ]]; then
    printf 'none'
    return 0
  fi

  profiles="$(awk -F'|' 'NF >= 1 {if (out) out = out ", " $1; else out = $1} END {print out}' "$state_file")"
  if [[ -z "$profiles" ]]; then
    printf 'none'
  else
    printf '%s' "$profiles"
  fi
}

docker_status_summary() {
  if docker_service_active; then
    printf 'active'
  elif docker_engine_available; then
    printf 'installed'
  else
    printf 'not installed'
  fi
}

memory_usage_summary() {
  if command_exists free; then
    free -h | awk '/Mem:/ {print "used " $3 " / total " $2}'
  else
    printf 'unknown'
  fi
}

disk_usage_summary() {
  df -h / 2>/dev/null | awk 'NR==2 {print $3 " used / " $2 " total (" $5 ")"}'
}

system_command_summary() {
  if [[ -x "$SYSTEM_INSTALL_PATH" ]]; then
    printf '%s' "$SYSTEM_INSTALL_PATH"
  else
    printf 'not installed'
  fi
}

show_status() {
  local host kernel arch shell_name uptime_text script_realpath
  host="$(hostname 2>/dev/null || printf 'unknown')"
  kernel="$(uname -r 2>/dev/null || printf 'unknown')"
  arch="$(uname -m 2>/dev/null || printf 'unknown')"
  shell_name="${SHELL:-unknown}"
  uptime_text="$(uptime -p 2>/dev/null || printf 'unknown')"
  script_realpath="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || printf '%s' "$SCRIPT_PATH")"

  printf 'Status Dashboard\n'
  print_rule
  printf '\n'
  print_kv "Version" "$BAZOOKA_VERSION"
  print_kv "Maintainer" "$BAZOOKA_MAINTAINER"
  print_kv "Repository" "$BAZOOKA_REPOSITORY"
  print_kv "Repository URL" "$BAZOOKA_REPOSITORY_URL"
  print_kv "Hostname" "$host"
  print_kv "Ubuntu" "$(ubuntu_version_short)"
  print_kv "Kernel" "$kernel"
  print_kv "Architecture" "$arch"
  print_kv "Docker" "$(docker_status_summary)"
  print_kv "Installed Profiles" "$(installed_profiles_summary)"
  print_kv "State Directory" "$STATE_DIR"
  print_kv "Log File" "$LOG_FILE"
  print_kv "Script Path" "$script_realpath"
  print_kv "System Command Path" "$(system_command_summary)"
  print_kv "Current User" "$BAZOOKA_USER"
  print_kv "Shell" "$shell_name"
  print_kv "Uptime" "$uptime_text"
  print_kv "Disk Usage" "$(disk_usage_summary)"
  print_kv "Memory Usage" "$(memory_usage_summary)"
  log_info "Status dashboard displayed"
}

# ============================================================================
# REPAIR ENGINE
# ============================================================================

run_repair_step() {
  local label
  label="$1"
  shift

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "$label" "DRY-RUN"
    log_info "Dry run: would run repair step ${label}: $*"
    return 0
  fi

  if "$@"; then
    print_task_status "$label" "OK"
    log_info "Repair step succeeded: ${label}"
    return 0
  fi

  print_task_status "$label" "FAILED"
  log_error "Repair step failed: ${label}"
  return 1
}

repair_environment() {
  local start_ts failed
  start_ts="$(date +%s)"
  failed=0

  print_task_header "Repair Environment"

  if [[ "$DRY_RUN" != true ]]; then
    require_root "Repair environment" || return "$?"
  fi

  if [[ "$ASSUME_YES" != true && "$DRY_RUN" != true ]]; then
    if ! confirm "Run safe APT and Bazooka state repair steps?"; then
      print_task_status "Repair" "WARN cancelled"
      return 0
    fi
  fi

  run_repair_step "apt update" env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Lock::Timeout=60 update || failed=1
  run_repair_step "dpkg configure" dpkg --configure -a || failed=1
  run_repair_step "fix broken packages" env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Lock::Timeout=60 --fix-broken install -y || failed=1
  run_repair_step "apt autoremove" env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Lock::Timeout=60 autoremove -y || failed=1
  run_repair_step "state directory" mkdir -p "$STATE_DIR" || failed=1
  run_repair_step "log file" touch "$LOG_FILE" || failed=1

  if [[ "$DRY_RUN" != true ]]; then
    chmod 0755 "$STATE_DIR" || failed=1
    chmod 0644 "$LOG_FILE" || failed=1
  fi

  print_completion "$start_ts"
  return "$failed"
}

# ============================================================================
# WORKSPACE ENGINE
# ============================================================================

validate_project_name() {
  local project_name
  project_name="$1"

  if [[ -z "$project_name" ]]; then
    print_error "Workspace name cannot be empty."
    return 1
  fi

  if [[ "$project_name" == *".."* || "$project_name" == */* || "$project_name" == "\\"* ]]; then
    print_error "Workspace name must not contain path traversal or path separators."
    return 1
  fi

  if [[ ! "$project_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    print_error "Workspace name may only contain letters, numbers, dot, underscore, and hyphen."
    return 1
  fi
}

write_file_if_missing() {
  local file_path
  file_path="$1"
  shift

  if [[ -e "$file_path" ]]; then
    print_task_status "$(safe_basename "$file_path")" "WARN exists, kept"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "$(safe_basename "$file_path")" "DRY-RUN"
    return 0
  fi

  printf '%s\n' "$@" >"$file_path"
  print_task_status "$(safe_basename "$file_path")" "OK"
}

create_workspace() {
  local project_name workspace_path directories dir
  project_name="$COMMAND_ARG"
  workspace_path="${WORKSPACE_DIR}/${project_name}"
  directories=(
    notes
    screenshots
    findings
    reports
    evidence
    references
    scope
    archive
  )

  if ! validate_project_name "$project_name"; then
    exit "$EXIT_USAGE"
  fi

  if [[ -d "$workspace_path" ]]; then
    print_warn "Workspace already exists. Existing files will not be overwritten."
  fi

  print_task_header "Workspace Created"

  if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$workspace_path"
  fi

  for dir in "${directories[@]}"; do
    if [[ "$DRY_RUN" == true ]]; then
      print_task_status "$dir/" "DRY-RUN"
    else
      mkdir -p "${workspace_path}/${dir}"
      print_task_status "$dir/" "OK"
    fi
  done

  write_file_if_missing "${workspace_path}/README.md" \
    "# ${project_name}" \
    "" \
    "Authorized security workspace for notes, scope, findings, evidence references, and final reports."
  write_file_if_missing "${workspace_path}/scope/scope.md" \
    "# Scope" \
    "" \
    "## In Scope" \
    "" \
    "## Out of Scope" \
    "" \
    "## Authorization Notes"
  write_file_if_missing "${workspace_path}/notes/notes.md" \
    "# Notes" \
    "" \
    "Record dated observations and commands relevant to the authorized engagement."
  write_file_if_missing "${workspace_path}/findings/findings.md" \
    "# Findings" \
    "" \
    "## Finding Title" \
    "" \
    "- Severity:" \
    "- Affected Asset:" \
    "- Evidence:" \
    "- Recommendation:"

  restore_user_ownership "${BAZOOKA_HOME}/bazooka"

  printf '\n'
  print_kv "Name" "$project_name"
  print_kv "Location" "${WORKSPACE_DIR}/${project_name}"
  print_kv "Directories" "8"
  if [[ "$DRY_RUN" == true ]]; then
    print_kv "Status" "DRY-RUN"
  else
    print_kv "Status" "READY"
  fi
  log_info "Workspace prepared: ${workspace_path}"
}

# ============================================================================
# REPORT ENGINE
# ============================================================================

generate_report_template() {
  local report_file timestamp
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  report_file="${REPORT_DIR}/report-${timestamp}.md"

  print_task_header "Report Template"

  if [[ "$DRY_RUN" == true ]]; then
    print_kv "Path" "$report_file"
    print_kv "Status" "DRY-RUN"
    log_info "Dry run: would generate report template ${report_file}"
    return 0
  fi

  mkdir -p "$REPORT_DIR"
  cat >"$report_file" <<'EOF'
# Security Assessment Report

## Executive Summary
Summarize the authorized assessment, business context, and key outcomes.

## Scope
Define approved targets, exclusions, dates, and authorization boundaries.

## Rules of Engagement
Document permitted testing methods, contact paths, and stop conditions.

## Methodology
Describe the high-level approach and validation process.

## Findings Summary
List findings by title, severity, status, and affected asset.

## Detailed Findings
Provide one structured subsection per finding with evidence and impact.

## Risk Rating
Define the rating model used and explain severity assignments.

## Evidence
Reference screenshots, logs, reproduction notes, and supporting material.

## Recommendations
Provide prioritized remediation guidance and validation steps.

## Appendix
Include supporting notes, tool versions, assumptions, and references.
EOF
  restore_user_ownership "$REPORT_DIR"
  print_kv "Path" "$report_file"
  print_kv "Status" "READY"
  log_info "Generated report template: ${report_file}"
}

# ============================================================================
# BACKUP ENGINE
# ============================================================================

human_size() {
  local file_path
  file_path="$1"

  if command_exists du; then
    du -h "$file_path" 2>/dev/null | awk '{print $1}'
  else
    wc -c <"$file_path" 2>/dev/null || printf 'unknown'
  fi
}

backup_state() {
  local start_ts timestamp backup_file tmp_dir
  start_ts="$(date +%s)"
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  backup_file="${BACKUP_DIR}/bazooka-state-${timestamp}.tar.gz"
  tmp_dir=""

  print_task_header "Backup State"

  if [[ "$DRY_RUN" == true ]]; then
    print_kv "Backup" "$backup_file"
    print_kv "Status" "DRY-RUN"
    log_info "Dry run: would back up Bazooka state metadata to ${backup_file}"
    print_completion "$start_ts"
    return 0
  fi

  require_root "Backing up Bazooka state" || return "$?"
  mkdir -p "$BACKUP_DIR"
  tmp_dir="$(mktemp -d)"
  mkdir -p "${tmp_dir}/state"

  if [[ -d "$STATE_DIR" ]]; then
    find "$STATE_DIR" -maxdepth 1 -type f -name '*.list' -exec cp -a {} "${tmp_dir}/state/" \;
    if [[ -d "${STATE_DIR}/labs" ]]; then
      mkdir -p "${tmp_dir}/state/labs"
      find "${STATE_DIR}/labs" -maxdepth 1 -type f -name '*.yml' -exec cp -a {} "${tmp_dir}/state/labs/" \;
    fi
  fi

  cat >"${tmp_dir}/manifest.txt" <<EOF
name=bazooka-state
created=${timestamp}
source=${STATE_DIR}
note=metadata-only; workspace findings and evidence are not included
EOF

  tar -C "$tmp_dir" -czf "$backup_file" .
  rm -rf "$tmp_dir"
  restore_user_ownership "$BACKUP_DIR"

  print_kv "Backup" "$(safe_basename "$backup_file")"
  print_kv "Size" "$(human_size "$backup_file")"
  print_kv "Location" "$backup_file"
  print_kv "Timestamp" "$timestamp"
  log_info "Created state backup: ${backup_file}"
  print_completion "$start_ts"
}

# ============================================================================
# RESTORE ENGINE
# ============================================================================

list_backup_files() {
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'bazooka-state-*.tar.gz' 2>/dev/null | sort
}

select_backup_file() {
  local backups count index selected
  mapfile -t backups < <(list_backup_files)
  count="${#backups[@]}"

  if ((count == 0)); then
    print_error "No backups found in ${BACKUP_DIR}."
    return 1
  fi

  print_task_header "Available Backups" >&2
  for index in "${!backups[@]}"; do
    printf '%02d  %-38s %s\n' "$((index + 1))" "$(safe_basename "${backups[$index]}")" "$(human_size "${backups[$index]}")" >&2
  done
  printf '\n' >&2

  if [[ "$ASSUME_YES" == true && "$count" -eq 1 ]]; then
    printf '%s' "${backups[0]}"
    return 0
  fi

  printf 'Selection: ' >&2
  read -r selected
  if [[ ! "$selected" =~ ^[0-9]+$ ]] || ((selected < 1 || selected > count)); then
    print_error "Invalid backup selection."
    return 1
  fi

  printf '%s' "${backups[$((selected - 1))]}"
}

restore_state() {
  local start_ts backup_file tmp_dir restored_profiles profile package_name missing_profiles
  start_ts="$(date +%s)"
  tmp_dir=""
  missing_profiles=()

  if ! backup_file="$(select_backup_file)"; then
    exit "$EXIT_NOT_FOUND"
  fi
  printf '\n'
  print_kv "Selected" "$backup_file"

  if [[ "$DRY_RUN" == true ]]; then
    print_kv "Status" "DRY-RUN"
    log_info "Dry run: would restore Bazooka metadata from ${backup_file}"
    print_completion "$start_ts"
    return 0
  fi

  require_root "Restoring Bazooka state" || return "$?"
  tmp_dir="$(mktemp -d)"
  tar -C "$tmp_dir" -xzf "$backup_file"
  mkdir -p "$STATE_DIR"

  if [[ -d "${tmp_dir}/state" ]]; then
    cp -a "${tmp_dir}/state/." "$STATE_DIR/"
  fi
  rm -rf "$tmp_dir"

  print_kv "Status" "RESTORED"

  if [[ -r "${STATE_DIR}/profiles.list" ]]; then
    restored_profiles="$(awk -F'|' 'NF >= 1 {print $1}' "${STATE_DIR}/profiles.list")"
    while IFS= read -r profile; do
      [[ -z "$profile" ]] && continue
      case "$profile" in
        minimal) package_name="curl" ;;
        recon) package_name="nmap" ;;
        web) package_name="sqlmap" ;;
        docker) package_name="docker-ce" ;;
        *) package_name="" ;;
      esac
      if [[ -n "$package_name" ]] && ! package_installed "$package_name"; then
        missing_profiles+=("$profile")
      fi
    done <<<"$restored_profiles"
  fi

  if ((${#missing_profiles[@]} > 0)); then
    print_warn "Restored metadata references profiles not installed on this system: $(join_by ', ' "${missing_profiles[@]}")"
    print_info "Run the related Bazooka profile commands manually after reviewing scope and authorization."
  fi

  log_info "Restored state from backup: ${backup_file}"
  print_completion "$start_ts"
}

# ============================================================================
# BENCHMARK ENGINE
# ============================================================================

elapsed_seconds() {
  local start_ns end_ns diff_ns
  start_ns="$1"
  end_ns="$2"
  diff_ns=$((end_ns - start_ns))
  awk -v ns="$diff_ns" 'BEGIN {printf "%.3f", ns / 1000000000}'
}

throughput_mbps() {
  local megabytes seconds
  megabytes="$1"
  seconds="$2"
  awk -v mb="$megabytes" -v sec="$seconds" 'BEGIN {if (sec > 0) printf "%.1f", mb / sec; else printf "0.0"}'
}

run_benchmark() {
  local start_ts start_ns end_ns cpu_seconds disk_file write_seconds read_seconds docker_seconds
  start_ts="$(date +%s)"
  disk_file="/tmp/bazooka-benchmark-$$.bin"

  print_task_header "Benchmark"

  start_ns="$(date +%s%N)"
  local i total
  total=0
  for ((i = 0; i < 200000; i++)); do
    total=$(((total + i) % 1000003))
  done
  end_ns="$(date +%s%N)"
  cpu_seconds="$(elapsed_seconds "$start_ns" "$end_ns")"
  print_kv "CPU Loop" "${cpu_seconds}s"

  start_ns="$(date +%s%N)"
  dd if=/dev/zero of="$disk_file" bs=1M count=32 conv=fsync status=none
  end_ns="$(date +%s%N)"
  write_seconds="$(elapsed_seconds "$start_ns" "$end_ns")"
  print_kv "Disk Write" "$(throughput_mbps 32 "$write_seconds") MB/s"

  start_ns="$(date +%s%N)"
  dd if="$disk_file" of=/dev/null bs=1M status=none
  end_ns="$(date +%s%N)"
  read_seconds="$(elapsed_seconds "$start_ns" "$end_ns")"
  rm -f "$disk_file"
  print_kv "Disk Read" "$(throughput_mbps 32 "$read_seconds") MB/s"

  if command_exists free; then
    print_kv "Memory" "$(memory_usage_summary)"
  else
    print_kv "Memory" "unknown"
  fi

  if docker_engine_available; then
    start_ns="$(date +%s%N)"
    docker ps >/dev/null 2>&1 || true
    end_ns="$(date +%s%N)"
    docker_seconds="$(elapsed_seconds "$start_ns" "$end_ns")"
    print_kv "Docker Response" "${docker_seconds}s"
  else
    print_kv "Docker Response" "not installed"
  fi

  log_info "Benchmark completed"
  print_completion "$start_ts"
}

# ============================================================================
# UPDATE ENGINE
# ============================================================================

update_bazooka() {
  local latest_version

  print_task_header "Update Bazooka"

  if [[ -z "$BAZOOKA_UPDATE_URL" && -z "$BAZOOKA_RELEASE_API_URL" ]]; then
    print_info "Update source is not configured."
    log_warn "Update requested but source is not configured"
    return 0
  fi

  if [[ -n "$BAZOOKA_RELEASE_API_URL" ]]; then
    require_command curl
    latest_version="$(curl -fsSL "$BAZOOKA_RELEASE_API_URL" | grep -Eo '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed -E 's/.*"([^"]+)"/\1/' || true)"
    print_kv "Current Version" "$BAZOOKA_VERSION"
    print_kv "Latest Version" "${latest_version:-unknown}"
  fi

  if [[ -n "$BAZOOKA_UPDATE_URL" ]]; then
    print_kv "Update URL" "$BAZOOKA_UPDATE_URL"
    if [[ "$DRY_RUN" == true ]]; then
      print_kv "Status" "DRY-RUN"
      return 0
    fi
    print_info "Download and replacement are intentionally conservative. Review the release source before replacing the installed script."
  fi
}

# ============================================================================
# UNINSTALL ENGINE
# ============================================================================

uninstall_bazooka() {
  local start_ts remove_user_data
  start_ts="$(date +%s)"
  remove_user_data=false

  print_task_header "Uninstall"
  print_info "This removes Bazooka system command and managed state."
  print_info "Docker and system packages will not be removed automatically."

  if [[ "$DRY_RUN" != true ]]; then
    require_root "Uninstalling Bazooka" || return "$?"
  fi

  if [[ "$ASSUME_YES" != true && "$DRY_RUN" != true ]]; then
    if ! confirm "Remove ${SYSTEM_INSTALL_PATH} and ${STATE_DIR}?"; then
      print_task_status "Uninstall" "WARN cancelled"
      return 0
    fi
  fi

  if [[ "$DRY_RUN" != true ]]; then
    if [[ "$ASSUME_YES" == true ]]; then
      print_warn "Workspaces and reports are kept. Removing them requires an explicit additional confirmation."
    elif confirm "Also remove all workspaces and reports?"; then
      remove_user_data=true
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    print_task_status "$SYSTEM_INSTALL_PATH" "DRY-RUN"
    print_task_status "$STATE_DIR" "DRY-RUN"
    print_info "Manual package removal, if desired: review Docker and apt packages separately."
    print_completion "$start_ts"
    return 0
  fi

  rm -f "$SYSTEM_INSTALL_PATH"
  rm -rf "$STATE_DIR"
  print_task_status "$SYSTEM_INSTALL_PATH" "OK"
  print_task_status "$STATE_DIR" "OK"

  if [[ "$remove_user_data" == true ]]; then
    rm -rf "$WORKSPACE_DIR" "$REPORT_DIR"
    print_task_status "Workspaces and reports" "OK"
  else
    print_task_status "Workspaces and reports" "WARN kept"
  fi

  print_info "Manual package removal, if desired: review Docker and apt packages separately."
  log_warn "Bazooka uninstall completed"
  print_completion "$start_ts"
}

install_system_command() {
  require_command install

  print_info "Installing Bazooka system command"
  print_rule
  print_kv "Source" "$SCRIPT_PATH"
  print_kv "Destination" "$SYSTEM_INSTALL_PATH"
  if [[ -x "$SCRIPT_PATH" ]]; then
    print_kv "Executable" "yes"
  else
    print_kv "Executable" "no"
    print_error "Run chmod +x ${SCRIPT_PATH} before installing Bazooka."
    return "$EXIT_USAGE"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    print_kv "Status" "DRY-RUN"
    log_info "Dry run: would install ${SCRIPT_PATH} to ${SYSTEM_INSTALL_PATH}"
    return 0
  fi

  require_root "System installation" || return "$?"

  install -m 0755 "$SCRIPT_PATH" "$SYSTEM_INSTALL_PATH"
  print_kv "Status" "INSTALLED"
  log_info "Installed system command at ${SYSTEM_INSTALL_PATH}"
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

show_menu() {
  printf '\n'
  print_color "$COLOR_CYAN" "BAZOOKA"
  printf '%s\n\n' "$BAZOOKA_TAGLINE"
  print_warn "AUTHORIZED USE ONLY"
  printf '\n'
  printf '[ Workstation ]\n\n'
  printf '01  Minimal Profile              Core packages and base tooling\n'
  printf '02  Recon Profile                Authorized reconnaissance utilities\n'
  printf '03  Web Profile                  Web security testing environment\n'
  printf '04  Full Deployment              Install all supported profiles\n\n'
  printf '[ Labs ]\n\n'
  printf '05  Docker Engine                Install and configure Docker\n'
  printf '06  Local Labs                   Deploy local-only training labs\n'
  printf '07  Wordlists                    Manage local wordlist collections\n\n'
  printf '[ Management ]\n\n'
  printf '08  Status Dashboard             System and profile overview\n'
  printf '09  Health Check                 Validate workstation readiness\n'
  printf '10  Repair Environment           Fix package and dependency issues\n'
  printf '11  Backup State                 Save Bazooka workstation state\n'
  printf '12  Restore State                Restore saved workstation state\n'
  printf '13  Benchmark                    Basic local system benchmark\n\n'
  printf '[ Workspace ]\n\n'
  printf '14  Create Workspace             Project directory structure\n'
  printf '15  Report Template              Generate Markdown report template\n\n'
  printf '[ System ]\n\n'
  printf '16  Update Bazooka               Check configured release source\n'
  printf '17  Uninstall                    Remove Bazooka-managed state\n'
  printf '00  Exit\n\n'
}

read_menu_selection() {
  local selection workspace_name

  while true; do
    show_menu
    printf 'Selection: '
    read -r selection
    printf '\n'

    case "$selection" in
      1 | 01) profile_minimal ;;
      2 | 02) profile_recon ;;
      3 | 03) profile_web ;;
      4 | 04) profile_all ;;
      5 | 05) install_docker_engine ;;
      6 | 06) deploy_labs ;;
      7 | 07) manage_wordlists ;;
      8 | 08) show_status ;;
      9 | 09) run_healthcheck || true ;;
      10) repair_environment ;;
      11) backup_state ;;
      12) restore_state ;;
      13) run_benchmark ;;
      14)
        printf 'Workspace name: '
        read -r workspace_name
        COMMAND_ARG="$workspace_name"
        create_workspace
        ;;
      15) generate_report_template ;;
      16) update_bazooka ;;
      17) uninstall_bazooka ;;
      0 | 00)
        print_info "Exiting."
        return 0
        ;;
      *)
        print_warn "Invalid selection."
        ;;
    esac

    printf '\n'
    printf 'Press Enter to continue...'
    read -r _
  done
}

run_interactive() {
  INTERACTIVE_MODE=true
  print_banner
  printf '\n'
  print_status_box "interactive" "ready"
  read_menu_selection
}

# ============================================================================
# CLI PARSER
# ============================================================================

show_help() {
  cat <<'EOF'
Bazooka - Ubuntu Security Workstation Manager

Maintainer: voxynoxy
Repository: https://github.com/voxynoxy/bazooka-workstation

AUTHORIZED USE ONLY
Bazooka supports authorized cybersecurity learning, CTF preparation, local lab
work, defensive research, workstation maintenance, and professional reporting.
Do not use this tool to support unauthorized access, credential theft, malware,
phishing, persistence, evasion, or attacks against systems without permission.

Usage:
  bazookasetup.sh [global flags] [command]
  bazookasetup.sh [global flags] --workspace PROJECT_NAME

Global flags:
  --help             Show this help output
  --version          Show version information
  --dry-run          Show intended changes without applying them
  --no-color         Disable ANSI color output
  --verbose          Enable debug output
  --quiet            Suppress non-essential output
  --yes              Assume yes for confirmation prompts
  --install-system   Install command to /usr/local/bin/bazookasetup

Workstation commands:
  --minimal          Core packages and base tooling
  --recon            Authorized reconnaissance utilities
  --web              Web security testing environment
  --all              Install all supported profiles

Labs commands:
  --docker           Install and configure Docker Engine
  --labs             Deploy local-only training labs
  --wordlists        Manage local wordlist collections

Management commands:
  --status           System and profile overview
  --healthcheck      Validate workstation readiness
  --repair           Fix package and dependency issues
  --backup           Save Bazooka workstation state
  --restore          Restore saved workstation state
  --benchmark        Basic local system benchmark

Workspace commands:
  --workspace NAME   Create project directory structure
  --report-template  Generate Markdown report template

System commands:
  --update           Check configured release source
  --uninstall        Remove Bazooka-managed state

Examples:
  bazookasetup.sh
  bazookasetup.sh --dry-run --minimal
  bazookasetup.sh --workspace client-authorized-assessment
  sudo bazookasetup.sh --install-system
EOF
}

show_version() {
  printf '%s %s\n' "$BAZOOKA_NAME" "$BAZOOKA_VERSION"
  printf 'Maintainer: %s\n' "$BAZOOKA_MAINTAINER"
  printf 'Repository: %s\n' "$BAZOOKA_REPOSITORY"
  printf 'Repository URL: %s\n' "$BAZOOKA_REPOSITORY_URL"
}

set_command() {
  local new_command new_arg
  new_command="$1"
  new_arg="${2:-}"

  if [[ -n "$COMMAND" ]]; then
    print_error "Only one command may be specified per run: ${COMMAND} and ${new_command}"
    exit "$EXIT_USAGE"
  fi

  COMMAND="$new_command"
  COMMAND_ARG="$new_arg"
}

parse_cli() {
  while (($# > 0)); do
    case "$1" in
      --help)
        show_help
        exit "$EXIT_SUCCESS"
        ;;
      --version)
        show_version
        exit "$EXIT_SUCCESS"
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      --no-color)
        NO_COLOR=true
        disable_colors
        ;;
      --verbose)
        VERBOSE=true
        ;;
      --quiet)
        QUIET=true
        ;;
      --yes)
        ASSUME_YES=true
        ;;
      --install-system)
        set_command "install-system"
        ;;
      --minimal)
        set_command "minimal"
        ;;
      --recon)
        set_command "recon"
        ;;
      --web)
        set_command "web"
        ;;
      --docker)
        set_command "docker"
        ;;
      --labs)
        set_command "labs"
        ;;
      --wordlists)
        set_command "wordlists"
        ;;
      --all)
        set_command "all"
        ;;
      --status)
        set_command "status"
        ;;
      --healthcheck)
        set_command "healthcheck"
        ;;
      --repair)
        set_command "repair"
        ;;
      --backup)
        set_command "backup"
        ;;
      --restore)
        set_command "restore"
        ;;
      --benchmark)
        set_command "benchmark"
        ;;
      --workspace)
        shift
        if [[ $# -eq 0 || -z "${1:-}" ]]; then
          print_error "--workspace requires PROJECT_NAME"
          exit "$EXIT_USAGE"
        fi
        set_command "workspace" "$1"
        ;;
      --report-template)
        set_command "report-template"
        ;;
      --update)
        set_command "update"
        ;;
      --uninstall)
        set_command "uninstall"
        ;;
      --)
        shift
        break
        ;;
      -*)
        print_error "Unknown option: $1"
        exit "$EXIT_USAGE"
        ;;
      *)
        print_error "Unexpected argument: $1"
        exit "$EXIT_USAGE"
        ;;
    esac
    shift
  done

  if (($# > 0)); then
    print_error "Unexpected trailing arguments: $*"
    exit "$EXIT_USAGE"
  fi
}

route_command() {
  case "$COMMAND" in
    "")
      run_interactive
      ;;
    install-system)
      install_system_command
      ;;
    minimal)
      profile_minimal
      ;;
    recon)
      profile_recon
      ;;
    web)
      profile_web
      ;;
    docker)
      install_docker_engine
      ;;
    labs)
      deploy_labs
      ;;
    wordlists)
      manage_wordlists
      ;;
    all)
      profile_all
      ;;
    status)
      show_status
      ;;
    healthcheck)
      if run_healthcheck; then
        exit "$EXIT_SUCCESS"
      fi
      exit "$EXIT_HEALTH_UNHEALTHY"
      ;;
    repair)
      repair_environment
      ;;
    backup)
      backup_state
      ;;
    restore)
      restore_state
      ;;
    benchmark)
      run_benchmark
      ;;
    workspace)
      create_workspace
      ;;
    report-template)
      generate_report_template
      ;;
    update)
      update_bazooka
      ;;
    uninstall)
      uninstall_bazooka
      ;;
    *)
      print_error "Internal routing error for command: $COMMAND"
      exit "$EXIT_GENERAL_ERROR"
      ;;
  esac
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local route_status
  trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
  trap cleanup EXIT
  trap on_interrupt INT
  trap on_interrupt TERM

  parse_cli "$@"

  if [[ "$COMMAND" != "" && "$COMMAND" != "install-system" ]]; then
    if ! detect_os; then
      exit "$EXIT_USAGE"
    fi
  elif [[ "$COMMAND" == "" ]]; then
    if ! detect_os; then
      exit "$EXIT_USAGE"
    fi
  fi

  log_debug "Starting ${BAZOOKA_NAME} ${BAZOOKA_VERSION}"
  if route_command; then
    exit "$EXIT_SUCCESS"
  else
    route_status="$?"
    exit "$route_status"
  fi
}

main "$@"

# ============================================================
# MANUAL VERIFICATION CHECKLIST
# ============================================================
# 1. Line ~14: Verify BAZOOKA_UPDATE_URL and BAZOOKA_RELEASE_API_URL before
#    enabling remote update behavior.
#    Category: [REPO URL]
#
# 2. Line ~62: Verify package names at runtime with apt-cache policy on each
#    supported Ubuntu release before non-dry-run profile installation.
#    Category: [PACKAGE AVAILABILITY]
#
# 3. Line ~662: Verify optional profile packages that vary between Ubuntu
#    releases or configured apt repositories.
#    Category: [PACKAGE AVAILABILITY]
#
# 4. Line ~918: Verify Docker official apt repository availability, package
#    names, and Ubuntu codename compatibility before release testing.
#    Category: [REPO URL]
#
# 5. Line ~1324: Verify apt lock detection behavior when fuser is unavailable;
#    fuser is typically provided by the psmisc package.
#    Category: [COMMAND SYNTAX]

# ============================================================
# FINAL REVIEW SUMMARY
# ============================================================
# 1. SHELLCHECK / REVIEW MANUAL: PASS
#    shellcheck was not installed in this environment. Manual review covered
#    quoted variables, command substitution, "$@" handling, array joins under
#    strict IFS, trap behavior, and controlled non-zero exits.
#
# 2. SECTION STRUCTURE CONSISTENCY: FIXED
#    Removed extra top-level section headers and made help/version helpers part
#    of CLI PARSER so the section order matches the requested structure.
#
# 3. CENTRALIZED CHECK COMMENTS: PASS
#    All inline CHECK comments are summarized in MANUAL VERIFICATION CHECKLIST.
#
# 4. AUDIT EXIT CODE: FIXED
#    Added an exit code contract in CONSTANTS and wired usage, privilege,
#    healthcheck unhealthy, restore-without-backup, and interrupt paths to it.
#
# 5. GLOBAL FLAGS CONSISTENCY AUDIT: PASS
#    Command matrix: --minimal dry-run PASS, yes N-A, verbose PASS, quiet PASS,
#    no-color PASS; --recon dry-run PASS, yes PASS for optional prompt, verbose
#    PASS, quiet PASS, no-color PASS; --web dry-run PASS, yes N-A, verbose PASS,
#    quiet PASS, no-color PASS; --docker dry-run PASS, yes PASS, verbose PASS,
#    quiet PASS, no-color PASS; --labs dry-run PASS, yes N-A, verbose PASS,
#    quiet PASS, no-color PASS; --wordlists dry-run PASS, yes N-A, verbose PASS,
#    quiet PASS, no-color PASS; --all dry-run PASS, yes PASS, verbose PASS,
#    quiet PASS, no-color PASS; --status dry-run N-A, yes N-A, verbose N-A,
#    quiet N-A, no-color PASS; --healthcheck dry-run N-A, yes N-A, verbose PASS,
#    quiet PASS, no-color PASS; --repair dry-run PASS, yes PASS, verbose PASS,
#    quiet PASS, no-color PASS; --backup dry-run PASS, yes N-A, verbose PASS,
#    quiet PASS, no-color PASS; --restore dry-run PASS, yes PASS when only one
#    backup exists, verbose PASS, quiet PASS, no-color PASS; --benchmark dry-run
#    N-A, yes N-A, verbose PASS, quiet PASS, no-color PASS; --workspace dry-run
#    PASS, yes N-A, verbose PASS, quiet PASS, no-color PASS; --report-template
#    dry-run PASS, yes N-A, verbose PASS, quiet PASS, no-color PASS; --update
#    dry-run PASS when configured, yes N-A, verbose PASS, quiet PASS, no-color
#    PASS; --uninstall dry-run PASS, yes PASS for primary removal prompt,
#    verbose PASS, quiet PASS, no-color PASS.
#
# 6. STYLE AND SAFETY FINAL CHECK: PASS
#    No emoji or prohibited marketing-style copy was added. AUTHORIZED USE ONLY
#    appears in interactive banner/menu and --help. The script provisions local
#    workstation tooling, local-only labs, state management, and reporting; it
#    does not implement exploitation workflow, credential theft, persistence,
#    evasion, malware, or public-target automation.
