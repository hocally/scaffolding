#!/usr/bin/env bash

log() {
  printf '[bootstrap] %s\n' "$*"
}

warn() {
  printf '[bootstrap] warning: %s\n' "$*" >&2
}

die() {
  printf '[bootstrap] error: %s\n' "$*" >&2
  exit 1
}

die_action() {
  local message="$1"
  local action="$2"

  printf '[bootstrap] error: %s\n' "${message}" >&2
  printf '[bootstrap] action: %s\n' "${action}" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run this script with sudo on the Ubuntu server"
  fi
}

require_ubuntu_2404() {
  if [[ ! -r /etc/os-release ]]; then
    die_action "cannot read /etc/os-release; this bootstrap targets Ubuntu Server 24.04 LTS" "run this on the target Ubuntu server, not on a laptop or recovery shell"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    die_action "this bootstrap targets Ubuntu Server 24.04 LTS; detected ${PRETTY_NAME:-unknown OS}" "install Ubuntu Server 24.04 LTS on the target machine, then rerun bootstrap"
  fi
}

require_supported_arch() {
  local arch
  arch="$(dpkg --print-architecture)"

  case "${arch}" in
    amd64|arm64)
      ;;
    *)
      die_action "unsupported CPU architecture '${arch}'" "use amd64 or arm64 hardware, or audit every pinned container image before extending support"
      ;;
  esac
}

detect_server_user() {
  local candidate="${SERVER_USER:-${SUDO_USER:-}}"

  if [[ -z "${candidate}" || "${candidate}" == "root" ]]; then
    die_action "could not detect a non-root operator account" "set SERVER_USER in bootstrap/env to the Ubuntu user created during installation"
  fi

  if ! id "${candidate}" >/dev/null 2>&1; then
    die_action "SERVER_USER '${candidate}' does not exist on this host" "edit bootstrap/env so SERVER_USER matches an existing non-root account"
  fi

  printf '%s\n' "${candidate}"
}

primary_ipv4() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i + 1)
          exit
        }
      }
    }
  '
}

default_iface() {
  ip route show default 2>/dev/null | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1) }'
}

default_gateway() {
  ip route show default 2>/dev/null | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1) }'
}

require_network_basics() {
  have_cmd ip || die_action "missing ip command" "install iproute2 or reinstall a standard Ubuntu Server image"

  if [[ -z "$(primary_ipv4)" ]]; then
    die_action "no primary IPv4 address detected" "connect Ethernet or configure networking during Ubuntu install, then verify with: ip -4 addr"
  fi

  if [[ -z "$(default_iface)" ]]; then
    die_action "no default network route detected" "configure the network gateway or DHCP, then verify with: ip route"
  fi

  if ! getent hosts download.docker.com >/dev/null 2>&1; then
    die_action "DNS cannot resolve download.docker.com" "fix DNS or internet connectivity, then verify with: getent hosts download.docker.com"
  fi
}

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { found = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      found = 1
      next
    }
    { print }
    END {
      if (found == 0) {
        print key "=" value
      }
    }
  ' "${file}" > "${tmp}"
  cat "${tmp}" > "${file}"
  rm -f "${tmp}"
}

resolve_operator_path() {
  local base_dir="$1"
  local path="$2"

  [[ -n "${path}" ]] || return 0

  if [[ "${path}" == /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${base_dir}" "${path}"
  fi
}

valid_gitea_repo_name() {
  local name="$1"

  [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  [[ "${name}" != *..* ]] || return 1
  [[ "${name}" != .* ]] || return 1
  [[ "${name}" != *. ]] || return 1
}

json_escape() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s\n' "${value}"
}

urlencode() {
  local value="$1"
  local length="${#value}"
  local index char

  for ((index = 0; index < length; index++)); do
    char="${value:index:1}"
    case "${char}" in
      [a-zA-Z0-9.~_-])
        printf '%s' "${char}"
        ;;
      *)
        printf '%%%02X' "'${char}"
        ;;
    esac
  done
}
