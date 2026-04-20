#!/usr/bin/env bash
set -Eeuo pipefail

APP_HOSTS="${APP_HOSTS:-gitea campsites}"

detect_os() {
  uname -s
}

default_iface_linux() {
  ip route show default 2>/dev/null | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1) }'
}

default_gateway_linux() {
  ip route show default 2>/dev/null | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1) }'
}

primary_ipv4_linux() {
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

default_iface_darwin() {
  route -n get default 2>/dev/null | awk '$1 == "interface:" { print $2 }'
}

default_gateway_darwin() {
  route -n get default 2>/dev/null | awk '$1 == "gateway:" { print $2 }'
}

primary_ipv4_darwin() {
  local iface="$1"
  [[ -n "${iface}" ]] || return 0
  ipconfig getifaddr "${iface}" 2>/dev/null || true
}

dns_servers_linux() {
  if command -v resolvectl >/dev/null 2>&1; then
    resolvectl dns 2>/dev/null | dns_servers_from_resolvectl_output
  else
    awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf 2>/dev/null | sort -u
  fi
}

dns_servers_from_resolvectl_output() {
  awk '
    {
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) {
          print $i
        } else if ($i ~ /^[0-9A-Fa-f:]+$/ && $i ~ /:/) {
          print $i
        }
      }
    }
  ' | sort -u
}

dns_servers_darwin() {
  scutil --dns 2>/dev/null | awk '$1 ~ /^nameserver/ { print $3 }' | sort -u
}

resolve_name() {
  local name="$1"

  if command -v getent >/dev/null 2>&1; then
    getent hosts "${name}" >/dev/null 2>&1
    return
  fi

  if command -v dscacheutil >/dev/null 2>&1; then
    [[ -n "$(dscacheutil -q host -a name "${name}" 2>/dev/null)" ]]
    return
  fi

  return 2
}

main() {
  local os iface ip gateway
  os="$(detect_os)"

  case "${os}" in
    Linux)
      iface="$(default_iface_linux)"
      ip="$(primary_ipv4_linux)"
      gateway="$(default_gateway_linux)"
      ;;
    Darwin)
      iface="$(default_iface_darwin)"
      ip="$(primary_ipv4_darwin "${iface}")"
      gateway="$(default_gateway_darwin)"
      ;;
    *)
      printf 'unsupported OS for network-info: %s\n' "${os}" >&2
      exit 1
      ;;
  esac

  printf 'host: %s\n' "$(hostname -s)"
  printf 'os: %s\n' "${os}"
  printf 'primary interface: %s\n' "${iface:-unknown}"
  printf 'primary IPv4: %s\n' "${ip:-unknown}"
  printf 'default gateway/router: %s\n' "${gateway:-unknown}"
  printf 'dns servers:\n'
  if [[ "${os}" == "Linux" ]]; then
    dns_servers_linux | sed 's/^/  - /'
  else
    dns_servers_darwin | sed 's/^/  - /'
  fi

  printf '\nname resolution:\n'
  local name
  for name in ${APP_HOSTS}; do
    if resolve_name "${name}"; then
      printf '  %s: resolves\n' "${name}"
    else
      printf '  %s: does not resolve\n' "${name}"
    fi
  done

  printf '\nrouter/local-DNS task for the server:\n'
  printf '  reserve the server MAC address to a stable IP\n'
  for name in ${APP_HOSTS}; do
    printf '  add %s -> <server-ip>\n' "${name}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
